using Azure.Data.Tables;
using Azure.Identity;
using Microsoft.Extensions.Options;
using PumpSync.Infrastructure.Options;

namespace PumpSync.Infrastructure.TableStorage;

public sealed class TableClientFactory(IOptions<AzureStorageOptions> options)
{
    private readonly AzureStorageOptions options = options.Value;

    public TableClient CreateClient(string tableName)
    {
        if (!string.IsNullOrWhiteSpace(options.ConnectionString))
        {
            return new TableClient(options.ConnectionString, tableName);
        }

        if (string.IsNullOrWhiteSpace(options.AccountName))
        {
            throw new InvalidOperationException("AzureStorage AccountName or ConnectionString configuration is required.");
        }

        return new TableClient(new Uri($"https://{options.AccountName}.table.core.windows.net"), tableName, new DefaultAzureCredential());
    }
}
