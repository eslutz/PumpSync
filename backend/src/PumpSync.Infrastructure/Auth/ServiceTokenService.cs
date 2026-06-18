using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using PumpSync.Application.Abstractions;
using PumpSync.Domain.Auth;
using PumpSync.Domain.Users;
using PumpSync.Infrastructure.Options;

namespace PumpSync.Infrastructure.Auth;

public sealed class ServiceTokenService(IOptions<PumpSyncOptions> options) : IServiceTokenIssuer, IServiceTokenValidator
{
    private readonly PumpSyncOptions options = options.Value;

    public string IssueToken(AuthenticatedUser user, DateTimeOffset expiresAt)
    {
        var credentials = new SigningCredentials(SecurityKey(), SecurityAlgorithms.HmacSha256);
        var token = new JwtSecurityToken(
            options.ServiceTokenIssuer,
            options.ServiceTokenAudience,
            [
                new Claim(JwtRegisteredClaimNames.Sub, user.UserId.ToString()),
                new Claim("subject_id", user.SubjectId),
                new Claim("installation_id", user.InstallationId),
                new Claim("mode", user.Mode is AuthenticatedUserMode.SelfHosted ? "selfHosted" : "hosted"),
                new Claim("scope", "ios")
            ],
            DateTime.UtcNow,
            expiresAt.UtcDateTime,
            credentials);

        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    public AuthenticatedUser Validate(string bearerToken)
    {
        var token = bearerToken.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase)
            ? bearerToken["Bearer ".Length..]
            : bearerToken;

        var handler = new JwtSecurityTokenHandler();
        var principal = handler.ValidateToken(token, new TokenValidationParameters
        {
            ValidIssuer = options.ServiceTokenIssuer,
            ValidAudience = options.ServiceTokenAudience,
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = SecurityKey(),
            ClockSkew = TimeSpan.FromMinutes(2)
        }, out _);

        var userId = principal.FindFirst(JwtRegisteredClaimNames.Sub)?.Value
            ?? principal.FindFirst(ClaimTypes.NameIdentifier)?.Value
            ?? throw new SecurityTokenValidationException("Service token is missing subject.");
        var subjectId = principal.FindFirst("subject_id")?.Value
            ?? throw new SecurityTokenValidationException("Service token is missing subject id.");
        var installationId = principal.FindFirst("installation_id")?.Value
            ?? throw new SecurityTokenValidationException("Service token is missing installation id.");
        var mode = principal.FindFirst("mode")?.Value is "selfHosted"
            ? AuthenticatedUserMode.SelfHosted
            : AuthenticatedUserMode.Hosted;
        var scopes = principal.FindAll("scope").Select(x => x.Value).ToArray();

        return new AuthenticatedUser(new UserId(Guid.ParseExact(userId, "N")), subjectId, installationId, mode, scopes);
    }

    private SymmetricSecurityKey SecurityKey()
    {
        if (string.IsNullOrWhiteSpace(options.ServiceTokenSigningKey) || options.ServiceTokenSigningKey.Length < 32)
        {
            throw new InvalidOperationException("PumpSync ServiceTokenSigningKey must be at least 32 characters.");
        }

        return new SymmetricSecurityKey(Encoding.UTF8.GetBytes(options.ServiceTokenSigningKey));
    }
}
