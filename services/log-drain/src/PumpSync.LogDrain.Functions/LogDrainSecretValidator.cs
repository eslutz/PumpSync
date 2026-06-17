using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Configuration;

public sealed class LogDrainSecretValidator(IConfiguration configuration)
{
    private const string HeaderName = "X-PumpSync-LogDrain-Secret";

    public bool IsAuthorized(HttpRequestData request)
    {
        var configuredSecret = configuration["LogDrain:SharedSecret"];
        if (string.IsNullOrWhiteSpace(configuredSecret))
        {
            return false;
        }

        return request.Headers.TryGetValues(HeaderName, out var values)
            && values.Any(value => string.Equals(value, configuredSecret, StringComparison.Ordinal));
    }
}
