using Microsoft.Extensions.Logging.Abstractions;
using PumpSync.ApiContracts;
using PumpSync.Application.Abstractions;
using PumpSync.Application.UseCases;
using PumpSync.Domain.Auth;
using PumpSync.Domain.Users;
using Xunit;

namespace PumpSync.Tests;

public sealed class AppleServerNotificationUseCaseTests
{
    [Fact]
    public async Task ExecuteAsync_MarksRelayEmailUndeliverable_WhenEmailForwardingIsDisabled()
    {
        var users = new RecordingUserRepository();
        var useCase = new HandleAppleServerNotificationUseCase(
            new StubAppleServerNotificationValidator(
                new AppleServerNotification(
                    [new AppleServerNotificationEvent("email-disabled", "apple-subject", "relay@example.com")])),
            users,
            NullLogger<HandleAppleServerNotificationUseCase>.Instance);

        var response = await useCase.ExecuteAsync(new AppleServerNotificationRequest("signed-payload"), CancellationToken.None);

        Assert.Equal(1, response.ProcessedEvents);
        Assert.Equal(("apple-subject", "relay@example.com", false), users.EmailForwardingUpdates.Single());
    }

    [Fact]
    public async Task ExecuteAsync_MarksRelayEmailDeliverable_WhenEmailForwardingIsEnabled()
    {
        var users = new RecordingUserRepository();
        var useCase = new HandleAppleServerNotificationUseCase(
            new StubAppleServerNotificationValidator(
                new AppleServerNotification(
                    [new AppleServerNotificationEvent("email-enabled", "apple-subject", "relay@example.com")])),
            users,
            NullLogger<HandleAppleServerNotificationUseCase>.Instance);

        await useCase.ExecuteAsync(new AppleServerNotificationRequest("signed-payload"), CancellationToken.None);

        Assert.Equal(("apple-subject", "relay@example.com", true), users.EmailForwardingUpdates.Single());
    }

    [Theory]
    [InlineData("consent-revoked", "Revoked")]
    [InlineData("account-delete", "Deleted")]
    [InlineData("account-deleted", "Deleted")]
    public async Task ExecuteAsync_DeactivatesUser_WhenAppleAuthorizationIsNoLongerValid(string eventType, string expectedStatus)
    {
        var users = new RecordingUserRepository();
        var useCase = new HandleAppleServerNotificationUseCase(
            new StubAppleServerNotificationValidator(
                new AppleServerNotification(
                    [new AppleServerNotificationEvent(eventType, "apple-subject", null)])),
            users,
            NullLogger<HandleAppleServerNotificationUseCase>.Instance);

        await useCase.ExecuteAsync(new AppleServerNotificationRequest("signed-payload"), CancellationToken.None);

        Assert.Equal(("apple-subject", expectedStatus), users.StatusUpdates.Single());
    }

    [Fact]
    public async Task ExecuteAsync_RejectsMissingPayload()
    {
        var useCase = new HandleAppleServerNotificationUseCase(
            new StubAppleServerNotificationValidator(new AppleServerNotification([])),
            new RecordingUserRepository(),
            NullLogger<HandleAppleServerNotificationUseCase>.Instance);

        await Assert.ThrowsAsync<ArgumentException>(
            () => useCase.ExecuteAsync(new AppleServerNotificationRequest(" "), CancellationToken.None));
    }

    private sealed class StubAppleServerNotificationValidator(AppleServerNotification notification) : IAppleServerNotificationValidator
    {
        public Task<AppleServerNotification> ValidateAsync(string payload, CancellationToken cancellationToken) =>
            Task.FromResult(notification);
    }
}

public sealed class AuthenticatedUserGuardTests
{
    [Fact]
    public async Task EnsureActiveAsync_AllowsActiveMatchingAppleSubject()
    {
        var userId = UserId.New();
        var users = new RecordingUserRepository
        {
            ActiveUser = (userId, "apple-subject")
        };
        var guard = new AuthenticatedUserGuard(users);

        await guard.EnsureActiveAsync(new AuthenticatedUser(userId, "apple-subject", []), CancellationToken.None);
    }

    [Fact]
    public async Task EnsureActiveAsync_RejectsInactiveUser()
    {
        var guard = new AuthenticatedUserGuard(new RecordingUserRepository());

        await Assert.ThrowsAsync<UnauthorizedAccessException>(
            () => guard.EnsureActiveAsync(new AuthenticatedUser(UserId.New(), "apple-subject", []), CancellationToken.None));
    }

    [Fact]
    public async Task EnsureActiveAsync_RejectsAppleSubjectMismatch()
    {
        var userId = UserId.New();
        var users = new RecordingUserRepository
        {
            ActiveUser = (userId, "other-subject")
        };
        var guard = new AuthenticatedUserGuard(users);

        await Assert.ThrowsAsync<UnauthorizedAccessException>(
            () => guard.EnsureActiveAsync(new AuthenticatedUser(userId, "apple-subject", []), CancellationToken.None));
    }
}

internal sealed class RecordingUserRepository : IUserRepository
{
    public List<(string AppleSubject, string? Email, bool Enabled)> EmailForwardingUpdates { get; } = [];

    public List<(string AppleSubject, string Status)> StatusUpdates { get; } = [];

    public (UserId UserId, string AppleSubject)? ActiveUser { get; init; }

    public Task<(UserId UserId, string? Email)> UpsertAppleUserAsync(AppleIdentity identity, CancellationToken cancellationToken) =>
        Task.FromResult((UserId.New(), identity.Email));

    public Task<(UserId UserId, string AppleSubject)?> FindByIdAsync(UserId userId, CancellationToken cancellationToken) =>
        Task.FromResult(ActiveUser);

    public Task SetAppleEmailForwardingAsync(string appleSubject, string? email, bool enabled, CancellationToken cancellationToken)
    {
        EmailForwardingUpdates.Add((appleSubject, email, enabled));
        return Task.CompletedTask;
    }

    public Task SetAppleUserStatusAsync(string appleSubject, string status, CancellationToken cancellationToken)
    {
        StatusUpdates.Add((appleSubject, status));
        return Task.CompletedTask;
    }
}
