using PumpSync.ApiContracts;
using PumpSync.Application.Abstractions;
using PumpSync.Application.UseCases;
using PumpSync.Domain.Auth;
using PumpSync.Domain.Tandem;
using PumpSync.Domain.Users;
using Xunit;

namespace PumpSync.Tests;

public sealed class ValidateTandemCredentialsUseCaseTests
{
    [Fact]
    public async Task ExecuteAsync_AuthenticatesTandemCredentials()
    {
        var authenticator = new FakeTandemAuthenticator();
        var useCase = new ValidateTandemCredentialsUseCase(
            new FakeRateLimiter(allowed: true),
            authenticator);

        var response = await useCase.ExecuteAsync(
            User(),
            new TandemCredentialValidationRequest(new TandemCredentialsDto("user@example.com", "password", "us")),
            CancellationToken.None);

        Assert.True(response.Validated);
        Assert.Equal("user@example.com", authenticator.LastCredentials?.Username);
        Assert.Equal(TandemRegion.Us, authenticator.LastCredentials?.Region);
    }

    [Fact]
    public async Task ExecuteAsync_RejectsWhenRateLimited()
    {
        var useCase = new ValidateTandemCredentialsUseCase(
            new FakeRateLimiter(allowed: false),
            new FakeTandemAuthenticator());

        var ex = await Assert.ThrowsAsync<InvalidOperationException>(() =>
            useCase.ExecuteAsync(
                User(),
                new TandemCredentialValidationRequest(new TandemCredentialsDto("user@example.com", "password", "eu")),
                CancellationToken.None));

        Assert.Equal("Tandem credential validation rate limit exceeded.", ex.Message);
    }

    private static AuthenticatedUser User() =>
        new(UserId.New(), "original-transaction-id", "installation-id", AuthenticatedUserMode.Hosted, []);

    private sealed class FakeRateLimiter(bool allowed) : IRateLimiter
    {
        public Task<bool> AllowAsync(UserId userId, string operation, int maxRequests, TimeSpan window, CancellationToken cancellationToken)
        {
            Assert.Equal("validate-tandem-credentials", operation);
            return Task.FromResult(allowed);
        }
    }

    private sealed class FakeTandemAuthenticator : ITandemAuthenticator
    {
        public TandemCredentials? LastCredentials { get; private set; }

        public Task<TandemSession> LoginAsync(TandemCredentials credentials, CancellationToken cancellationToken)
        {
            LastCredentials = credentials;
            return Task.FromResult(new TandemSession(
                credentials.Region,
                "access-token",
                "pumper-id",
                "account-id",
                "device-id",
                DateTimeOffset.UtcNow.AddHours(1)));
        }
    }
}
