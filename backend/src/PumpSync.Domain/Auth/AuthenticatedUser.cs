using PumpSync.Domain.Users;

namespace PumpSync.Domain.Auth;

public sealed record AuthenticatedUser(
    UserId UserId,
    string AppleSubject,
    string[] Scopes);
