using PumpSync.Application.Abstractions;
using PumpSync.Domain.Tandem;
using PumpSync.Infrastructure.Options;
using PumpSync.Infrastructure.Tandem.Parsing;
using Microsoft.Extensions.Options;
using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;

namespace PumpSync.Infrastructure.Tandem;

public sealed class TandemEventClient(
    HttpClient httpClient,
    ITandemAuthenticator authenticator,
    IOptions<TandemSourceOptions> options) : ITandemEventClient
{
    private static readonly int[] PumpSyncEventIds = [3, 20, 21, 64, 65, 66, 279];

    public async Task<IReadOnlyList<TandemEvent>> FetchEventsAsync(
        TandemCredentials credentials,
        TandemSyncWindow syncWindow,
        CancellationToken cancellationToken)
    {
        for (var attempt = 0; ; attempt++)
        {
            try
            {
                return await FetchWithFreshSessionAsync(credentials, syncWindow, cancellationToken);
            }
            catch (HttpRequestException ex) when (ex.StatusCode == HttpStatusCode.Unauthorized && attempt == 0)
            {
            }
        }
    }

    private async Task<IReadOnlyList<TandemEvent>> FetchWithFreshSessionAsync(
        TandemCredentials credentials,
        TandemSyncWindow syncWindow,
        CancellationToken cancellationToken)
    {
        var session = await authenticator.LoginAsync(credentials, cancellationToken);
        var region = session.Region is TandemRegion.Eu ? options.Value.Eu : options.Value.Us;
        var metadata = await GetPumpEventMetadataAsync(region, session, cancellationToken);
        var deviceId = SelectDeviceId(metadata, syncWindow.DeviceId);
        var raw = await GetPumpEventsRawAsync(region, session, deviceId, syncWindow.MinDate, syncWindow.MaxDate, cancellationToken);

        var decoder = new TandemRawEventDecoder(options);
        var mapper = new TandemDomainEventMapper();
        return mapper.Map(decoder.Decode(raw), deviceId, syncWindow.MaxDate);
    }

    private async Task<IReadOnlyList<PumpEventMetadata>> GetPumpEventMetadataAsync(
        TandemRegionOptions region,
        TandemSession session,
        CancellationToken cancellationToken)
    {
        using var document = await GetJsonAsync(
            region,
            session,
            $"api/reports/reportsfacade/{Uri.EscapeDataString(session.PumperId)}/pumpeventmetadata",
            cancellationToken);

        if (document.RootElement.ValueKind != JsonValueKind.Array)
        {
            throw new InvalidOperationException("Tandem pump metadata response was not an array.");
        }

        var devices = new List<PumpEventMetadata>();
        foreach (var item in document.RootElement.EnumerateArray())
        {
            if (!item.TryGetProperty("tconnectDeviceId", out var idElement))
            {
                continue;
            }

            var id = idElement.GetString();
            if (string.IsNullOrWhiteSpace(id))
            {
                continue;
            }

            devices.Add(new PumpEventMetadata(
                id,
                TryReadDate(item, "maxDateWithEvents"),
                TryReadLastUploadDate(item)));
        }

        return devices;
    }

    private async Task<string> GetPumpEventsRawAsync(
        TandemRegionOptions region,
        TandemSession session,
        string deviceId,
        DateTimeOffset? minDate,
        DateTimeOffset? maxDate,
        CancellationToken cancellationToken)
    {
        var minDateString = FormatDate(minDate ?? DateTimeOffset.UtcNow.AddDays(-2));
        var maxDateString = FormatDate(maxDate ?? DateTimeOffset.UtcNow);
        var eventIds = string.Join("%2C", PumpSyncEventIds);
        var endpoint = $"api/reports/reportsfacade/pumpevents/{Uri.EscapeDataString(session.PumperId)}/{Uri.EscapeDataString(deviceId)}" +
            $"?minDate={Uri.EscapeDataString(minDateString)}&maxDate={Uri.EscapeDataString(maxDateString)}&eventIds={eventIds}";

        using var response = await SendWithRetryAsync(region, session, endpoint, cancellationToken);
        var body = await response.Content.ReadAsStringAsync(cancellationToken);
        using var document = JsonDocument.Parse(body);
        return document.RootElement.ValueKind == JsonValueKind.String
            ? document.RootElement.GetString() ?? string.Empty
            : body.Trim('"');
    }

    private async Task<JsonDocument> GetJsonAsync(
        TandemRegionOptions region,
        TandemSession session,
        string endpoint,
        CancellationToken cancellationToken)
    {
        using var response = await SendWithRetryAsync(region, session, endpoint, cancellationToken);
        return await JsonDocument.ParseAsync(await response.Content.ReadAsStreamAsync(cancellationToken), cancellationToken: cancellationToken);
    }

    private async Task<HttpResponseMessage> SendWithRetryAsync(
        TandemRegionOptions region,
        TandemSession session,
        string endpoint,
        CancellationToken cancellationToken)
    {
        for (var attempt = 0; ; attempt++)
        {
            var response = await SendAsync(region, session, endpoint, cancellationToken);
            if (response.IsSuccessStatusCode)
            {
                return response;
            }

            if (!ShouldRetry(response, attempt, out var delay))
            {
                var statusCode = response.StatusCode;
                response.Dispose();
                throw new HttpRequestException($"Tandem Source request failed with HTTP {(int)statusCode}.", null, statusCode);
            }

            response.Dispose();
            await Task.Delay(delay, cancellationToken);
        }
    }

    private async Task<HttpResponseMessage> SendAsync(
        TandemRegionOptions region,
        TandemSession session,
        string endpoint,
        CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, new Uri(new Uri(region.SourceUrl), endpoint));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", session.AccessToken);
        request.Headers.TryAddWithoutValidation("Origin", "https://tconnect.tandemdiabetes.com");
        request.Headers.TryAddWithoutValidation("Referer", "https://tconnect.tandemdiabetes.com/");
        return await httpClient.SendAsync(request, cancellationToken);
    }

    private static bool ShouldRetry(HttpResponseMessage response, int attempt, out TimeSpan delay)
    {
        delay = TimeSpan.Zero;
        if (attempt >= 2)
        {
            return false;
        }

        if (response.StatusCode is HttpStatusCode.TooManyRequests && response.Headers.RetryAfter?.Delta is { } retryAfter)
        {
            delay = retryAfter;
            return true;
        }

        if (response.StatusCode is HttpStatusCode.InternalServerError or HttpStatusCode.BadGateway or HttpStatusCode.ServiceUnavailable or HttpStatusCode.GatewayTimeout)
        {
            delay = TimeSpan.FromMilliseconds(250 * Math.Pow(2, attempt));
            return true;
        }

        return false;
    }

    private static string SelectDeviceId(IReadOnlyList<PumpEventMetadata> metadata, string? requestedDeviceId)
    {
        if (!string.IsNullOrWhiteSpace(requestedDeviceId))
        {
            if (metadata.Any(x => string.Equals(x.DeviceId, requestedDeviceId, StringComparison.Ordinal)))
            {
                return requestedDeviceId;
            }

            throw new InvalidOperationException("Requested Tandem device was not found for this account.");
        }

        return metadata
            .OrderByDescending(x => x.MaxDateWithEvents ?? x.LastUploadAt ?? DateTimeOffset.MinValue)
            .FirstOrDefault()?.DeviceId
            ?? throw new InvalidOperationException("No Tandem device metadata was returned for this account.");
    }

    private static DateTimeOffset? TryReadDate(JsonElement item, string propertyName)
    {
        if (!item.TryGetProperty(propertyName, out var value) || value.ValueKind != JsonValueKind.String)
        {
            return null;
        }

        return DateTimeOffset.TryParse(value.GetString(), out var parsed) ? parsed : null;
    }

    private static DateTimeOffset? TryReadLastUploadDate(JsonElement item)
    {
        if (!item.TryGetProperty("lastUpload", out var lastUpload) || lastUpload.ValueKind != JsonValueKind.Object)
        {
            return null;
        }

        foreach (var property in lastUpload.EnumerateObject())
        {
            if (property.Value.ValueKind == JsonValueKind.String && DateTimeOffset.TryParse(property.Value.GetString(), out var parsed))
            {
                return parsed;
            }
        }

        return null;
    }

    private static string FormatDate(DateTimeOffset value) => value.UtcDateTime.ToString("yyyy-MM-dd");

    private sealed record PumpEventMetadata(
        string DeviceId,
        DateTimeOffset? MaxDateWithEvents,
        DateTimeOffset? LastUploadAt);
}
