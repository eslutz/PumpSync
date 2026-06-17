using '../bicep/main.bicep'

param location = readEnvironmentVariable('AZURE_LOCATION', 'eastus')
param environmentName = 'prod'
param appName = 'pumpsync'
param appleClientId = readEnvironmentVariable('APPLE_CLIENT_ID', '')
param sqlAdministratorLogin = readEnvironmentVariable('AZURE_SQL_ADMIN_LOGIN', 'pumpsyncadmin')
param sqlAdministratorPassword = readEnvironmentVariable('AZURE_SQL_ADMIN_PASSWORD', '')
param serviceTokenSigningKey = readEnvironmentVariable('PUMPSYNC_SERVICE_TOKEN_SIGNING_KEY', '')
param allowedSqlCidrs = []
