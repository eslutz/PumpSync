namespace PumpSync.ApiContracts;

public sealed record AppleSessionRequest(
    string IdentityToken,
    string? AuthorizationCode,
    string? Email,
    string? FullName);

public sealed record AppleSessionResponse(
    string AccessToken,
    DateTimeOffset ExpiresAt,
    UserSummary User);

public sealed record UserSummary(
    string UserId,
    string? Email);

public sealed record AppleServerNotificationRequest(
    string Payload);

public sealed record AppleServerNotificationResponse(
    int ProcessedEvents);
