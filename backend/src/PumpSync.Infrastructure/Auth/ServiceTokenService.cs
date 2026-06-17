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

    public string IssueToken(UserId userId, string appleSubject, DateTimeOffset expiresAt)
    {
        var credentials = new SigningCredentials(SecurityKey(), SecurityAlgorithms.HmacSha256);
        var token = new JwtSecurityToken(
            options.ServiceTokenIssuer,
            options.ServiceTokenAudience,
            [
                new Claim(JwtRegisteredClaimNames.Sub, userId.ToString()),
                new Claim("apple_sub", appleSubject),
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
        var appleSubject = principal.FindFirst("apple_sub")?.Value
            ?? throw new SecurityTokenValidationException("Service token is missing Apple subject.");
        var scopes = principal.FindAll("scope").Select(x => x.Value).ToArray();

        return new AuthenticatedUser(new UserId(Guid.ParseExact(userId, "N")), appleSubject, scopes);
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
