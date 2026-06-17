using PumpSync.Application.Abstractions;
using PumpSync.Domain.Billing;
using PumpSync.Domain.Users;

namespace PumpSync.Infrastructure.Sql;

public sealed class SqlBillingEntitlementRepository(SqlConnectionFactory connections) : IBillingEntitlementRepository
{
    public async Task<BillingEntitlement?> GetActiveEntitlementAsync(UserId userId, CancellationToken cancellationToken)
    {
        await using var connection = await connections.OpenAsync(cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandText = """
SELECT TOP 1 OriginalTransactionId, ProductId, Status, ExpiresAt, UpdatedAt
FROM dbo.BillingEntitlements
WHERE UserId = @UserId
  AND Status IN ('Active', 'GracePeriod')
  AND (ExpiresAt IS NULL OR ExpiresAt > SYSUTCDATETIME())
ORDER BY UpdatedAt DESC;
""";
        command.Parameters.AddWithValue("@UserId", userId.Value);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new BillingEntitlement(
            userId,
            reader.GetString(0),
            reader.GetString(1),
            Enum.Parse<BillingEntitlementStatus>(reader.GetString(2)),
            reader.IsDBNull(3) ? null : reader.GetDateTimeOffset(3),
            reader.GetDateTimeOffset(4));
    }
}
