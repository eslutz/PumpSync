namespace PumpSync.Infrastructure.Options;

public sealed class PumpSyncOptions
{
    public string ServiceTokenSigningKey { get; set; } = string.Empty;

    public string ServiceTokenIssuer { get; set; } = "pumpsync";

    public string ServiceTokenAudience { get; set; } = "pumpsync-ios";

    public string BackendMode { get; set; } = "Hosted";
}

public sealed class AppStoreOptions
{
    public string BundleId { get; set; } = "dev.ericslutz.PumpSync";

    public string Environment { get; set; } = "Sandbox";

    public string SubscriptionProductId { get; set; } = "dev.ericslutz.PumpSync.hosted.monthly";

    public string IssuerId { get; set; } = string.Empty;

    public string KeyId { get; set; } = string.Empty;

    public string PrivateKey { get; set; } = string.Empty;

    public string RootCertificatePem { get; set; } = string.Empty;
}

public sealed class AzureStorageOptions
{
    public string ConnectionString { get; set; } = string.Empty;

    public string AccountName { get; set; } = string.Empty;

    public string SubscriptionEntitlementsTableName { get; set; } = "SubscriptionEntitlements";

    public string InstallationsTableName { get; set; } = "Installations";

    public string InstallationLookupTableName { get; set; } = "InstallationLookup";

    public string SyncAttemptsTableName { get; set; } = "SyncAttempts";

    public string RateLimitBucketsTableName { get; set; } = "RateLimitBuckets";

    public string AppStoreNotificationIdempotencyTableName { get; set; } = "AppleNotificationIdempotency";

    public string AuditEventsTableName { get; set; } = "AuditEvents";
}

public sealed class TandemSourceOptions
{
    public TandemRegionOptions Us { get; set; } = new()
    {
        LoginUrl = "https://tdcservices.tandemdiabetes.com/accounts/api/login",
        AuthorizeUrl = "https://tdcservices.tandemdiabetes.com/accounts/api/connect/authorize",
        TokenUrl = "https://tdcservices.tandemdiabetes.com/accounts/api/connect/token",
        SourceUrl = "https://source.tandemdiabetes.com/",
        ClientId = "0oa27ho9tpZE9Arjy4h7",
        RedirectUri = "https://sso.tandemdiabetes.com/auth/callback",
        Issuer = "https://sso.tandemdiabetes.com"
    };

    public TandemRegionOptions Eu { get; set; } = new()
    {
        LoginUrl = "https://tdcservices.eu.tandemdiabetes.com/accounts/api/login",
        AuthorizeUrl = "https://tdcservices.eu.tandemdiabetes.com/accounts/api/connect/authorize",
        TokenUrl = "https://tdcservices.eu.tandemdiabetes.com/accounts/api/connect/token",
        SourceUrl = "https://source.eu.tandemdiabetes.com/",
        ClientId = "1519e414-eeec-492e-8c5e-97bea4815a10",
        RedirectUri = "https://source.eu.tandemdiabetes.com/authorize/callback",
        Issuer = "https://tdcservices.eu.tandemdiabetes.com/accounts/api"
    };

    public string EventTimeZoneId { get; set; } = "UTC";
}

public sealed class TandemRegionOptions
{
    public string LoginUrl { get; set; } = string.Empty;

    public string AuthorizeUrl { get; set; } = string.Empty;

    public string TokenUrl { get; set; } = string.Empty;

    public string SourceUrl { get; set; } = string.Empty;

    public string ClientId { get; set; } = string.Empty;

    public string RedirectUri { get; set; } = string.Empty;

    public string Issuer { get; set; } = string.Empty;
}
