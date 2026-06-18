using PumpSync.ApiContracts;
using PumpSync.Application.Abstractions;
using PumpSync.Domain.Common;

namespace PumpSync.Application.UseCases;

public sealed class CreateSelfHostedSessionUseCase(
    IServiceTokenIssuer tokens,
    IClock clock,
    IBackendModeProvider backendMode)
{
    public BackendSessionResponse Execute(SelfHostedSessionRequest request)
    {
        if (!backendMode.IsSelfHosted)
        {
            throw new UnauthorizedAccessException("Self-hosted sessions are not available on PumpSync Hosted.");
        }

        if (string.IsNullOrWhiteSpace(request.InstallationId))
        {
            throw new ArgumentException("Installation id is required.", nameof(request));
        }

        var user = SubjectIdentity.SelfHosted(request.InstallationId);
        var expiresAt = clock.UtcNow.AddHours(12);
        return new BackendSessionResponse(tokens.IssueToken(user, expiresAt), expiresAt, true, "selfHosted");
    }
}
