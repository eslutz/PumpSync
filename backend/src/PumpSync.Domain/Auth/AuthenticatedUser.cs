using PumpSync.Domain.Users;

namespace PumpSync.Domain.Auth;

public enum AuthenticatedUserMode
{
    Hosted = 1,
    SelfHosted = 2
}

public sealed record AuthenticatedUser(
    UserId UserId,
    string SubjectId,
    string InstallationId,
    AuthenticatedUserMode Mode,
    string[] Scopes);
