using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

public sealed class ModelCostUpdaterFunction(
    ModelCostCatalogClient catalogClient,
    ILogger<ModelCostUpdaterFunction> logger)
{
    [Function("ModelCostUpdater")]
    public async Task Run(
        [TimerTrigger("%ModelCostUpdater:Schedule%")] TimerInfo timer,
        CancellationToken cancellationToken)
    {
        var result = await catalogClient.RefreshAsync(cancellationToken);
        logger.LogInformation(
            "Model cost updater completed. Enabled: {Enabled}. Updated model count: {ModelCount}.",
            result.Enabled,
            result.ModelCount);
    }
}
