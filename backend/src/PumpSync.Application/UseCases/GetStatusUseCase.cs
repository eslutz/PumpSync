using PumpSync.ApiContracts;
using PumpSync.Application.Abstractions;
using PumpSync.Domain.Auth;
using PumpSync.Domain.Billing;

namespace PumpSync.Application.UseCases;

public sealed class GetStatusUseCase(
    IBillingEntitlementRepository billing)
{
    public async Task<StatusResponse> ExecuteAsync(AuthenticatedUser user, CancellationToken cancellationToken)
    {
        var entitlement = user.Mode is AuthenticatedUserMode.SelfHosted
            ? new BillingEntitlement(user.SubjectId, "self-hosted", BillingEntitlementStatus.Active, "SelfHosted", null, DateTimeOffset.UtcNow)
            : await billing.GetActiveEntitlementAsync(user.SubjectId, cancellationToken);

        return new StatusResponse(
            entitlement is not null,
            user.Mode is AuthenticatedUserMode.SelfHosted ? "selfHosted" : "hosted",
            "device-keychain-only",
            "server-does-not-retain-tandem-data");
    }
}
