using PumpSync.ApiContracts;
using PumpSync.Application.Abstractions;
using PumpSync.Application.Validation;
using PumpSync.Domain.Auth;
using PumpSync.Domain.Tandem;

namespace PumpSync.Application.UseCases;

public sealed class ValidateTandemCredentialsUseCase(
    IRateLimiter rateLimiter,
    ITandemAuthenticator authenticator)
{
    public async Task<TandemCredentialValidationResponse> ExecuteAsync(
        AuthenticatedUser user,
        TandemCredentialValidationRequest request,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);
        TandemSyncRequestValidator.ValidateCredentials(request.Tandem);

        var allowed = await rateLimiter.AllowAsync(user.UserId, "validate-tandem-credentials", 12, TimeSpan.FromHours(1), cancellationToken);
        if (!allowed)
        {
            throw new InvalidOperationException("Tandem credential validation rate limit exceeded.");
        }

        var credentials = new TandemCredentials(
            request.Tandem.Username,
            request.Tandem.Password,
            TandemRegionParser.Parse(request.Tandem.Region));

        _ = await authenticator.LoginAsync(credentials, cancellationToken);
        return new TandemCredentialValidationResponse(true);
    }
}
