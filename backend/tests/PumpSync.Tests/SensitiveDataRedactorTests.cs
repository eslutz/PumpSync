using PumpSync.Application.Security;
using Xunit;

namespace PumpSync.Tests;

public sealed class SensitiveDataRedactorTests
{
    [Fact]
    public void Redact_RemovesCredentialAndTokenValues()
    {
        var redacted = SensitiveDataRedactor.Redact(new Dictionary<string, string>
        {
            ["username"] = "user@example.com",
            ["password"] = "secret",
            ["Authorization"] = "Bearer token",
            ["deviceId"] = "pump-1"
        });

        Assert.Equal("[redacted]", redacted["username"]);
        Assert.Equal("[redacted]", redacted["password"]);
        Assert.Equal("[redacted]", redacted["Authorization"]);
        Assert.Equal("pump-1", redacted["deviceId"]);
    }
}
