using PumpSync.Application.Abstractions;
using PumpSync.Domain.Sync;
using PumpSync.Domain.Users;

namespace PumpSync.Infrastructure.Sql;

public sealed class SqlSyncStateRepository(SqlConnectionFactory connections) : ISyncStateRepository
{
    public async Task<SyncJob> RecordDirectSyncStartedAsync(UserId userId, string? deviceId, DateTimeOffset requestedAt, CancellationToken cancellationToken)
    {
        await using var connection = await connections.OpenAsync(cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandText = """
INSERT INTO dbo.SyncJobs (JobId, UserId, DeviceId, RequestedAt, Status)
VALUES (@JobId, @UserId, @DeviceId, @RequestedAt, 'Running');
SELECT @JobId AS JobId, 'Running' AS Status, @RequestedAt AS RequestedAt;
""";
        var jobId = Guid.CreateVersion7();
        command.Parameters.AddWithValue("@JobId", jobId);
        command.Parameters.AddWithValue("@UserId", userId.Value);
        command.Parameters.AddWithValue("@DeviceId", (object?)deviceId ?? DBNull.Value);
        command.Parameters.AddWithValue("@RequestedAt", requestedAt);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            throw new InvalidOperationException("Sync job creation did not return a row.");
        }

        return new SyncJob(reader.GetGuid(0), userId, deviceId, reader.GetDateTimeOffset(2), Enum.Parse<SyncJobStatus>(reader.GetString(1)));
    }

    public Task MarkSucceededAsync(Guid jobId, DateTimeOffset completedAt, CancellationToken cancellationToken) =>
        UpdateJobAsync(jobId, "Succeeded", completedAt, null, cancellationToken);

    public async Task MarkFailedAsync(Guid jobId, string errorCode, CancellationToken cancellationToken)
    {
        await using var connection = await connections.OpenAsync(cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandText = "UPDATE dbo.SyncJobs SET Status = 'Failed', LastError = @Error, CompletedAt = SYSUTCDATETIME() WHERE JobId = @JobId;";
        command.Parameters.AddWithValue("@JobId", jobId);
        command.Parameters.AddWithValue("@Error", errorCode);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task<DateTimeOffset?> GetLastSuccessfulSyncAsync(UserId userId, CancellationToken cancellationToken)
    {
        await using var connection = await connections.OpenAsync(cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandText = "SELECT MAX(CompletedAt) FROM dbo.SyncJobs WHERE UserId = @UserId AND Status = 'Succeeded';";
        command.Parameters.AddWithValue("@UserId", userId.Value);
        var result = await command.ExecuteScalarAsync(cancellationToken);
        return result is DBNull or null ? null : (DateTimeOffset)result;
    }

    private async Task UpdateJobAsync(Guid jobId, string status, DateTimeOffset completedAt, string? error, CancellationToken cancellationToken)
    {
        await using var connection = await connections.OpenAsync(cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandText = "UPDATE dbo.SyncJobs SET Status = @Status, LastError = @Error, CompletedAt = @CompletedAt WHERE JobId = @JobId;";
        command.Parameters.AddWithValue("@JobId", jobId);
        command.Parameters.AddWithValue("@Status", status);
        command.Parameters.AddWithValue("@Error", (object?)error ?? DBNull.Value);
        command.Parameters.AddWithValue("@CompletedAt", completedAt);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }
}
