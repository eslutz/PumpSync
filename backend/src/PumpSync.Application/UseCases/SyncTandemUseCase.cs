using PumpSync.ApiContracts;
using PumpSync.Application.Abstractions;
using PumpSync.Application.Mapping;
using PumpSync.Application.Validation;
using PumpSync.Domain.Auth;
using PumpSync.Domain.Common;
using PumpSync.Domain.Tandem;

namespace PumpSync.Application.UseCases;

public sealed class SyncTandemUseCase(
    IRateLimiter rateLimiter,
    ITandemEventClient tandemEvents,
    ISampleNormalizer normalizer,
    ISyncStateRepository syncState,
    IClock clock)
{
    public async Task<TandemSyncResponse> ExecuteAsync(
        AuthenticatedUser user,
        TandemSyncRequest request,
        CancellationToken cancellationToken)
    {
        TandemSyncRequestValidator.Validate(request, clock.UtcNow);

        var allowed = await rateLimiter.AllowAsync(user.UserId, "sync-tandem", 12, TimeSpan.FromHours(1), cancellationToken);
        if (!allowed)
        {
            throw new InvalidOperationException("Tandem sync rate limit exceeded.");
        }

        var credentials = new TandemCredentials(
            request.Tandem.Username,
            request.Tandem.Password,
            TandemRegionParser.Parse(request.Tandem.Region));

        var started = await syncState.RecordDirectSyncStartedAsync(user.UserId, request.DeviceId, clock.UtcNow, cancellationToken);
        try
        {
            var events = await tandemEvents.FetchEventsAsync(
                credentials,
                new TandemSyncWindow(request.DeviceId, request.MinDate, request.MaxDate),
                cancellationToken);
            var samples = normalizer.Normalize(user.UserId, events);
            await syncState.MarkSucceededAsync(started.JobId, clock.UtcNow, cancellationToken);

            return new TandemSyncResponse(
                samples.LastOrDefault()?.Cursor,
                samples.Select(x => x.ToDto()).ToArray());
        }
        catch (Exception ex)
        {
            await syncState.MarkFailedAsync(started.JobId, ex.GetType().Name, cancellationToken);
            throw;
        }
    }
}
