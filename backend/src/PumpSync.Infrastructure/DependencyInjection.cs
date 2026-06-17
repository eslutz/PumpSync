using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using PumpSync.Application.Abstractions;
using PumpSync.Domain.Common;
using PumpSync.Infrastructure.Auth;
using PumpSync.Infrastructure.Options;
using PumpSync.Infrastructure.Sql;
using PumpSync.Infrastructure.Tandem;

namespace PumpSync.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddPumpSyncInfrastructure(this IServiceCollection services, IConfiguration configuration)
    {
        services.Configure<PumpSyncOptions>(configuration.GetSection("PumpSync"));
        services.Configure<AppleOptions>(configuration.GetSection("Apple"));
        services.Configure<AzureSqlOptions>(configuration.GetSection("AzureSql"));
        services.Configure<AzureStorageOptions>(configuration.GetSection("AzureStorage"));
        services.Configure<TandemSourceOptions>(configuration.GetSection("TandemSource"));

        services.AddSingleton<IClock, SystemClock>();
        services.AddSingleton<SqlConnectionFactory>();
        services.AddScoped<IUserRepository, SqlUserRepository>();
        services.AddScoped<IBillingEntitlementRepository, SqlBillingEntitlementRepository>();
        services.AddScoped<ISyncStateRepository, SqlSyncStateRepository>();
        services.AddScoped<IIdempotencyStore, SqlIdempotencyStore>();
        services.AddScoped<IRateLimiter, SqlRateLimiter>();

        services.AddSingleton<IAppleIdentityValidator, AppleIdentityValidator>();
        services.AddSingleton<ServiceTokenService>();
        services.AddSingleton<IServiceTokenIssuer>(sp => sp.GetRequiredService<ServiceTokenService>());
        services.AddSingleton<IServiceTokenValidator>(sp => sp.GetRequiredService<ServiceTokenService>());

        services.AddHttpClient<ITandemAuthenticator, TandemSourceAuthenticator>()
            .ConfigurePrimaryHttpMessageHandler(() => new HttpClientHandler { AllowAutoRedirect = true, UseCookies = true });
        services.AddHttpClient<ITandemEventClient, TandemEventClient>();

        return services;
    }
}
