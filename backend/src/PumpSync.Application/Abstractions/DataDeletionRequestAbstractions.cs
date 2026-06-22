using PumpSync.Domain.Users;

namespace PumpSync.Application.Abstractions;

public interface IHostedDataDeletionRequestRepository
{
    Task<HostedDataDeletionInstallationLinks> FindInstallationLinksAsync(string installationId, CancellationToken cancellationToken);

    Task<IReadOnlyList<HostedDataDeletionRecord>> FindSubscriptionEntitlementRecordsAsync(
        IReadOnlyCollection<string> originalTransactionIds,
        CancellationToken cancellationToken);

    Task<IReadOnlyList<HostedDataDeletionRecord>> FindHostedUserRecordsAsync(
        IReadOnlyCollection<UserId> hostedUserIds,
        CancellationToken cancellationToken);

    Task DeleteRecordsAsync(IReadOnlyCollection<HostedDataDeletionRecord> records, CancellationToken cancellationToken);

    Task RecordAuditEventAsync(HostedDataDeletionAuditEvent auditEvent, CancellationToken cancellationToken);
}

public interface IDataDeletionAuditHasher
{
    string HashInstallationId(string installationId);
}

public sealed record HostedDataDeletionInstallationLinks(
    IReadOnlyList<string> OriginalTransactionIds,
    IReadOnlyList<HostedDataDeletionRecord> Records);

public sealed record HostedDataDeletionRecord(
    string TableName,
    string PartitionKey,
    string RowKey);

public sealed record HostedDataDeletionTableCount(int Found, int Purged);

public sealed record HostedDataDeletionAuditEvent(
    string EventId,
    DateTimeOffset OccurredAt,
    string Environment,
    string Status,
    string InstallationIdHash,
    IReadOnlyList<string> OriginalTransactionIds,
    int Found,
    int Purged,
    IReadOnlyDictionary<string, HostedDataDeletionTableCount> Tables);
