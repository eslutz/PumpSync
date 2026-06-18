using PumpSync.Domain.Auth;
using PumpSync.Domain.Billing;

namespace PumpSync.Application.Abstractions;

public interface IAppStoreSignedPayloadVerifier
{
    Task<VerifiedAppStoreTransaction> VerifyTransactionAsync(string signedTransactionInfo, CancellationToken cancellationToken);

    Task<IReadOnlyList<VerifiedAppStoreTransaction>> VerifyNotificationAsync(string signedPayload, CancellationToken cancellationToken);
}

public interface IServiceTokenIssuer
{
    string IssueToken(AuthenticatedUser user, DateTimeOffset expiresAt);
}

public interface IServiceTokenValidator
{
    AuthenticatedUser Validate(string bearerToken);
}

public sealed record VerifiedAppStoreTransaction(
    string OriginalTransactionId,
    string ProductId,
    BillingEntitlementStatus Status,
    string Environment,
    DateTimeOffset? ExpiresAt,
    DateTimeOffset VerifiedAt);
