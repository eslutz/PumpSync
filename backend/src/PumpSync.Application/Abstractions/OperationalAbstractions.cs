using PumpSync.Domain.Users;

namespace PumpSync.Application.Abstractions;

public interface IRateLimiter
{
    Task<bool> AllowAsync(UserId userId, string operation, int maxRequests, TimeSpan window, CancellationToken cancellationToken);
}

public interface IBackendModeProvider
{
    bool IsSelfHosted { get; }
}

public interface IIdempotencyStore
{
    Task<IdempotencyRecord?> TryGetAsync(UserId userId, string endpoint, string key, CancellationToken cancellationToken);

    Task StoreAsync(IdempotencyRecord record, CancellationToken cancellationToken);
}

public sealed record IdempotencyRecord(
    UserId UserId,
    string Endpoint,
    string Key,
    string RequestHash,
    string ResponseJson,
    DateTimeOffset ExpiresAt);
