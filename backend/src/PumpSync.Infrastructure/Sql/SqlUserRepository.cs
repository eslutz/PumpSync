using Microsoft.Data.SqlClient;
using PumpSync.Application.Abstractions;
using PumpSync.Domain.Auth;
using PumpSync.Domain.Users;

namespace PumpSync.Infrastructure.Sql;

public sealed class SqlUserRepository(SqlConnectionFactory connections) : IUserRepository
{
    public async Task<(UserId UserId, string? Email)> UpsertAppleUserAsync(AppleIdentity identity, CancellationToken cancellationToken)
    {
        await using var connection = await connections.OpenAsync(cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandText = """
MERGE dbo.Users WITH (HOLDLOCK) AS target
USING (SELECT @AppleSubject AS AppleSubject) AS source
ON target.AppleSubject = source.AppleSubject
WHEN MATCHED THEN
  UPDATE SET Email = COALESCE(@Email, target.Email), EmailVerified = @EmailVerified, Status = 'Active', UpdatedAt = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
  INSERT (UserId, AppleSubject, Email, EmailVerified, Status, CreatedAt, UpdatedAt)
  VALUES (@UserId, @AppleSubject, @Email, @EmailVerified, 'Active', SYSUTCDATETIME(), SYSUTCDATETIME())
OUTPUT inserted.UserId, inserted.Email;
""";
        var newUserId = UserId.New();
        command.Parameters.AddWithValue("@UserId", newUserId.Value);
        command.Parameters.AddWithValue("@AppleSubject", identity.Subject);
        command.Parameters.AddWithValue("@Email", (object?)identity.Email ?? DBNull.Value);
        command.Parameters.AddWithValue("@EmailVerified", identity.EmailVerified);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            throw new InvalidOperationException("User upsert did not return a row.");
        }

        return (new UserId(reader.GetGuid(0)), reader.IsDBNull(1) ? null : reader.GetString(1));
    }

    public async Task<(UserId UserId, string AppleSubject)?> FindByIdAsync(UserId userId, CancellationToken cancellationToken)
    {
        await using var connection = await connections.OpenAsync(cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandText = "SELECT UserId, AppleSubject FROM dbo.Users WHERE UserId = @UserId AND Status = 'Active';";
        command.Parameters.AddWithValue("@UserId", userId.Value);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        return await reader.ReadAsync(cancellationToken)
            ? (new UserId(reader.GetGuid(0)), reader.GetString(1))
            : null;
    }

    public async Task SetAppleEmailForwardingAsync(string appleSubject, string? email, bool enabled, CancellationToken cancellationToken)
    {
        await using var connection = await connections.OpenAsync(cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandText = """
UPDATE dbo.Users
SET Email = COALESCE(@Email, Email),
    EmailVerified = @EmailVerified,
    UpdatedAt = SYSUTCDATETIME()
WHERE AppleSubject = @AppleSubject;
""";
        command.Parameters.AddWithValue("@AppleSubject", appleSubject);
        command.Parameters.AddWithValue("@Email", (object?)email ?? DBNull.Value);
        command.Parameters.AddWithValue("@EmailVerified", enabled);

        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task SetAppleUserStatusAsync(string appleSubject, string status, CancellationToken cancellationToken)
    {
        await using var connection = await connections.OpenAsync(cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandText = """
UPDATE dbo.Users
SET Status = @Status,
    UpdatedAt = SYSUTCDATETIME()
WHERE AppleSubject = @AppleSubject;
""";
        command.Parameters.AddWithValue("@AppleSubject", appleSubject);
        command.Parameters.AddWithValue("@Status", status);

        await command.ExecuteNonQueryAsync(cancellationToken);
    }
}
