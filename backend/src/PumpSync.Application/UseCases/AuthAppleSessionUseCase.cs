using PumpSync.ApiContracts;
using PumpSync.Application.Abstractions;
using PumpSync.Domain.Common;

namespace PumpSync.Application.UseCases;

public sealed class AuthAppleSessionUseCase(
    IAppleIdentityValidator validator,
    IUserRepository users,
    IServiceTokenIssuer tokenIssuer,
    IClock clock)
{
    public async Task<AppleSessionResponse> ExecuteAsync(AppleSessionRequest request, CancellationToken cancellationToken)
    {
        var identity = await validator.ValidateAsync(request.IdentityToken, cancellationToken);
        var user = await users.UpsertAppleUserAsync(identity, cancellationToken);
        var expiresAt = clock.UtcNow.AddHours(12);
        var token = tokenIssuer.IssueToken(user.UserId, identity.Subject, expiresAt);

        return new AppleSessionResponse(
            token,
            expiresAt,
            new UserSummary(user.UserId.ToString(), user.Email));
    }
}
