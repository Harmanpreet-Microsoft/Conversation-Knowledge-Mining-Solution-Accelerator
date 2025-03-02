@minLength(3)
@maxLength(15)
@description('Solution Name')
param solutionName string
param solutionLocation string
param keyVaultName string
type FirewallRules = {
  @description('The list of IP address CIDR blocks to allow access from.')
  allowedIpAddresses: string[]
}
@description('Whether or not public endpoint access is allowed for this server')
param enablePublicNetworkAccess bool = true

@description('The firewall rules to install on the sql-server.')
param firewallRules FirewallRules?
@description('The Name of a user-assigned managed identity to use as the identity for this resource.  Use a blank string for a system-assigned identity.')
param managedIdentityName string = '${ solutionName }-managed-identity'
// param managedIdentityObjectId string

// @description('The name of the SQL logical server.')
// param serverName string = '${ solutionName }-sql-server'

// @description('The name of the SQL Database.')
// param sqlDBName string = '${ solutionName }-sql-db'

// @description('Location for all resources.')
// param location string = solutionLocation

// @description('The administrator username of the SQL logical server.')
// param administratorLogin string = 'sqladmin'

// @description('The administrator password of the SQL logical server.')
// @secure()
// param administratorLoginPassword string = 'TestPassword_1234'

var serverName = '${ solutionName }-sql-server'
var sqlDBName = '${ solutionName }-sql-db'
var location = solutionLocation
var administratorLogin = 'sqladmin'
var administratorLoginPassword = 'TestPassword_1234'

// resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
//   name: serverName
//   location: location
//   kind:'v12.0'
//   properties: {
//       administratorLogin: administratorLogin
//       administratorLoginPassword: administratorLoginPassword
//       publicNetworkAccess: 'Enabled'
//       version: '12.0'
//       restrictOutboundNetworkAccess: 'Disabled'
//     }
// }

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: managedIdentityName
}

resource sqlServer 'Microsoft.Sql/servers@2021-11-01' = {
  name: serverName
  location: location
 
  properties: {
    administrators: {
      azureADOnlyAuthentication: true
      login: managedIdentity.name
      principalType: 'User'
      sid: managedIdentity.properties.principalId
      tenantId: managedIdentity.properties.tenantId
    }
    publicNetworkAccess: enablePublicNetworkAccess || firewallRules != null ? 'Enabled' : 'Disabled'
    version: '12.0'
  }}
resource firewallRule 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = {
  name: 'AllowSpecificRange'
  parent: sqlServer
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '255.255.255.255'
  }
}

resource AllowAllWindowsAzureIps 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = {
  name: 'AllowAllWindowsAzureIps'
  parent: sqlServer
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource sqlDB 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  parent: sqlServer
  name: sqlDBName
  location: location
  sku: {
    name: 'GP_S_Gen5'
    tier: 'GeneralPurpose'
    family: 'Gen5'
    capacity: 2
  }
  kind:'v12.0,user,vcore,serverless'
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    autoPauseDelay:60
    minCapacity:1
    readScale: 'Disabled'
    zoneRedundant: false
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: keyVaultName
}

resource sqldbServerEntry 'Microsoft.KeyVault/vaults/secrets@2021-11-01-preview' = {
  parent: keyVault
  name: 'SQLDB-SERVER'
  properties: {
    value: '${serverName}.database.windows.net'
  }
}

resource sqldbDatabaseEntry 'Microsoft.KeyVault/vaults/secrets@2021-11-01-preview' = {
  parent: keyVault
  name: 'SQLDB-DATABASE'
  properties: {
    value: sqlDBName
  }
}

resource sqldbDatabaseUsername 'Microsoft.KeyVault/vaults/secrets@2021-11-01-preview' = {
  parent: keyVault
  name: 'SQLDB-USERNAME'
  properties: {
    value: administratorLogin
  }
}

resource sqldbDatabasePwd 'Microsoft.KeyVault/vaults/secrets@2021-11-01-preview' = {
  parent: keyVault
  name: 'SQLDB-PASSWORD'
  properties: {
    value: administratorLoginPassword
  }
}
module sqluser 'create-sql-user-and-role.bicep' = [for user in users: {
  name: 'sqluser-${guid(location, user.principalId, user.principalName, name, sqlServer.name)}'
  params: {
    managedIdentityId: managedIdentity.id
    principalId: user.principalId
    principalName: user.principalName
    sqlDatabaseName: sqlDBName
    location: location
    sqlServerName: sqlServer.name
    databaseRoles: ['db_owner']
  }
  dependsOn: [ sqlDBName ]
}]
output sqlServerName string = '${serverName}.database.windows.net'
output sqlDbName string = sqlDBName
output sqlDbUser string = administratorLogin

// output sqlDbOutput object = {
//   sqlServerName: '${serverName}.database.windows.net' 
//   sqlDbName: sqlDBName
//   sqlDbUser: administratorLogin
//   sqlDbPwd: administratorLoginPassword
// }
