using System.Net;
using Microsoft.Extensions.Options;
using PumpSync.Application.Abstractions;
using PumpSync.Domain.Tandem;
using PumpSync.Infrastructure.Options;
using PumpSync.Infrastructure.Tandem;
using Xunit;

namespace PumpSync.Tests;

public sealed class TandemEventClientTests
{
    [Fact]
    public async Task FetchEventsAsync_AcceptsNumericTandemDeviceIds()
    {
        var handler = new FakeTandemHandler(new Queue<string>([
            """
            [
              {
                "tconnectDeviceId": 12345,
                "maxDateWithEvents": "2026-06-20T12:00:00Z"
              }
            ]
            """,
            "\"\""
        ]));
        var options = Options.Create(new TandemSourceOptions
        {
            Us = new TandemRegionOptions { SourceUrl = "https://source.example/" }
        });
        var client = new TandemEventClient(
            new HttpClient(handler),
            new FakeTandemAuthenticator(),
            options);

        var events = await client.FetchEventsAsync(
            new TandemCredentials("user@example.com", "password", TandemRegion.Us),
            new TandemSyncWindow(null, DateTimeOffset.Parse("2026-06-20T00:00:00Z"), DateTimeOffset.Parse("2026-06-21T00:00:00Z")),
            CancellationToken.None);

        Assert.Empty(events);
        Assert.Contains(handler.RequestUris, uri => uri.AbsolutePath.Contains("/pumpevents/pumper-1/12345", StringComparison.Ordinal));
    }

    private sealed class FakeTandemAuthenticator : ITandemAuthenticator
    {
        public Task<TandemSession> LoginAsync(TandemCredentials credentials, CancellationToken cancellationToken) =>
            Task.FromResult(new TandemSession(
                TandemRegion.Us,
                "access-token",
                "pumper-1",
                "account-1",
                null,
                DateTimeOffset.UtcNow.AddHours(1)));
    }

    private sealed class FakeTandemHandler(Queue<string> responses) : HttpMessageHandler
    {
        public List<Uri> RequestUris { get; } = [];

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            RequestUris.Add(request.RequestUri ?? throw new InvalidOperationException("Request URI was missing."));
            var response = responses.Dequeue();
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(response)
            });
        }
    }
}
