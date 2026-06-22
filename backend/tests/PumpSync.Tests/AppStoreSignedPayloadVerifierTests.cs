using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;
using PumpSync.Infrastructure.Auth;
using PumpSync.Infrastructure.Options;
using Xunit;

namespace PumpSync.Tests;

public sealed class AppStoreSignedPayloadVerifierTests
{
    [Fact]
    public async Task VerifyTransactionAsync_AcceptsEs256JwsPinnedToConfiguredRoot()
    {
        using var rootKey = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        using var leafKey = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        using var rootCertificate = CreateRootCertificate(rootKey);
        using var leafCertificate = CreateLeafCertificate(rootCertificate, rootKey, leafKey);
        var signedTransaction = CreateSignedTransaction(leafCertificate, leafKey);
        var verifier = new AppStoreSignedPayloadVerifier(Options.Create(new AppStoreOptions
        {
            BundleId = "dev.ericslutz.PumpSync",
            Environment = "Sandbox",
            SubscriptionProductId = "dev.ericslutz.PumpSync.hosted.monthly",
            RootCertificatePem = rootCertificate.ExportCertificatePem()
        }));

        var transaction = await verifier.VerifyTransactionAsync(signedTransaction, CancellationToken.None);

        Assert.Equal("original-transaction-1", transaction.OriginalTransactionId);
        Assert.Equal("dev.ericslutz.PumpSync.hosted.monthly", transaction.ProductId);
        Assert.Equal("Sandbox", transaction.Environment);
    }

    private static X509Certificate2 CreateRootCertificate(ECDsa rootKey)
    {
        var request = new CertificateRequest(
            "CN=PumpSync Test Root",
            rootKey,
            HashAlgorithmName.SHA256);
        request.CertificateExtensions.Add(new X509BasicConstraintsExtension(true, false, 0, true));
        request.CertificateExtensions.Add(new X509KeyUsageExtension(X509KeyUsageFlags.KeyCertSign | X509KeyUsageFlags.CrlSign, true));
        request.CertificateExtensions.Add(new X509SubjectKeyIdentifierExtension(request.PublicKey, false));

        return request.CreateSelfSigned(
            DateTimeOffset.UtcNow.AddDays(-1),
            DateTimeOffset.UtcNow.AddYears(1));
    }

    private static X509Certificate2 CreateLeafCertificate(
        X509Certificate2 rootCertificate,
        ECDsa rootKey,
        ECDsa leafKey)
    {
        var request = new CertificateRequest(
            "CN=PumpSync Test Leaf",
            leafKey,
            HashAlgorithmName.SHA256);
        request.CertificateExtensions.Add(new X509BasicConstraintsExtension(false, false, 0, true));
        request.CertificateExtensions.Add(new X509KeyUsageExtension(X509KeyUsageFlags.DigitalSignature, true));
        request.CertificateExtensions.Add(new X509SubjectKeyIdentifierExtension(request.PublicKey, false));

        var serialNumber = RandomNumberGenerator.GetBytes(16);
        using var certificate = request.Create(
            rootCertificate.SubjectName,
            X509SignatureGenerator.CreateForECDsa(rootKey),
            DateTimeOffset.UtcNow.AddDays(-1),
            DateTimeOffset.UtcNow.AddYears(1),
            serialNumber);

        return certificate.CopyWithPrivateKey(leafKey);
    }

    private static string CreateSignedTransaction(X509Certificate2 leafCertificate, ECDsa leafKey)
    {
        var now = DateTimeOffset.UtcNow;
        var descriptor = new SecurityTokenDescriptor
        {
            Claims = new Dictionary<string, object>
            {
                ["bundleId"] = "dev.ericslutz.PumpSync",
                ["productId"] = "dev.ericslutz.PumpSync.hosted.monthly",
                ["environment"] = "Sandbox",
                ["originalTransactionId"] = "original-transaction-1",
                ["expiresDate"] = now.AddDays(1).ToUnixTimeMilliseconds()
            },
            AdditionalHeaderClaims = new Dictionary<string, object>
            {
                ["x5c"] = new[]
                {
                    Convert.ToBase64String(leafCertificate.Export(X509ContentType.Cert))
                }
            },
            SigningCredentials = new SigningCredentials(
                new ECDsaSecurityKey(leafKey),
                SecurityAlgorithms.EcdsaSha256)
        };

        return new JsonWebTokenHandler().CreateToken(descriptor);
    }
}
