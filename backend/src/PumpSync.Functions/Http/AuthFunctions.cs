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
    GetCapabilitiesUseCase capabilities,
    CreateSubscriptionSessionUseCase subscriptionSession,
    CreateSelfHostedSessionUseCase selfHostedSession,
    HandleAppStoreNotificationUseCase appStoreNotifications,
    ILogger<AuthFunctions> logger) : HttpFunctionBase(tokenValidator)
{
    [Function("Capabilities")]
    public Task<HttpResponseData> Capabilities(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "v1/capabilities")] HttpRequestData request) =>
        ExecuteAsync(request, token => JsonAsync(request, HttpStatusCode.OK, capabilities.Execute(), token));

    [Function("SubscriptionSession")]
    public Task<HttpResponseData> SubscriptionSession(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "v1/subscription/session")] HttpRequestData request) =>
        ExecuteAsync(request, async token =>
        {
            var startedAt = Stopwatch.GetTimestamp();
            logger.LogInformation(
                "Received subscription session request. InvocationId={InvocationId}",
                request.FunctionContext.InvocationId);
            var body = await ReadJsonAsync<SubscriptionSessionRequest>(request, token);
            var response = await subscriptionSession.ExecuteAsync(body, token);
            logger.LogInformation(
                "Completed subscription session request in {DurationMs} ms. InvocationId={InvocationId}",
                ElapsedMilliseconds(startedAt),
                request.FunctionContext.InvocationId);
            return await JsonAsync(request, HttpStatusCode.OK, response, token);
        });

    [Function("SelfHostedSession")]
    public Task<HttpResponseData> SelfHostedSession(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "v1/self-host/session")] HttpRequestData request) =>
        ExecuteAsync(request, async token =>
        {
            var body = await ReadJsonAsync<SelfHostedSessionRequest>(request, token);
            var response = selfHostedSession.Execute(body);
            return await JsonAsync(request, HttpStatusCode.OK, response, token);
        });

    [Function("AppStoreNotifications")]
    public Task<HttpResponseData> AppStoreNotifications(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "v1/app-store/notifications")] HttpRequestData request) =>
        ExecuteAsync(request, async token =>
        {
            var startedAt = Stopwatch.GetTimestamp();
            logger.LogInformation(
                "Received App Store server notification request. InvocationId={InvocationId}",
                request.FunctionContext.InvocationId);
            var body = await ReadJsonAsync<AppStoreNotificationRequest>(request, token);
            var response = await appStoreNotifications.ExecuteAsync(body, token);
            logger.LogInformation(
                "Completed App Store server notification request in {DurationMs} ms with {ProcessedEvents} event(s). InvocationId={InvocationId}",
                ElapsedMilliseconds(startedAt),
                response.ProcessedEvents,
                request.FunctionContext.InvocationId);
            return await JsonAsync(request, HttpStatusCode.OK, response, token);
        });

    private static long ElapsedMilliseconds(long startedAt) =>
        (long)Stopwatch.GetElapsedTime(startedAt).TotalMilliseconds;
}
