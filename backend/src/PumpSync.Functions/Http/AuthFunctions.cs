using System.Net;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using PumpSync.ApiContracts;
using PumpSync.Application.Abstractions;
using PumpSync.Application.UseCases;

namespace PumpSync.Functions.Http;

public sealed class AuthFunctions(
    IServiceTokenValidator tokenValidator,
    AuthAppleSessionUseCase appleSession) : HttpFunctionBase(tokenValidator)
{
    [Function("AuthAppleSession")]
    public Task<HttpResponseData> AppleSession(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "v1/auth/apple/session")] HttpRequestData request) =>
        ExecuteAsync(request, async token =>
        {
            var body = await ReadJsonAsync<AppleSessionRequest>(request, token);
            var response = await appleSession.ExecuteAsync(body, token);
            return await JsonAsync(request, HttpStatusCode.OK, response, token);
        });
}
