using '../bicep/main.subscription.bicep'

param location = readEnvironmentVariable('AZURE_LOCATION', 'eastus2')
param environmentName = 'nonprod'
param appName = 'pumpsync'
param resourceGroupName = readEnvironmentVariable('AZURE_RESOURCE_GROUP', 'rg-pumpsync-nonprod')
param appleClientId = readEnvironmentVariable('APPLE_CLIENT_ID', 'com.ericslutz.PumpSync')
param sqlServer = readEnvironmentVariable('AZURE_SQL_SERVER', 'ericslutz-dev-db.database.windows.net')
param sqlDatabase = readEnvironmentVariable('AZURE_SQL_DATABASE', 'ericslutz.dev.db')
param serviceTokenSigningKey = readEnvironmentVariable('PUMPSYNC_SERVICE_TOKEN_SIGNING_KEY', '')
param logDrainSharedSecret = readEnvironmentVariable('PUMPSYNC_LOG_DRAIN_SHARED_SECRET', '')
param modelCostUpdaterSchedule = readEnvironmentVariable('PUMPSYNC_MODEL_COST_UPDATER_SCHEDULE', '0 0 4 * * *')
param modelCostUpdaterCatalogUrl = readEnvironmentVariable('PUMPSYNC_MODEL_COST_CATALOG_URL', '')
