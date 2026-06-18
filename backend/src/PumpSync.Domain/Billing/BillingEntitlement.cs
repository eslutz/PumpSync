namespace PumpSync.Domain.Billing;

public enum BillingEntitlementStatus
{
    Unknown = 0,
    Active = 1,
    Expired = 2,
    Revoked = 3,
    GracePeriod = 4
}

public sealed record BillingEntitlement(
    string OriginalTransactionId,
    string ProductId,
    BillingEntitlementStatus Status,
    string Environment,
    DateTimeOffset? ExpiresAt,
    DateTimeOffset UpdatedAt);
