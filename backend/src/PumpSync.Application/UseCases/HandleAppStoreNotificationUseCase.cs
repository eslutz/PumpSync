using PumpSync.ApiContracts;
using PumpSync.Application.Abstractions;
using PumpSync.Domain.Billing;
using PumpSync.Domain.Common;

namespace PumpSync.Application.UseCases;

public sealed class HandleAppStoreNotificationUseCase(
    IAppStoreSignedPayloadVerifier verifier,
    IBillingEntitlementRepository entitlements,
    IAppStoreNotificationIdempotencyStore idempotency,
    IClock clock)
{
    public async Task<AppStoreNotificationResponse> ExecuteAsync(AppStoreNotificationRequest request, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.SignedPayload))
        {
            throw new ArgumentException("Signed App Store payload is required.", nameof(request));
        }

        var notificationKey = request.SignedPayload.Length > 64
            ? request.SignedPayload[..64]
            : request.SignedPayload;
        if (!await idempotency.TryRecordAsync(notificationKey, clock.UtcNow, cancellationToken))
        {
            return new AppStoreNotificationResponse(0);
        }

        var transactions = await verifier.VerifyNotificationAsync(request.SignedPayload, cancellationToken);
        foreach (var transaction in transactions)
        {
            await entitlements.UpsertEntitlementAsync(
                new BillingEntitlement(
                    transaction.OriginalTransactionId,
                    transaction.ProductId,
                    transaction.Status,
                    transaction.Environment,
                    transaction.ExpiresAt,
                    transaction.VerifiedAt),
                cancellationToken);
        }

        return new AppStoreNotificationResponse(transactions.Count);
    }
}
