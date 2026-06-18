using System.Security.Claims;
using PumpSync.Infrastructure.Auth;
using Xunit;

namespace PumpSync.Tests;

public sealed class AppleIdentityValidatorTests
{
    [Fact]
    public void CreateIdentity_ReadsSubject_WhenJwtHandlerMappedAppleSubClaim()
    {
        var claimsIdentity = new ClaimsIdentity(
        [
            new Claim(ClaimTypes.NameIdentifier, "apple-subject"),
            new Claim(ClaimTypes.Email, "relay@example.com"),
            new Claim("email_verified", "true"),
            new Claim("real_user_status", "2")
        ]);

        var identity = AppleIdentityValidator.CreateIdentity(claimsIdentity);

        Assert.Equal("apple-subject", identity.Subject);
        Assert.Equal("relay@example.com", identity.Email);
        Assert.True(identity.EmailVerified);
        Assert.Equal("2", identity.RealUserStatus);
    }
}
