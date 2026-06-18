using Microsoft.Extensions.Options;
using PumpSync.Application.Abstractions;
using PumpSync.Infrastructure.Options;

namespace PumpSync.Infrastructure;

public sealed class BackendModeProvider(IOptions<PumpSyncOptions> options) : IBackendModeProvider
{
    public bool IsSelfHosted => options.Value.BackendMode.Equals("SelfHosted", StringComparison.OrdinalIgnoreCase);
}
