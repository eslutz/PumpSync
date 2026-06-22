using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text.Json;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;
using PumpSync.Application.Abstractions;
using PumpSync.Domain.Billing;
using PumpSync.Infrastructure.Options;

namespace PumpSync.Infrastructure.Auth;

public sealed class AppStoreSignedPayloadVerifier(IOptions<AppStoreOptions> options) : IAppStoreSignedPayloadVerifier
{
    private readonly AppStoreOptions options = options.Value;
    private readonly Lazy<X509Certificate2> rootCertificate = new(() => LoadRootCertificate(options.Value.RootCertificatePem));

    public async Task<VerifiedAppStoreTransaction> VerifyTransactionAsync(string signedTransactionInfo, CancellationToken cancellationToken)
    {
        var payload = await VerifyJwsAsync(signedTransactionInfo, cancellationToken);
        return ParseTransaction(payload);
    }

    public async Task<IReadOnlyList<VerifiedAppStoreTransaction>> VerifyNotificationAsync(string signedPayload, CancellationToken cancellationToken)
    {
        var payload = await VerifyJwsAsync(signedPayload, cancellationToken);
        using var document = JsonDocument.Parse(payload);
        var transactions = new List<VerifiedAppStoreTransaction>();

        if (document.RootElement.TryGetProperty("data", out var data) &&
            data.TryGetProperty("signedTransactionInfo", out var signedTransactionInfo) &&
            signedTransactionInfo.ValueKind == JsonValueKind.String)
        {
            transactions.Add(await VerifyTransactionAsync(signedTransactionInfo.GetString() ?? string.Empty, cancellationToken));
        }

        return transactions;
    }

    private async Task<string> VerifyJwsAsync(string jws, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(jws))
        {
            throw new SecurityTokenValidationException("Signed App Store payload is required.");
        }

        var parts = jws.Split('.');
        if (parts.Length != 3)
        {
            throw new SecurityTokenValidationException("Signed App Store payload is not a compact JWS.");
        }

        using var header = JsonDocument.Parse(Base64UrlEncoder.DecodeBytes(parts[0]));
        if (!header.RootElement.TryGetProperty("x5c", out var certs) || certs.ValueKind != JsonValueKind.Array || certs.GetArrayLength() == 0)
        {
            throw new SecurityTokenValidationException("Signed App Store payload is missing certificate headers.");
        }

        var certificates = ReadCertificates(certs);
        var certificate = certificates[0];
        using var chain = new X509Chain();
        chain.ChainPolicy.RevocationMode = X509RevocationMode.NoCheck;
        chain.ChainPolicy.TrustMode = X509ChainTrustMode.CustomRootTrust;
        chain.ChainPolicy.CustomTrustStore.Add(rootCertificate.Value);

        foreach (var intermediate in certificates.Skip(1))
        {
            chain.ChainPolicy.ExtraStore.Add(intermediate);
        }

        if (!chain.Build(certificate))
        {
            throw new SecurityTokenValidationException("Signed App Store payload certificate chain is not pinned to the configured Apple root.");
        }

        using var publicKey = certificate.GetECDsaPublicKey()
            ?? throw new SecurityTokenValidationException("Signed App Store payload certificate does not contain an ECDSA public key.");
        var signingKey = new ECDsaSecurityKey(publicKey);
        var result = await new JsonWebTokenHandler().ValidateTokenAsync(jws, new TokenValidationParameters
        {
            ValidateAudience = false,
            ValidateIssuer = false,
            ValidateLifetime = false,
            ValidateIssuerSigningKey = true,
            IssuerSigningKeyResolver = (_, _, _, _) => [signingKey]
        });

        if (!result.IsValid)
        {
            throw new SecurityTokenValidationException("Signed App Store payload validation failed.", result.Exception);
        }

        return Base64UrlEncoder.Decode(parts[1]);
    }

    private static X509Certificate2 LoadRootCertificate(string rootCertificatePem)
    {
        if (string.IsNullOrWhiteSpace(rootCertificatePem))
        {
            throw new SecurityTokenValidationException("AppStore__RootCertificatePem is required before App Store payloads can be trusted.");
        }

        return X509Certificate2.CreateFromPem(rootCertificatePem);
    }

    private static List<X509Certificate2> ReadCertificates(JsonElement certs)
    {
        var certificates = new List<X509Certificate2>();

        foreach (var cert in certs.EnumerateArray())
        {
            if (cert.ValueKind != JsonValueKind.String || string.IsNullOrWhiteSpace(cert.GetString()))
            {
                throw new SecurityTokenValidationException("Signed App Store payload contains an invalid certificate header.");
            }

            certificates.Add(X509CertificateLoader.LoadCertificate(Convert.FromBase64String(cert.GetString()!)));
        }

        return certificates;
    }

    private VerifiedAppStoreTransaction ParseTransaction(string payload)
    {
        using var document = JsonDocument.Parse(payload);
        var root = document.RootElement;
        var bundleId = RequiredString(root, "bundleId");
        if (!string.Equals(bundleId, options.BundleId, StringComparison.Ordinal))
        {
            throw new SecurityTokenValidationException("App Store transaction bundle id does not match PumpSync.");
        }

        var productId = RequiredString(root, "productId");
        if (!string.Equals(productId, options.SubscriptionProductId, StringComparison.Ordinal))
        {
            throw new SecurityTokenValidationException("App Store transaction product id does not match PumpSync Hosted.");
        }

        var environment = RequiredString(root, "environment");
        if (!string.Equals(environment, options.Environment, StringComparison.OrdinalIgnoreCase))
        {
            throw new SecurityTokenValidationException("App Store transaction environment does not match this backend.");
        }

        var expiresAt = TryReadMilliseconds(root, "expiresDate");
        var revokedAt = TryReadMilliseconds(root, "revocationDate");
        var status = revokedAt is not null
            ? BillingEntitlementStatus.Revoked
            : expiresAt is null || expiresAt > DateTimeOffset.UtcNow
                ? BillingEntitlementStatus.Active
                : BillingEntitlementStatus.Expired;

        return new VerifiedAppStoreTransaction(
            RequiredString(root, "originalTransactionId"),
            productId,
            status,
            environment,
            expiresAt,
            DateTimeOffset.UtcNow);
    }

    private static string RequiredString(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var property) || property.ValueKind != JsonValueKind.String)
        {
            throw new SecurityTokenValidationException($"App Store transaction is missing {propertyName}.");
        }

        return property.GetString() ?? string.Empty;
    }

    private static DateTimeOffset? TryReadMilliseconds(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var property))
        {
            return null;
        }

        var milliseconds = property.ValueKind switch
        {
            JsonValueKind.Number when property.TryGetInt64(out var value) => value,
            JsonValueKind.String when long.TryParse(property.GetString(), out var value) => value,
            _ => 0
        };

        return milliseconds <= 0 ? null : DateTimeOffset.FromUnixTimeMilliseconds(milliseconds);
    }
}
