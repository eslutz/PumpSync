using PumpSync.Application.Abstractions;
using PumpSync.Domain.Users;

namespace PumpSync.Infrastructure.Sql;

public sealed class SqlRateLimiter(SqlConnectionFactory connections) : IRateLimiter
{
    public async Task<bool> AllowAsync(UserId userId, string operation, int maxRequests, TimeSpan window, CancellationToken cancellationToken)
    {
        await using var connection = await connections.OpenAsync(cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandText = """
DELETE FROM dbo.RateLimitEvents WHERE OccurredAt < DATEADD(second, -@WindowSeconds, SYSUTCDATETIME());
DECLARE @CurrentCount int = (
  SELECT COUNT(*) FROM dbo.RateLimitEvents
  WHERE UserId = @UserId AND Operation = @Operation AND OccurredAt >= DATEADD(second, -@WindowSeconds, SYSUTCDATETIME())
);
IF @CurrentCount < @MaxRequests
BEGIN
  INSERT INTO dbo.RateLimitEvents (UserId, Operation, OccurredAt) VALUES (@UserId, @Operation, SYSUTCDATETIME());
  SELECT CAST(1 AS bit);
END
ELSE
BEGIN
  SELECT CAST(0 AS bit);
END
""";
        command.Parameters.AddWithValue("@UserId", userId.Value);
        command.Parameters.AddWithValue("@Operation", operation);
        command.Parameters.AddWithValue("@MaxRequests", maxRequests);
        command.Parameters.AddWithValue("@WindowSeconds", (int)window.TotalSeconds);
        var result = await command.ExecuteScalarAsync(cancellationToken);
        return result is bool allowed && allowed;
    }
}
