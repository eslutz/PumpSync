using System.IdentityModel.Tokens.Jwt;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;
using PumpSync.Application.Abstractions;
using PumpSync.Domain.Auth;
using PumpSync.Infrastructure.Options;

namespace PumpSync.Infrastructure.Auth;

public sealed class AppleIdentityValidator : IAppleIdentityValidator
{
    private readonly AppleOptions options;
    private readonly ConfigurationManager<OpenIdConnectConfiguration> configurationManager;
    private readonly JwtSecurityTokenHandler tokenHandler = new();

    public AppleIdentityValidator(IOptions<AppleOptions> options)
    {
        this.options = options.Value;
        var documentRetriever = new HttpDocumentRetriever { RequireHttps = true };
        configurationManager = new ConfigurationManager<OpenIdConnectConfiguration>(
            "https://appleid.apple.com/.well-known/openid-configuration",
            new OpenIdConnectConfigurationRetriever(),
            documentRetriever);
    }

    public async Task<AppleIdentity> ValidateAsync(string identityToken, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(options.ClientId))
        {
            throw new InvalidOperationException("Apple ClientId configuration is required.");
        }

        var configuration = await configurationManager.GetConfigurationAsync(cancellationToken);
        var result = await tokenHandler.ValidateTokenAsync(identityToken, new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = options.Issuer,
            ValidateAudience = true,
            ValidAudience = options.ClientId,
            ValidateIssuerSigningKey = true,
            IssuerSigningKeys = configuration.SigningKeys,
            ValidateLifetime = true,
            ClockSkew = TimeSpan.FromMinutes(2)
        });

        if (!result.IsValid || result.ClaimsIdentity is null)
        {
            throw new SecurityTokenValidationException("Apple identity token validation failed.", result.Exception);
        }

        var subject = result.ClaimsIdentity.FindFirst(JwtRegisteredClaimNames.Sub)?.Value
            ?? result.ClaimsIdentity.FindFirst("sub")?.Value
            ?? throw new SecurityTokenValidationException("Apple identity token did not include a subject.");
        var email = result.ClaimsIdentity.FindFirst(JwtRegisteredClaimNames.Email)?.Value
            ?? result.ClaimsIdentity.FindFirst("email")?.Value;
        var emailVerifiedRaw = result.ClaimsIdentity.FindFirst("email_verified")?.Value;

        return new AppleIdentity(
            subject,
            email,
            string.Equals(emailVerifiedRaw, "true", StringComparison.OrdinalIgnoreCase),
            result.ClaimsIdentity.FindFirst("real_user_status")?.Value);
    }
}
