using PumpSync.Domain.Billing;
using PumpSync.Domain.Samples;
using PumpSync.Domain.Sync;
using PumpSync.Domain.Users;

namespace PumpSync.Application.Abstractions;

public interface IBillingEntitlementRepository
{
    Task<BillingEntitlement?> GetActiveEntitlementAsync(string originalTransactionId, CancellationToken cancellationToken);

    Task UpsertEntitlementAsync(BillingEntitlement entitlement, CancellationToken cancellationToken);
}

public interface IInstallationRepository
{
    Task UpsertInstallationAsync(string originalTransactionId, string installationId, DateTimeOffset seenAt, CancellationToken cancellationToken);

    Task<string?> FindOriginalTransactionIdAsync(string installationId, CancellationToken cancellationToken);
}

public interface ISyncStateRepository
{
    Task<SyncJob> RecordDirectSyncStartedAsync(UserId userId, string? deviceId, DateTimeOffset requestedAt, CancellationToken cancellationToken);

    Task MarkSucceededAsync(Guid jobId, DateTimeOffset completedAt, CancellationToken cancellationToken);

    Task MarkFailedAsync(Guid jobId, string errorCode, CancellationToken cancellationToken);

    Task<DateTimeOffset?> GetLastSuccessfulSyncAsync(UserId userId, CancellationToken cancellationToken);
}

public interface IAppStoreNotificationIdempotencyStore
{
    Task<bool> TryRecordAsync(string notificationId, DateTimeOffset receivedAt, CancellationToken cancellationToken);
}
