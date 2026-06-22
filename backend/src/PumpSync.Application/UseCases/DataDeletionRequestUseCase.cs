using PumpSync.Application.Abstractions;
using PumpSync.Domain.Common;

namespace PumpSync.Application.UseCases;

public sealed class DataDeletionRequestUseCase(
    IHostedDataDeletionRequestRepository repository,
    IDataDeletionAuditHasher auditHasher,
    IClock clock)
{
    public async Task<HostedDataDeletionReport> ExecuteAsync(
        HostedDataDeletionRequest request,
        CancellationToken cancellationToken)
    {
        var installationId = request.InstallationId.Trim();
        if (string.IsNullOrWhiteSpace(installationId))
        {
            throw new ArgumentException("Installation id is required.", nameof(request));
        }

        var environment = request.Environment.Trim().ToLowerInvariant();
        if (environment is not "nonprod" and not "prod")
        {
            throw new ArgumentException("Environment must be either nonprod or prod.", nameof(request));
        }

        var installationLinks = await repository.FindInstallationLinksAsync(installationId, cancellationToken);
        var originalTransactionIds = installationLinks.OriginalTransactionIds
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Distinct(StringComparer.Ordinal)
            .Order(StringComparer.Ordinal)
            .ToArray();

        var records = new List<HostedDataDeletionRecord>(installationLinks.Records);
        records.AddRange(await repository.FindSubscriptionEntitlementRecordsAsync(originalTransactionIds, cancellationToken));

        var hostedUserIds = originalTransactionIds
            .Select(originalTransactionId => SubjectIdentity.Hosted(originalTransactionId, installationId).UserId)
            .Distinct()
            .ToArray();
        records.AddRange(await repository.FindHostedUserRecordsAsync(hostedUserIds, cancellationToken));

        var distinctRecords = records
            .DistinctBy(record => (record.TableName, record.PartitionKey, record.RowKey))
            .OrderBy(record => record.TableName, StringComparer.Ordinal)
            .ThenBy(record => record.PartitionKey, StringComparer.Ordinal)
            .ThenBy(record => record.RowKey, StringComparer.Ordinal)
            .ToArray();

        var status = distinctRecords.Length == 0
            ? HostedDataDeletionStatus.NoRecordsFound
            : request.Execute ? HostedDataDeletionStatus.Purged : HostedDataDeletionStatus.DryRun;
        var purgedRecords = Array.Empty<HostedDataDeletionRecord>();
        string? auditEventId = null;

        if (request.Execute)
        {
            await repository.DeleteRecordsAsync(distinctRecords, cancellationToken);
            purgedRecords = distinctRecords;
            var occurredAt = clock.UtcNow;
            auditEventId = CreateAuditEventId(occurredAt);
            await repository.RecordAuditEventAsync(
                new HostedDataDeletionAuditEvent(
                    auditEventId,
                    occurredAt,
                    environment,
                    status,
                    auditHasher.HashInstallationId(installationId),
                    originalTransactionIds,
                    distinctRecords.Length,
                    purgedRecords.Length,
                    BuildTableCounts(distinctRecords, purgedRecords)),
                cancellationToken);
        }

        return new HostedDataDeletionReport(
            status,
            request.Execute,
            environment,
            installationId,
            originalTransactionIds,
            auditEventId,
            distinctRecords.Length,
            purgedRecords.Length,
            BuildTableCounts(distinctRecords, purgedRecords));
    }

    private static IReadOnlyDictionary<string, HostedDataDeletionTableCount> BuildTableCounts(
        IReadOnlyCollection<HostedDataDeletionRecord> foundRecords,
        IReadOnlyCollection<HostedDataDeletionRecord> purgedRecords)
    {
        var tableNames = foundRecords
            .Select(record => record.TableName)
            .Concat(purgedRecords.Select(record => record.TableName))
            .Distinct(StringComparer.Ordinal)
            .Order(StringComparer.Ordinal);

        return tableNames.ToDictionary(
            tableName => tableName,
            tableName => new HostedDataDeletionTableCount(
                foundRecords.Count(record => string.Equals(record.TableName, tableName, StringComparison.Ordinal)),
                purgedRecords.Count(record => string.Equals(record.TableName, tableName, StringComparison.Ordinal))),
            StringComparer.Ordinal);
    }

    private static string CreateAuditEventId(DateTimeOffset occurredAt) =>
        $"{occurredAt.UtcDateTime:yyyyMMddHHmmssfffffff}-{Guid.CreateVersion7():N}";
}

public sealed record HostedDataDeletionRequest(
    string InstallationId,
    string Environment,
    bool Execute);

public sealed record HostedDataDeletionReport(
    string Status,
    bool Execute,
    string Environment,
    string InstallationId,
    IReadOnlyList<string> OriginalTransactionIds,
    string? AuditEventId,
    int Found,
    int Purged,
    IReadOnlyDictionary<string, HostedDataDeletionTableCount> Tables);

public static class HostedDataDeletionStatus
{
    public const string NoRecordsFound = "no_records_found";
    public const string DryRun = "dry_run";
    public const string Purged = "purged";
}
