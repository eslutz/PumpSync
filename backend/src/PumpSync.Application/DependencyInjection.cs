using Microsoft.Extensions.DependencyInjection;
using PumpSync.Application.Idempotency;
using PumpSync.Application.Normalization;
using PumpSync.Application.UseCases;

namespace PumpSync.Application;

public static class DependencyInjection
{
    public static IServiceCollection AddPumpSyncApplication(this IServiceCollection services)
    {
        services.AddSingleton<IdempotentExecutor>();
        services.AddSingleton<Abstractions.ISampleNormalizer, TandemSampleNormalizer>();
        services.AddScoped<AuthAppleSessionUseCase>();
        services.AddScoped<HandleAppleServerNotificationUseCase>();
        services.AddScoped<AuthenticatedUserGuard>();
        services.AddScoped<SyncTandemUseCase>();
        services.AddScoped<GetStatusUseCase>();
        return services;
    }
}
