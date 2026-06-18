using System.Diagnostics;
using System.Net;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using PumpSync.ApiContracts;
using PumpSync.Application.Abstractions;
using PumpSync.Application.UseCases;

namespace PumpSync.Functions.Http;

public sealed class AuthFunctions(
    IServiceTokenValidator tokenValidator,
    AuthAppleSessionUseCase appleSession,
    HandleAppleServerNotificationUseCase appleNotifications,
    ILogger<AuthFunctions> logger) : HttpFunctionBase(tokenValidator)
{
    [Function("AuthAppleSession")]
    public Task<HttpResponseData> AppleSession(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "v1/auth/apple/session")] HttpRequestData request) =>
        ExecuteAsync(request, async token =>
        {
            var startedAt = Stopwatch.GetTimestamp();
            logger.LogInformation(
                "Received Sign in with Apple session request. InvocationId={InvocationId}",
                request.FunctionContext.InvocationId);
            var body = await ReadJsonAsync<AppleSessionRequest>(request, token);
            var response = await appleSession.ExecuteAsync(body, token);
            logger.LogInformation(
                "Completed Sign in with Apple session request in {DurationMs} ms for UserId={UserId}. InvocationId={InvocationId}",
                ElapsedMilliseconds(startedAt),
                response.User.UserId,
                request.FunctionContext.InvocationId);
            return await JsonAsync(request, HttpStatusCode.OK, response, token);
        });

    [Function("AuthAppleNotifications")]
    public Task<HttpResponseData> AppleNotifications(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "v1/auth/apple/notifications")] HttpRequestData request) =>
        ExecuteAsync(request, async token =>
        {
            var startedAt = Stopwatch.GetTimestamp();
            logger.LogInformation(
                "Received Apple server notification request. InvocationId={InvocationId}",
                request.FunctionContext.InvocationId);
            var body = await ReadJsonAsync<AppleServerNotificationRequest>(request, token);
            var response = await appleNotifications.ExecuteAsync(body, token);
            logger.LogInformation(
                "Completed Apple server notification request in {DurationMs} ms with {ProcessedEvents} event(s). InvocationId={InvocationId}",
                ElapsedMilliseconds(startedAt),
                response.ProcessedEvents,
                request.FunctionContext.InvocationId);
            return await JsonAsync(request, HttpStatusCode.OK, response, token);
        });

    private static long ElapsedMilliseconds(long startedAt) =>
        (long)Stopwatch.GetElapsedTime(startedAt).TotalMilliseconds;
}
