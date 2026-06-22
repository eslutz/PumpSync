using System.Text.Json;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using PumpSync.Application;
using PumpSync.Application.UseCases;
using PumpSync.Infrastructure;

var options = CommandOptions.Parse(args);
if (options.ShowHelp)
{
    Console.WriteLine(CommandOptions.HelpText);
    return 0;
}

if (options.ErrorMessage is not null)
{
    Console.Error.WriteLine(options.ErrorMessage);
    Console.Error.WriteLine(CommandOptions.HelpText);
    return 2;
}

try
{
    var configuration = BuildConfiguration(options.Environment);
    var services = new ServiceCollection()
        .AddPumpSyncApplication()
        .AddPumpSyncInfrastructure(configuration)
        .BuildServiceProvider();

    using var scope = services.CreateScope();
    var useCase = scope.ServiceProvider.GetRequiredService<DataDeletionRequestUseCase>();
    var report = await useCase.ExecuteAsync(
        new HostedDataDeletionRequest(options.InstallationId, options.Environment, options.Execute),
        CancellationToken.None);

    Console.WriteLine(JsonSerializer.Serialize(report, new JsonSerializerOptions(JsonSerializerDefaults.Web)
    {
        WriteIndented = true
    }));
    return 0;
}
catch (Exception ex)
{
    Console.Error.WriteLine(ex.Message);
    return 1;
}

static IConfiguration BuildConfiguration(string environment)
{
    var baseConfiguration = new ConfigurationBuilder()
        .SetBasePath(AppContext.BaseDirectory)
        .AddJsonFile("appsettings.json", optional: true)
        .AddUserSecrets<CommandOptions>(optional: true)
        .AddEnvironmentVariables()
        .Build();

    var environmentSection = baseConfiguration.GetSection($"AzureStorage:Environments:{environment}");
    var overrides = new Dictionary<string, string?>();
    AddOverride(overrides, baseConfiguration, environmentSection, "ConnectionString");
    AddOverride(overrides, baseConfiguration, environmentSection, "AccountName");
    AddOverride(overrides, baseConfiguration, environmentSection, "Credential");

    return new ConfigurationBuilder()
        .SetBasePath(AppContext.BaseDirectory)
        .AddConfiguration(baseConfiguration)
        .AddInMemoryCollection(overrides)
        .Build();
}

static void AddOverride(
    IDictionary<string, string?> overrides,
    IConfiguration baseConfiguration,
    IConfiguration environmentSection,
    string key)
{
    var environmentValue = environmentSection[key];
    var explicitValue = baseConfiguration[$"AzureStorage:{key}"];
    if (string.IsNullOrWhiteSpace(explicitValue) && !string.IsNullOrWhiteSpace(environmentValue))
    {
        overrides[$"AzureStorage:{key}"] = environmentValue;
    }
}

internal sealed record CommandOptions(
    string InstallationId,
    string Environment,
    bool Execute,
    bool ShowHelp,
    string? ErrorMessage)
{
    public const string HelpText = """
        Usage:
          PumpSync.DataDeletionRequest --installation-id <ID> --environment <nonprod|prod> [--execute]

        Defaults to dry-run mode. Add --execute to purge matching records and write a hashed audit event.
        Configure AzureStorage__AccountName or AzureStorage__ConnectionString, and set DataDeletion__AuditHashSalt before using --execute.
        """;

    public static CommandOptions Parse(string[] args)
    {
        var installationId = "";
        var environment = "";
        var execute = false;

        for (var index = 0; index < args.Length; index++)
        {
            var arg = args[index];
            switch (arg)
            {
                case "--help" or "-h":
                    return new CommandOptions("", "", false, true, null);
                case "--execute":
                    execute = true;
                    break;
                case "--installation-id":
                    if (!TryReadValue(args, ref index, out installationId))
                    {
                        return Invalid("--installation-id requires a value.");
                    }

                    break;
                case "--environment":
                    if (!TryReadValue(args, ref index, out environment))
                    {
                        return Invalid("--environment requires a value.");
                    }

                    break;
                default:
                    return Invalid($"Unknown argument: {arg}");
            }
        }

        if (string.IsNullOrWhiteSpace(installationId))
        {
            return Invalid("--installation-id is required.");
        }

        if (environment is not "nonprod" and not "prod")
        {
            return Invalid("--environment must be either nonprod or prod.");
        }

        return new CommandOptions(installationId, environment, execute, false, null);
    }

    private static bool TryReadValue(string[] args, ref int index, out string value)
    {
        if (index + 1 >= args.Length || args[index + 1].StartsWith("--", StringComparison.Ordinal))
        {
            value = "";
            return false;
        }

        index++;
        value = args[index];
        return true;
    }

    private static CommandOptions Invalid(string message) => new("", "", false, false, message);
}
