using PumpSync.Application.Abstractions;
using PumpSync.Domain.Users;

namespace PumpSync.Infrastructure.Sql;

public sealed class SqlIdempotencyStore(SqlConnectionFactory connections) : IIdempotencyStore
{
    public async Task<IdempotencyRecord?> TryGetAsync(UserId userId, string endpoint, string key, CancellationToken cancellationToken)
    {
        await using var connection = await connections.OpenAsync(cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandText = """
SELECT RequestHash, ResponseJson, ExpiresAt
FROM dbo.IdempotencyRequests
WHERE UserId = @UserId AND Endpoint = @Endpoint AND IdempotencyKey = @Key AND ExpiresAt > SYSUTCDATETIME();
""";
        command.Parameters.AddWithValue("@UserId", userId.Value);
        command.Parameters.AddWithValue("@Endpoint", endpoint);
        command.Parameters.AddWithValue("@Key", key);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        return await reader.ReadAsync(cancellationToken)
            ? new IdempotencyRecord(userId, endpoint, key, reader.GetString(0), reader.GetString(1), reader.GetDateTimeOffset(2))
            : null;
    }

    public async Task StoreAsync(IdempotencyRecord record, CancellationToken cancellationToken)
    {
        await using var connection = await connections.OpenAsync(cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandText = """
INSERT INTO dbo.IdempotencyRequests (UserId, Endpoint, IdempotencyKey, RequestHash, ResponseJson, ExpiresAt, CreatedAt)
VALUES (@UserId, @Endpoint, @Key, @RequestHash, @ResponseJson, @ExpiresAt, SYSUTCDATETIME());
""";
        command.Parameters.AddWithValue("@UserId", record.UserId.Value);
        command.Parameters.AddWithValue("@Endpoint", record.Endpoint);
        command.Parameters.AddWithValue("@Key", record.Key);
        command.Parameters.AddWithValue("@RequestHash", record.RequestHash);
        command.Parameters.AddWithValue("@ResponseJson", record.ResponseJson);
        command.Parameters.AddWithValue("@ExpiresAt", record.ExpiresAt);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }
}
