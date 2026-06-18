using PumpSync.Application.Abstractions;
using PumpSync.Domain.Auth;

namespace PumpSync.Application.UseCases;

public sealed class AuthenticatedUserGuard(IUserRepository users)
{
    public async Task EnsureActiveAsync(AuthenticatedUser user, CancellationToken cancellationToken)
    {
        var activeUser = await users.FindByIdAsync(user.UserId, cancellationToken);
        if (activeUser is null || !string.Equals(activeUser.Value.AppleSubject, user.AppleSubject, StringComparison.Ordinal))
        {
            throw new UnauthorizedAccessException("The authenticated user is no longer active.");
        }
    }
}
