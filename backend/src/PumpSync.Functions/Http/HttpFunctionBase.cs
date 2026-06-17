using System.Net;
using System.Text.Json;
using Microsoft.Azure.Functions.Worker.Http;
using PumpSync.ApiContracts;
using PumpSync.Application.Abstractions;
using PumpSync.Domain.Auth;

namespace PumpSync.Functions.Http;

public abstract class HttpFunctionBase(IServiceTokenValidator tokenValidator)
{
    protected static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    protected AuthenticatedUser Authenticate(HttpRequestData request)
    {
        if (!request.Headers.TryGetValues("Authorization", out var values))
        {
            throw new UnauthorizedAccessException("Missing Authorization header.");
        }

        return tokenValidator.Validate(values.First());
    }

    protected static string RequiredIdempotencyKey(HttpRequestData request)
    {
        if (!request.Headers.TryGetValues("Idempotency-Key", out var values))
        {
            throw new InvalidOperationException("Idempotency-Key header is required.");
        }

        var key = values.FirstOrDefault();
        return string.IsNullOrWhiteSpace(key)
            ? throw new InvalidOperationException("Idempotency-Key header is required.")
            : key;
    }

    protected static async Task<T> ReadJsonAsync<T>(HttpRequestData request, CancellationToken cancellationToken)
    {
        var value = await JsonSerializer.DeserializeAsync<T>(request.Body, JsonOptions, cancellationToken);
        return value ?? throw new InvalidOperationException("Request body is required.");
    }

    protected static async Task<HttpResponseData> JsonAsync<T>(HttpRequestData request, HttpStatusCode statusCode, T value, CancellationToken cancellationToken)
    {
        var response = request.CreateResponse(statusCode);
        response.Headers.Add("Content-Type", "application/json");
        await response.WriteStringAsync(JsonSerializer.Serialize(value, JsonOptions), cancellationToken);
        return response;
    }

    protected static Task<HttpResponseData> NoContentAsync(HttpRequestData request)
    {
        var response = request.CreateResponse(HttpStatusCode.NoContent);
        return Task.FromResult(response);
    }

    protected static Task<HttpResponseData> ErrorAsync(HttpRequestData request, HttpStatusCode statusCode, string code, string message, CancellationToken cancellationToken)
    {
        var correlationId = request.FunctionContext.InvocationId;
        return JsonAsync(request, statusCode, new ErrorResponse(code, message, correlationId), cancellationToken);
    }

    protected async Task<HttpResponseData> ExecuteAsync(HttpRequestData request, Func<CancellationToken, Task<HttpResponseData>> action)
    {
        try
        {
            return await action(request.FunctionContext.CancellationToken);
        }
        catch (UnauthorizedAccessException ex)
        {
            return await ErrorAsync(request, HttpStatusCode.Unauthorized, "unauthorized", ex.Message, request.FunctionContext.CancellationToken);
        }
        catch (InvalidOperationException ex)
        {
            return await ErrorAsync(request, HttpStatusCode.BadRequest, "invalid_request", ex.Message, request.FunctionContext.CancellationToken);
        }
    }
}
