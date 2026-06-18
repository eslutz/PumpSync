using PumpSync.ApiContracts;
using PumpSync.Application.Abstractions;

namespace PumpSync.Application.UseCases;

public sealed class GetCapabilitiesUseCase(IBackendModeProvider backendMode)
{
    public CapabilitiesResponse Execute()
    {
        var serviceMode = backendMode.IsSelfHosted ? "selfHosted" : "hosted";
        var billingMode = serviceMode == "hosted" ? "hostedSubscription" : "selfHosted";

        return new CapabilitiesResponse(
            "2026-06-18",
            serviceMode,
            billingMode,
            "device-keychain-only",
            "server-does-not-retain-tandem-data");
    }
}
