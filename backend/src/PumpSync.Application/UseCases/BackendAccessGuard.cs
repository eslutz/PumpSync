using PumpSync.Application.Abstractions;
using PumpSync.Domain.Auth;

namespace PumpSync.Application.UseCases;

public sealed class BackendAccessGuard(IBillingEntitlementRepository entitlements)
{
    public async Task EnsureAccessAsync(AuthenticatedUser user, CancellationToken cancellationToken)
    {
        if (user.Mode is AuthenticatedUserMode.SelfHosted)
        {
            return;
        }

        var entitlement = await entitlements.GetActiveEntitlementAsync(user.SubjectId, cancellationToken);
        if (entitlement is null)
        {
            throw new UnauthorizedAccessException("An active PumpSync Hosted subscription is required.");
        }
    }
}
