using System.Diagnostics;
using Microsoft.Extensions.Logging;
using PumpSync.ApiContracts;
using PumpSync.Application.Abstractions;
using PumpSync.Domain.Auth;

namespace PumpSync.Application.UseCases;

public sealed class HandleAppleServerNotificationUseCase(
    IAppleServerNotificationValidator validator,
    IUserRepository users,
    ILogger<HandleAppleServerNotificationUseCase> logger)
{
    public async Task<AppleServerNotificationResponse> ExecuteAsync(
        AppleServerNotificationRequest request,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.Payload))
        {
            throw new ArgumentException("Apple notification payload is required.", nameof(request));
        }

        var totalStartedAt = Stopwatch.GetTimestamp();
        logger.LogInformation("Apple server notification processing started.");

        try
        {
            var validationStartedAt = Stopwatch.GetTimestamp();
            var notification = await validator.ValidateAsync(request.Payload, cancellationToken);
            logger.LogInformation(
                "Apple server notification payload validated in {DurationMs} ms with {EventCount} event(s).",
                ElapsedMilliseconds(validationStartedAt),
                notification.Events.Count);

            foreach (var notificationEvent in notification.Events)
            {
                var eventStartedAt = Stopwatch.GetTimestamp();
                await HandleEventAsync(notificationEvent, cancellationToken);
                logger.LogInformation(
                    "Apple server notification event handled in {DurationMs} ms. Type={EventType} HasEmail={HasEmail}",
                    ElapsedMilliseconds(eventStartedAt),
                    notificationEvent.Type,
                    !string.IsNullOrWhiteSpace(notificationEvent.Email));
            }

            logger.LogInformation(
                "Apple server notification processing completed in {DurationMs} ms with {EventCount} event(s).",
                ElapsedMilliseconds(totalStartedAt),
                notification.Events.Count);

            return new AppleServerNotificationResponse(notification.Events.Count);
        }
        catch (Exception ex)
        {
            logger.LogWarning(
                ex,
                "Apple server notification processing failed after {DurationMs} ms.",
                ElapsedMilliseconds(totalStartedAt));
            throw;
        }
    }

    private Task HandleEventAsync(AppleServerNotificationEvent notificationEvent, CancellationToken cancellationToken) =>
        notificationEvent.Type switch
        {
            "email-disabled" => users.SetAppleEmailForwardingAsync(
                notificationEvent.AppleSubject,
                notificationEvent.Email,
                enabled: false,
                cancellationToken),
            "email-enabled" => users.SetAppleEmailForwardingAsync(
                notificationEvent.AppleSubject,
                notificationEvent.Email,
                enabled: true,
                cancellationToken),
            "consent-revoked" => users.SetAppleUserStatusAsync(
                notificationEvent.AppleSubject,
                "Revoked",
                cancellationToken),
            "account-delete" or "account-deleted" => users.SetAppleUserStatusAsync(
                notificationEvent.AppleSubject,
                "Deleted",
                cancellationToken),
            _ => Task.CompletedTask
        };

    private static long ElapsedMilliseconds(long startedAt) =>
        (long)Stopwatch.GetElapsedTime(startedAt).TotalMilliseconds;
}
