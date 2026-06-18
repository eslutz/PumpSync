using System.Diagnostics;
using Microsoft.Extensions.Logging;
using PumpSync.ApiContracts;
using PumpSync.Application.Abstractions;
using PumpSync.Domain.Common;

namespace PumpSync.Application.UseCases;

public sealed class AuthAppleSessionUseCase(
    IAppleIdentityValidator validator,
    IUserRepository users,
    IServiceTokenIssuer tokenIssuer,
    IClock clock,
    ILogger<AuthAppleSessionUseCase> logger)
{
    public async Task<AppleSessionResponse> ExecuteAsync(AppleSessionRequest request, CancellationToken cancellationToken)
    {
        var totalStartedAt = Stopwatch.GetTimestamp();
        logger.LogInformation("Apple session creation started.");

        try
        {
            var validationStartedAt = Stopwatch.GetTimestamp();
            var identity = await validator.ValidateAsync(request.IdentityToken, cancellationToken);
            logger.LogInformation(
                "Apple identity token validated in {DurationMs} ms. HasEmail={HasEmail} EmailVerified={EmailVerified} RealUserStatus={RealUserStatus}",
                ElapsedMilliseconds(validationStartedAt),
                !string.IsNullOrWhiteSpace(identity.Email),
                identity.EmailVerified,
                identity.RealUserStatus ?? "unknown");

            var upsertStartedAt = Stopwatch.GetTimestamp();
            var user = await users.UpsertAppleUserAsync(identity, cancellationToken);
            logger.LogInformation(
                "Apple user upsert completed in {DurationMs} ms for UserId={UserId}.",
                ElapsedMilliseconds(upsertStartedAt),
                user.UserId);

            var tokenStartedAt = Stopwatch.GetTimestamp();
            var expiresAt = clock.UtcNow.AddHours(12);
            var token = tokenIssuer.IssueToken(user.UserId, identity.Subject, expiresAt);
            logger.LogInformation(
                "PumpSync service token issued in {DurationMs} ms for UserId={UserId}; ExpiresAt={ExpiresAt}.",
                ElapsedMilliseconds(tokenStartedAt),
                user.UserId,
                expiresAt);

            logger.LogInformation(
                "Apple session creation completed in {DurationMs} ms for UserId={UserId}.",
                ElapsedMilliseconds(totalStartedAt),
                user.UserId);

            return new AppleSessionResponse(
                token,
                expiresAt,
                new UserSummary(user.UserId.ToString(), user.Email));
        }
        catch (Exception ex)
        {
            logger.LogWarning(
                ex,
                "Apple session creation failed after {DurationMs} ms.",
                ElapsedMilliseconds(totalStartedAt));
            throw;
        }
    }

    private static long ElapsedMilliseconds(long startedAt) =>
        (long)Stopwatch.GetElapsedTime(startedAt).TotalMilliseconds;
}
