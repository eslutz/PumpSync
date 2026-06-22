using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using PumpSync.Application.Abstractions;
using PumpSync.Domain.Common;
using PumpSync.Infrastructure.Auth;
using PumpSync.Infrastructure.DataDeletion;
using PumpSync.Infrastructure.Options;
using PumpSync.Infrastructure.TableStorage;
using PumpSync.Infrastructure.Tandem;

namespace PumpSync.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddPumpSyncInfrastructure(this IServiceCollection services, IConfiguration configuration)
    {
        services.Configure<PumpSyncOptions>(configuration.GetSection("PumpSync"));
        services.Configure<AppStoreOptions>(configuration.GetSection("AppStore"));
        services.Configure<AzureStorageOptions>(configuration.GetSection("AzureStorage"));
        services.Configure<DataDeletionOptions>(configuration.GetSection("DataDeletion"));
        services.Configure<TandemSourceOptions>(configuration.GetSection("TandemSource"));

        services.AddSingleton<IClock, SystemClock>();
        services.AddSingleton<IBackendModeProvider, BackendModeProvider>();
        services.AddSingleton<TableClientFactory>();
        services.AddScoped<TableStorageStateRepository>();
        services.AddScoped<IBillingEntitlementRepository>(sp => sp.GetRequiredService<TableStorageStateRepository>());
        services.AddScoped<IInstallationRepository>(sp => sp.GetRequiredService<TableStorageStateRepository>());
        services.AddScoped<ISyncStateRepository>(sp => sp.GetRequiredService<TableStorageStateRepository>());
        services.AddScoped<IRateLimiter>(sp => sp.GetRequiredService<TableStorageStateRepository>());
        services.AddScoped<IAppStoreNotificationIdempotencyStore>(sp => sp.GetRequiredService<TableStorageStateRepository>());
        services.AddScoped<IHostedDataDeletionRequestRepository, TableStorageDataDeletionRequestRepository>();
        services.AddSingleton<IDataDeletionAuditHasher, HmacDataDeletionAuditHasher>();

        services.AddSingleton<IAppStoreSignedPayloadVerifier, AppStoreSignedPayloadVerifier>();
        services.AddSingleton<ServiceTokenService>();
        services.AddSingleton<IServiceTokenIssuer>(sp => sp.GetRequiredService<ServiceTokenService>());
        services.AddSingleton<IServiceTokenValidator>(sp => sp.GetRequiredService<ServiceTokenService>());

        services.AddHttpClient<ITandemAuthenticator, TandemSourceAuthenticator>()
            .ConfigurePrimaryHttpMessageHandler(() => new HttpClientHandler { AllowAutoRedirect = true, UseCookies = true });
        services.AddHttpClient<ITandemEventClient, TandemEventClient>();

        return services;
    }
}
