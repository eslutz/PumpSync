using PumpSync.ApiContracts;
using PumpSync.Application.Validation;
using Xunit;

namespace PumpSync.Tests;

public sealed class TandemSyncRequestValidatorTests
{
    private static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-06-17T12:00:00Z");

    [Fact]
    public void Validate_AllowsCurrentCredentialBearingSyncWindow()
    {
        var request = new TandemSyncRequest(
            new TandemCredentialsDto("user@example.com", "correct horse battery staple", "us"),
            "pump-1",
            Now.AddDays(-1),
            Now);

        TandemSyncRequestValidator.Validate(request, Now);
    }

    [Theory]
    [InlineData("", "password", "us", "Tandem username is required.")]
    [InlineData("user@example.com", "", "us", "Tandem password is required.")]
    [InlineData("user@example.com", "password", "apac", "Tandem region must be 'us' or 'eu'.")]
    public void Validate_RejectsInvalidCredentialFields(string username, string password, string region, string expectedMessage)
    {
        var request = new TandemSyncRequest(
            new TandemCredentialsDto(username, password, region),
            null,
            Now.AddDays(-1),
            Now);

        var ex = Assert.Throws<InvalidOperationException>(() => TandemSyncRequestValidator.Validate(request, Now));
        Assert.Equal(expectedMessage, ex.Message);
    }

    [Fact]
    public void Validate_RejectsSyncWindowOverLookbackLimit()
    {
        var request = new TandemSyncRequest(
            new TandemCredentialsDto("user@example.com", "password", "eu"),
            null,
            Now.AddDays(-15),
            Now);

        var ex = Assert.Throws<InvalidOperationException>(() => TandemSyncRequestValidator.Validate(request, Now));
        Assert.Equal("Tandem sync windows cannot exceed 14 days.", ex.Message);
    }

    [Fact]
    public void Validate_RejectsMaxDateInFuture()
    {
        var request = new TandemSyncRequest(
            new TandemCredentialsDto("user@example.com", "password", "us"),
            null,
            Now.AddHours(-1),
            Now.AddMinutes(6));

        var ex = Assert.Throws<InvalidOperationException>(() => TandemSyncRequestValidator.Validate(request, Now));
        Assert.Equal("MaxDate cannot be in the future.", ex.Message);
    }
}
