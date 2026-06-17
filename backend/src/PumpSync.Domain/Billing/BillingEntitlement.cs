using PumpSync.Domain.Users;

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
    UserId UserId,
    string OriginalTransactionId,
    string ProductId,
    BillingEntitlementStatus Status,
    DateTimeOffset? ExpiresAt,
    DateTimeOffset UpdatedAt);
