using Microsoft.Extensions.Options;
using PumpSync.Infrastructure.DataDeletion;
using PumpSync.Infrastructure.Options;
using Xunit;

namespace PumpSync.Tests;

public sealed class HmacDataDeletionAuditHasherTests
{
    [Fact]
    public void HashInstallationId_ReturnsStableHashWithoutRawInstallationId()
    {
        var hasher = new HmacDataDeletionAuditHasher(Options.Create(new DataDeletionOptions
        {
            AuditHashSalt = "test-salt"
        }));

        var first = hasher.HashInstallationId("installation-1");
        var second = hasher.HashInstallationId("installation-1");

        Assert.Equal(first, second);
        Assert.Equal(64, first.Length);
        Assert.DoesNotContain("installation-1", first, StringComparison.Ordinal);
    }

    [Fact]
    public void HashInstallationId_ThrowsWhenSaltIsMissing()
    {
        var hasher = new HmacDataDeletionAuditHasher(Options.Create(new DataDeletionOptions()));

        var error = Assert.Throws<InvalidOperationException>(() => hasher.HashInstallationId("installation-1"));

        Assert.Equal("DataDeletion__AuditHashSalt is required before writing deletion audit events.", error.Message);
    }
}
