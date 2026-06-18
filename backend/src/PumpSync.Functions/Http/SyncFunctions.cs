using System.Net;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using PumpSync.ApiContracts;
using PumpSync.Application.Abstractions;
using PumpSync.Application.UseCases;

namespace PumpSync.Functions.Http;

public sealed class SyncFunctions(
    IServiceTokenValidator tokenValidator,
    SyncTandemUseCase syncTandem,
    ValidateTandemCredentialsUseCase validateTandemCredentials,
    GetStatusUseCase status,
    BackendAccessGuard accessGuard) : HttpFunctionBase(tokenValidator)
{
    [Function("SyncTandem")]
    public Task<HttpResponseData> SyncTandem(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "v1/sync/tandem")] HttpRequestData request) =>
        ExecuteAsync(request, async token =>
        {
            var user = Authenticate(request);
            await accessGuard.EnsureAccessAsync(user, token);
            var body = await ReadJsonAsync<TandemSyncRequest>(request, token);
            var response = await syncTandem.ExecuteAsync(user, body, token);
            return await JsonAsync(request, HttpStatusCode.OK, response, token);
        });

    [Function("ValidateTandemCredentials")]
    public Task<HttpResponseData> ValidateTandemCredentials(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "v1/tandem/credentials/validate")] HttpRequestData request) =>
        ExecuteAsync(request, async token =>
        {
            var user = Authenticate(request);
            await accessGuard.EnsureAccessAsync(user, token);
            var body = await ReadJsonAsync<TandemCredentialValidationRequest>(request, token);
            var response = await validateTandemCredentials.ExecuteAsync(user, body, token);
            return await JsonAsync(request, HttpStatusCode.OK, response, token);
        });

    [Function("Status")]
    public Task<HttpResponseData> GetStatus(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "v1/status")] HttpRequestData request) =>
        ExecuteAsync(request, async token =>
        {
            var user = Authenticate(request);
            await accessGuard.EnsureAccessAsync(user, token);
            var response = await status.ExecuteAsync(user, token);
            return await JsonAsync(request, HttpStatusCode.OK, response, token);
        });
}
