using PumpSync.ApiContracts;
using PumpSync.Application.Abstractions;
using PumpSync.Domain.Auth;

namespace PumpSync.Application.UseCases;

public sealed class GetStatusUseCase(
    IBillingEntitlementRepository billing)
{
    public async Task<StatusResponse> ExecuteAsync(AuthenticatedUser user, CancellationToken cancellationToken)
    {
        var entitlement = await billing.GetActiveEntitlementAsync(user.UserId, cancellationToken);

        return new StatusResponse(
            entitlement is not null,
            "device-keychain-only",
            "server-does-not-retain-tandem-data");
    }
}
