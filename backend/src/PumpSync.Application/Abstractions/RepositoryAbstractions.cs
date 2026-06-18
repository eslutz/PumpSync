using PumpSync.Domain.Auth;
using PumpSync.Domain.Billing;
using PumpSync.Domain.Samples;
using PumpSync.Domain.Sync;
using PumpSync.Domain.Users;

namespace PumpSync.Application.Abstractions;

public interface IUserRepository
{
    Task<(UserId UserId, string? Email)> UpsertAppleUserAsync(AppleIdentity identity, CancellationToken cancellationToken);

    Task<(UserId UserId, string AppleSubject)?> FindByIdAsync(UserId userId, CancellationToken cancellationToken);

    Task SetAppleEmailForwardingAsync(string appleSubject, string? email, bool enabled, CancellationToken cancellationToken);

    Task SetAppleUserStatusAsync(string appleSubject, string status, CancellationToken cancellationToken);
}

public interface IBillingEntitlementRepository
{
    Task<BillingEntitlement?> GetActiveEntitlementAsync(UserId userId, CancellationToken cancellationToken);
}

public interface ISyncStateRepository
{
    Task<SyncJob> RecordDirectSyncStartedAsync(UserId userId, string? deviceId, DateTimeOffset requestedAt, CancellationToken cancellationToken);

    Task MarkSucceededAsync(Guid jobId, DateTimeOffset completedAt, CancellationToken cancellationToken);

    Task MarkFailedAsync(Guid jobId, string errorCode, CancellationToken cancellationToken);

    Task<DateTimeOffset?> GetLastSuccessfulSyncAsync(UserId userId, CancellationToken cancellationToken);
}
