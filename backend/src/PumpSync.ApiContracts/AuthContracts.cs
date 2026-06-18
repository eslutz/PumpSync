namespace PumpSync.ApiContracts;

public sealed record CapabilitiesResponse(
    string ApiVersion,
    string ServiceMode,
    string BillingMode,
    string TandemCredentialStorage,
    string TandemDataRetention);

public sealed record SubscriptionSessionRequest(
    string SignedTransactionInfo,
    string InstallationId);

public sealed record SelfHostedSessionRequest(
    string InstallationId);

public sealed record BackendSessionResponse(
    string AccessToken,
    DateTimeOffset ExpiresAt,
    bool EntitlementActive,
    string ServiceMode);

public sealed record AppStoreNotificationRequest(
    string SignedPayload);

public sealed record AppStoreNotificationResponse(
    int ProcessedEvents);
