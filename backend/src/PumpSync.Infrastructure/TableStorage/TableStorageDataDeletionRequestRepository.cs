using System.Text.Json;
using Azure;
using Azure.Data.Tables;
using Microsoft.Extensions.Options;
using PumpSync.Application.Abstractions;
using PumpSync.Domain.Users;
using PumpSync.Infrastructure.Options;

namespace PumpSync.Infrastructure.TableStorage;

public sealed class TableStorageDataDeletionRequestRepository(
    TableClientFactory tables,
    IOptions<AzureStorageOptions> options) : IHostedDataDeletionRequestRepository
{
    private readonly AzureStorageOptions options = options.Value;

    public async Task<HostedDataDeletionInstallationLinks> FindInstallationLinksAsync(
        string installationId,
        CancellationToken cancellationToken)
    {
        var records = new List<HostedDataDeletionRecord>();
        var originalTransactionIds = new HashSet<string>(StringComparer.Ordinal);

        var lookup = await TryGetAsync(InstallationLookup, "installation", installationId, cancellationToken);
        if (lookup is not null)
        {
            records.Add(ToRecord(options.InstallationLookupTableName, lookup));
            if (lookup.TryGetValue("OriginalTransactionId", out var originalTransactionId) &&
                originalTransactionId is string value &&
                !string.IsNullOrWhiteSpace(value))
            {
                originalTransactionIds.Add(value);
            }
        }

        var installationFilter = $"RowKey eq '{EscapeODataString(installationId)}'";
        await foreach (var entity in Installations.QueryAsync<TableEntity>(installationFilter, cancellationToken: cancellationToken))
        {
            records.Add(ToRecord(options.InstallationsTableName, entity));
            if (!string.IsNullOrWhiteSpace(entity.PartitionKey))
            {
                originalTransactionIds.Add(entity.PartitionKey);
            }
        }

        return new HostedDataDeletionInstallationLinks(
            originalTransactionIds.Order(StringComparer.Ordinal).ToArray(),
            records);
    }

    public async Task<IReadOnlyList<HostedDataDeletionRecord>> FindSubscriptionEntitlementRecordsAsync(
        IReadOnlyCollection<string> originalTransactionIds,
        CancellationToken cancellationToken)
    {
        var records = new List<HostedDataDeletionRecord>();
        foreach (var originalTransactionId in originalTransactionIds)
        {
            var entity = await TryGetAsync(Entitlements, "appstore", originalTransactionId, cancellationToken);
            if (entity is not null)
            {
                records.Add(ToRecord(options.SubscriptionEntitlementsTableName, entity));
            }
        }

        return records;
    }

    public async Task<IReadOnlyList<HostedDataDeletionRecord>> FindHostedUserRecordsAsync(
        IReadOnlyCollection<UserId> hostedUserIds,
        CancellationToken cancellationToken)
    {
        var records = new List<HostedDataDeletionRecord>();
        foreach (var hostedUserId in hostedUserIds)
        {
            var userPartitionKey = hostedUserId.ToString();
            var syncFilter = $"PartitionKey eq '{EscapeODataString(userPartitionKey)}'";
            await foreach (var entity in SyncAttempts.QueryAsync<TableEntity>(syncFilter, cancellationToken: cancellationToken))
            {
                records.Add(ToRecord(options.SyncAttemptsTableName, entity));
            }

            var rateLimitPrefix = $"{userPartitionKey}:";
            var rateLimitFilter = $"PartitionKey ge '{EscapeODataString(rateLimitPrefix)}' and PartitionKey lt '{EscapeODataString(rateLimitPrefix + "~")}'";
            await foreach (var entity in RateLimitBuckets.QueryAsync<TableEntity>(rateLimitFilter, cancellationToken: cancellationToken))
            {
                records.Add(ToRecord(options.RateLimitBucketsTableName, entity));
            }
        }

        return records;
    }

    public async Task DeleteRecordsAsync(IReadOnlyCollection<HostedDataDeletionRecord> records, CancellationToken cancellationToken)
    {
        foreach (var record in records.DistinctBy(record => (record.TableName, record.PartitionKey, record.RowKey)))
        {
            var table = tables.CreateClient(record.TableName);
            try
            {
                await table.DeleteEntityAsync(record.PartitionKey, record.RowKey, ETag.All, cancellationToken);
            }
            catch (RequestFailedException ex) when (ex.Status == 404)
            {
                // Deletion requests are idempotent from the support operator's perspective.
            }
        }
    }

    public async Task RecordAuditEventAsync(HostedDataDeletionAuditEvent auditEvent, CancellationToken cancellationToken)
    {
        var entity = new TableEntity("data-deletion-request", auditEvent.EventId)
        {
            ["OccurredAt"] = auditEvent.OccurredAt,
            ["Environment"] = auditEvent.Environment,
            ["Status"] = auditEvent.Status,
            ["ToolName"] = "PumpSync.DataDeletionRequest",
            ["InstallationIdHash"] = auditEvent.InstallationIdHash,
            ["Found"] = auditEvent.Found,
            ["Purged"] = auditEvent.Purged,
            ["TablesJson"] = JsonSerializer.Serialize(auditEvent.Tables)
        };

        await AuditEvents.AddEntityAsync(entity, cancellationToken);
    }

    private async Task<TableEntity?> TryGetAsync(
        TableClient table,
        string partitionKey,
        string rowKey,
        CancellationToken cancellationToken)
    {
        try
        {
            var response = await table.GetEntityAsync<TableEntity>(partitionKey, rowKey, cancellationToken: cancellationToken);
            return response.Value;
        }
        catch (RequestFailedException ex) when (ex.Status == 404)
        {
            return null;
        }
    }

    private static HostedDataDeletionRecord ToRecord(string tableName, TableEntity entity) =>
        new(tableName, entity.PartitionKey, entity.RowKey);

    private static string EscapeODataString(string value) => value.Replace("'", "''", StringComparison.Ordinal);

    private TableClient Entitlements => tables.CreateClient(options.SubscriptionEntitlementsTableName);
    private TableClient Installations => tables.CreateClient(options.InstallationsTableName);
    private TableClient InstallationLookup => tables.CreateClient(options.InstallationLookupTableName);
    private TableClient SyncAttempts => tables.CreateClient(options.SyncAttemptsTableName);
    private TableClient RateLimitBuckets => tables.CreateClient(options.RateLimitBucketsTableName);
    private TableClient AuditEvents => tables.CreateClient(options.AuditEventsTableName);
}
