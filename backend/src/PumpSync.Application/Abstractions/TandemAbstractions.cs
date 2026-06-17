using PumpSync.Domain.Tandem;
using PumpSync.Domain.Users;

namespace PumpSync.Application.Abstractions;

public interface ITandemAuthenticator
{
    Task<TandemSession> LoginAsync(TandemCredentials credentials, CancellationToken cancellationToken);
}

public interface ITandemEventClient
{
    Task<IReadOnlyList<TandemEvent>> FetchEventsAsync(TandemCredentials credentials, TandemSyncWindow syncWindow, CancellationToken cancellationToken);
}

public interface ISampleNormalizer
{
    IReadOnlyList<Domain.Samples.NormalizedSample> Normalize(UserId userId, IReadOnlyList<TandemEvent> events);
}

public sealed record TandemSession(
    TandemRegion Region,
    string AccessToken,
    string PumperId,
    string AccountId,
    string? DefaultDeviceId,
    DateTimeOffset ExpiresAt);

public sealed record TandemCredentials(
    string Username,
    string Password,
    TandemRegion Region)
{
    public override string ToString() => $"TandemCredentials(Username=<redacted>, Region={Region})";
}

public sealed record TandemSyncWindow(
    string? DeviceId,
    DateTimeOffset? MinDate,
    DateTimeOffset? MaxDate);
