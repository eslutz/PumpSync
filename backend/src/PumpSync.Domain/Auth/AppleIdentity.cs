namespace PumpSync.Domain.Auth;

public sealed record AppleIdentity(
    string Subject,
    string? Email,
    bool EmailVerified,
    string? RealUserStatus);
