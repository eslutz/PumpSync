using System.Net.Http.Json;
using Microsoft.Extensions.Configuration;

public sealed class ModelCostCatalogClient(HttpClient httpClient, IConfiguration configuration)
{
    public async Task<ModelCostRefreshResult> RefreshAsync(CancellationToken cancellationToken)
    {
        var endpoint = configuration["ModelCostUpdater:CatalogUrl"];
        if (string.IsNullOrWhiteSpace(endpoint))
        {
            return new ModelCostRefreshResult(false, 0);
        }

        var response = await httpClient.GetFromJsonAsync<ModelCostCatalogResponse>(endpoint, cancellationToken);
        return new ModelCostRefreshResult(true, response?.Models?.Count ?? 0);
    }
}

public sealed record ModelCostRefreshResult(bool Enabled, int ModelCount);

public sealed record ModelCostCatalogResponse(IReadOnlyList<ModelCostEntry> Models);

public sealed record ModelCostEntry(string Provider, string Model, decimal InputCostPerMillionTokens, decimal OutputCostPerMillionTokens);
