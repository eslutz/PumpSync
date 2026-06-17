using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Options;
using PumpSync.Infrastructure.Options;

namespace PumpSync.Infrastructure.Sql;

public sealed class SqlConnectionFactory(IOptions<AzureSqlOptions> options)
{
    public async Task<SqlConnection> OpenAsync(CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(options.Value.ConnectionString))
        {
            throw new InvalidOperationException("AzureSql ConnectionString configuration is required.");
        }

        var connection = new SqlConnection(options.Value.ConnectionString);
        await connection.OpenAsync(cancellationToken);
        return connection;
    }
}
