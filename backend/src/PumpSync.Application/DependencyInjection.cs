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
        services.AddScoped<GetCapabilitiesUseCase>();
        services.AddScoped<CreateSubscriptionSessionUseCase>();
        services.AddScoped<CreateSelfHostedSessionUseCase>();
        services.AddScoped<HandleAppStoreNotificationUseCase>();
        services.AddScoped<DataDeletionRequestUseCase>();
        services.AddScoped<BackendAccessGuard>();
        services.AddScoped<SyncTandemUseCase>();
        services.AddScoped<ValidateTandemCredentialsUseCase>();
        services.AddScoped<GetStatusUseCase>();
        return services;
    }
}
