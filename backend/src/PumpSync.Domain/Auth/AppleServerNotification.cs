namespace PumpSync.Domain.Auth;

public sealed record AppleServerNotification(
    IReadOnlyList<AppleServerNotificationEvent> Events);

public sealed record AppleServerNotificationEvent(
    string Type,
    string AppleSubject,
    string? Email);
