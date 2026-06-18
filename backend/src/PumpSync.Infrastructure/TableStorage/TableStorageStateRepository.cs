using Azure;
using Azure.Data.Tables;
using Microsoft.Extensions.Options;
using PumpSync.Application.Abstractions;
using PumpSync.Domain.Billing;
using PumpSync.Domain.Sync;
using PumpSync.Domain.Users;
using PumpSync.Infrastructure.Options;

namespace PumpSync.Infrastructure.TableStorage;

public sealed class TableStorageStateRepository(TableClientFactory tables, IOptions<AzureStorageOptions> options) :
    IBillingEntitlementRepository,
    IInstallationRepository,
    ISyncStateRepository,
    IRateLimiter,
    IAppStoreNotificationIdempotencyStore
{
    private readonly AzureStorageOptions options = options.Value;

    public async Task<BillingEntitlement?> GetActiveEntitlementAsync(string originalTransactionId, CancellationToken cancellationToken)
    {
        try
        {
            var entity = await Entitlements.GetEntityAsync<SubscriptionEntitlementEntity>("appstore", originalTransactionId, cancellationToken: cancellationToken);
            var value = entity.Value;
            if (value.Status is not "Active" and not "GracePeriod")
            {
                return null;
            }

            if (value.ExpiresAt is { } expiresAt && expiresAt <= DateTimeOffset.UtcNow)
            {
                return null;
            }

            return value.ToDomain();
        }
        catch (RequestFailedException ex) when (ex.Status == 404)
        {
            return null;
        }
    }

    public async Task UpsertEntitlementAsync(BillingEntitlement entitlement, CancellationToken cancellationToken)
    {
        await Entitlements.UpsertEntityAsync(SubscriptionEntitlementEntity.FromDomain(entitlement), TableUpdateMode.Replace, cancellationToken);
    }

    public async Task UpsertInstallationAsync(string originalTransactionId, string installationId, DateTimeOffset seenAt, CancellationToken cancellationToken)
    {
        await Installations.UpsertEntityAsync(new InstallationEntity
        {
            PartitionKey = originalTransactionId,
            RowKey = installationId,
            CreatedAt = seenAt,
            LastSeenAt = seenAt
        }, TableUpdateMode.Merge, cancellationToken);

        await InstallationLookup.UpsertEntityAsync(new InstallationLookupEntity
        {
            PartitionKey = "installation",
            RowKey = installationId,
            OriginalTransactionId = originalTransactionId,
            LastSeenAt = seenAt
        }, TableUpdateMode.Replace, cancellationToken);
    }

    public async Task<string?> FindOriginalTransactionIdAsync(string installationId, CancellationToken cancellationToken)
    {
        try
        {
            var entity = await InstallationLookup.GetEntityAsync<InstallationLookupEntity>("installation", installationId, cancellationToken: cancellationToken);
            return entity.Value.OriginalTransactionId;
        }
        catch (RequestFailedException ex) when (ex.Status == 404)
        {
            return null;
        }
    }

    public async Task<SyncJob> RecordDirectSyncStartedAsync(UserId userId, string? deviceId, DateTimeOffset requestedAt, CancellationToken cancellationToken)
    {
        var jobId = Guid.CreateVersion7();
        await SyncAttempts.AddEntityAsync(new SyncAttemptEntity
        {
            PartitionKey = userId.ToString(),
            RowKey = $"{long.MaxValue - requestedAt.UtcTicks:D19}-{jobId:N}",
            JobId = jobId.ToString("N"),
            DeviceId = deviceId,
            RequestedAt = requestedAt,
            Status = SyncJobStatus.Running.ToString()
        }, cancellationToken);
        return new SyncJob(jobId, userId, deviceId, requestedAt, SyncJobStatus.Running);
    }

    public Task MarkSucceededAsync(Guid jobId, DateTimeOffset completedAt, CancellationToken cancellationToken) =>
        UpdateSyncJobAsync(jobId, SyncJobStatus.Succeeded.ToString(), completedAt, null, cancellationToken);

    public Task MarkFailedAsync(Guid jobId, string errorCode, CancellationToken cancellationToken) =>
        UpdateSyncJobAsync(jobId, SyncJobStatus.Failed.ToString(), DateTimeOffset.UtcNow, errorCode, cancellationToken);

    public async Task<DateTimeOffset?> GetLastSuccessfulSyncAsync(UserId userId, CancellationToken cancellationToken)
    {
        var filter = $"PartitionKey eq '{userId}' and Status eq 'Succeeded'";
        DateTimeOffset? latest = null;
        await foreach (var entity in SyncAttempts.QueryAsync<SyncAttemptEntity>(filter, cancellationToken: cancellationToken))
        {
            if (entity.CompletedAt is { } completedAt && (latest is null || completedAt > latest))
            {
                latest = completedAt;
            }
        }

        return latest;
    }

    public async Task<bool> AllowAsync(UserId userId, string operation, int maxRequests, TimeSpan window, CancellationToken cancellationToken)
    {
        var now = DateTimeOffset.UtcNow;
        var bucketStart = new DateTimeOffset(now.Year, now.Month, now.Day, now.Hour, 0, 0, TimeSpan.Zero);
        var partitionKey = $"{userId}:{operation}";
        var rowKey = bucketStart.ToString("yyyyMMddHH");

        try
        {
            var response = await RateLimitBuckets.GetEntityAsync<RateLimitBucketEntity>(partitionKey, rowKey, cancellationToken: cancellationToken);
            var entity = response.Value;
            if (entity.Count >= maxRequests)
            {
                return false;
            }

            entity.Count++;
            await RateLimitBuckets.UpdateEntityAsync(entity, response.Value.ETag, TableUpdateMode.Replace, cancellationToken);
            return true;
        }
        catch (RequestFailedException ex) when (ex.Status == 404)
        {
            await RateLimitBuckets.AddEntityAsync(new RateLimitBucketEntity
            {
                PartitionKey = partitionKey,
                RowKey = rowKey,
                Count = 1,
                ExpiresAt = bucketStart.Add(window)
            }, cancellationToken);
            return true;
        }
    }

    public async Task<bool> TryRecordAsync(string notificationId, DateTimeOffset receivedAt, CancellationToken cancellationToken)
    {
        try
        {
            await NotificationIdempotency.AddEntityAsync(new NotificationEntity
            {
                PartitionKey = "appstore-notifications",
                RowKey = notificationId,
                ReceivedAt = receivedAt
            }, cancellationToken);
            return true;
        }
        catch (RequestFailedException ex) when (ex.Status == 409)
        {
            return false;
        }
    }

    private async Task UpdateSyncJobAsync(Guid jobId, string status, DateTimeOffset completedAt, string? error, CancellationToken cancellationToken)
    {
        var suffix = jobId.ToString("N");
        await foreach (var entity in SyncAttempts.QueryAsync<SyncAttemptEntity>(x => x.JobId == suffix, cancellationToken: cancellationToken))
        {
            entity.Status = status;
            entity.CompletedAt = completedAt;
            entity.LastError = error;
            await SyncAttempts.UpdateEntityAsync(entity, entity.ETag, TableUpdateMode.Replace, cancellationToken);
            return;
        }
    }

    private TableClient Entitlements => tables.CreateClient(options.SubscriptionEntitlementsTableName);
    private TableClient Installations => tables.CreateClient(options.InstallationsTableName);
    private TableClient InstallationLookup => tables.CreateClient(options.InstallationLookupTableName);
    private TableClient SyncAttempts => tables.CreateClient(options.SyncAttemptsTableName);
    private TableClient RateLimitBuckets => tables.CreateClient(options.RateLimitBucketsTableName);
    private TableClient NotificationIdempotency => tables.CreateClient(options.AppStoreNotificationIdempotencyTableName);

    private sealed class SubscriptionEntitlementEntity : ITableEntity
    {
        public string PartitionKey { get; set; } = string.Empty;
        public string RowKey { get; set; } = string.Empty;
        public DateTimeOffset? Timestamp { get; set; }
        public ETag ETag { get; set; }
        public string ProductId { get; set; } = string.Empty;
        public string Status { get; set; } = string.Empty;
        public string Environment { get; set; } = string.Empty;
        public DateTimeOffset? ExpiresAt { get; set; }
        public DateTimeOffset UpdatedAt { get; set; }

        public BillingEntitlement ToDomain() => new(
            RowKey,
            ProductId,
            Enum.Parse<BillingEntitlementStatus>(Status),
            Environment,
            ExpiresAt,
            UpdatedAt);

        public static SubscriptionEntitlementEntity FromDomain(BillingEntitlement entitlement) => new()
        {
            PartitionKey = "appstore",
            RowKey = entitlement.OriginalTransactionId,
            ProductId = entitlement.ProductId,
            Status = entitlement.Status.ToString(),
            Environment = entitlement.Environment,
            ExpiresAt = entitlement.ExpiresAt,
            UpdatedAt = entitlement.UpdatedAt
        };
    }

    private sealed class InstallationEntity : ITableEntity
    {
        public string PartitionKey { get; set; } = string.Empty;
        public string RowKey { get; set; } = string.Empty;
        public DateTimeOffset? Timestamp { get; set; }
        public ETag ETag { get; set; }
        public DateTimeOffset CreatedAt { get; set; }
        public DateTimeOffset LastSeenAt { get; set; }
    }

    private sealed class InstallationLookupEntity : ITableEntity
    {
        public string PartitionKey { get; set; } = string.Empty;
        public string RowKey { get; set; } = string.Empty;
        public DateTimeOffset? Timestamp { get; set; }
        public ETag ETag { get; set; }
        public string OriginalTransactionId { get; set; } = string.Empty;
        public DateTimeOffset LastSeenAt { get; set; }
    }

    private sealed class SyncAttemptEntity : ITableEntity
    {
        public string PartitionKey { get; set; } = string.Empty;
        public string RowKey { get; set; } = string.Empty;
        public DateTimeOffset? Timestamp { get; set; }
        public ETag ETag { get; set; }
        public string JobId { get; set; } = string.Empty;
        public string? DeviceId { get; set; }
        public DateTimeOffset RequestedAt { get; set; }
        public DateTimeOffset? CompletedAt { get; set; }
        public string Status { get; set; } = string.Empty;
        public string? LastError { get; set; }
    }

    private sealed class RateLimitBucketEntity : ITableEntity
    {
        public string PartitionKey { get; set; } = string.Empty;
        public string RowKey { get; set; } = string.Empty;
        public DateTimeOffset? Timestamp { get; set; }
        public ETag ETag { get; set; }
        public int Count { get; set; }
        public DateTimeOffset ExpiresAt { get; set; }
    }

    private sealed class NotificationEntity : ITableEntity
    {
        public string PartitionKey { get; set; } = string.Empty;
        public string RowKey { get; set; } = string.Empty;
        public DateTimeOffset? Timestamp { get; set; }
        public ETag ETag { get; set; }
        public DateTimeOffset ReceivedAt { get; set; }
    }
}
