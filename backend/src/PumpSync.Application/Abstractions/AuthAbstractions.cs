using PumpSync.Domain.Auth;
using PumpSync.Domain.Users;

namespace PumpSync.Application.Abstractions;

public interface IAppleIdentityValidator
{
    Task<AppleIdentity> ValidateAsync(string identityToken, CancellationToken cancellationToken);
}

public interface IAppleServerNotificationValidator
{
    Task<AppleServerNotification> ValidateAsync(string payload, CancellationToken cancellationToken);
}

public interface IServiceTokenIssuer
{
    string IssueToken(UserId userId, string appleSubject, DateTimeOffset expiresAt);
}

public interface IServiceTokenValidator
{
    AuthenticatedUser Validate(string bearerToken);
}
