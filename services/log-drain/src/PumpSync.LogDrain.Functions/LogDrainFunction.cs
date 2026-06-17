using System.Net;
using System.Text.Json;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;

public sealed class LogDrainFunction(
    LogDrainSecretValidator secretValidator,
    LogPayloadRedactor redactor,
    ILogger<LogDrainFunction> logger)
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    [Function("LogDrain")]
    public async Task<HttpResponseData> Run(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "v1/ops/log-drain")] HttpRequestData request)
    {
        if (!secretValidator.IsAuthorized(request))
        {
            return request.CreateResponse(HttpStatusCode.Unauthorized);
        }

        using var document = await JsonDocument.ParseAsync(request.Body, cancellationToken: request.FunctionContext.CancellationToken);
        var redacted = redactor.Redact(document.RootElement);
        logger.LogInformation("Received external log payload: {Payload}", redacted);

        return request.CreateResponse(HttpStatusCode.Accepted);
    }
}
