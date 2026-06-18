using PumpSync.ApiContracts;
using PumpSync.Application.Abstractions;
using PumpSync.Domain.Billing;
using PumpSync.Domain.Common;

namespace PumpSync.Application.UseCases;

public sealed class CreateSubscriptionSessionUseCase(
    IAppStoreSignedPayloadVerifier verifier,
    IBillingEntitlementRepository entitlements,
    IInstallationRepository installations,
    IServiceTokenIssuer tokens,
    IClock clock)
{
    public async Task<BackendSessionResponse> ExecuteAsync(SubscriptionSessionRequest request, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.InstallationId))
        {
            throw new ArgumentException("Installation id is required.", nameof(request));
        }

        var transaction = await verifier.VerifyTransactionAsync(request.SignedTransactionInfo, cancellationToken);
        var entitlement = new BillingEntitlement(
            transaction.OriginalTransactionId,
            transaction.ProductId,
            transaction.Status,
            transaction.Environment,
            transaction.ExpiresAt,
            transaction.VerifiedAt);
        await entitlements.UpsertEntitlementAsync(entitlement, cancellationToken);
        await installations.UpsertInstallationAsync(transaction.OriginalTransactionId, request.InstallationId, clock.UtcNow, cancellationToken);

        var active = await entitlements.GetActiveEntitlementAsync(transaction.OriginalTransactionId, cancellationToken);
        if (active is null)
        {
            throw new UnauthorizedAccessException("An active PumpSync Hosted subscription is required.");
        }

        var user = SubjectIdentity.Hosted(transaction.OriginalTransactionId, request.InstallationId);
        var expiresAt = clock.UtcNow.AddHours(12);
        return new BackendSessionResponse(tokens.IssueToken(user, expiresAt), expiresAt, true, "hosted");
    }
}
