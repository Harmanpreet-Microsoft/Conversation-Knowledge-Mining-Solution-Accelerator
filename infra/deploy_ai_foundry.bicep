// Creates Azure dependent resources for Azure AI studio

@minLength(3)
@maxLength(16)
@description('Required. Contains Solution Name')
param solutionName string

@description('Required. Specifies the location for resources.')
param solutionLocation string

@description('Optional. Contains KeyVault Name')
param keyVaultName string=''

@description('Required. Contains CU Location')
param cuLocation string

@description('Required. Contains type of Deployment')
param deploymentType string

@description('Required. Contains GPT mode Name')
param gptModelName string

@description('Required. Contains GPT Model Version')
param gptModelVersion string

@description('Required. Contains Open AI API version')
param azureOpenAIApiVersion string

@description('Required. Contains GPT Deployment Capacity')
param gptDeploymentCapacity int

@description('Required. Contains Embedding Model')
param embeddingModel string

@description('Required. Contains Embedding Deployment Capacity')
param embeddingDeploymentCapacity int

@description('Optional. Contains Managed Identity ObjectID')
param managedIdentityObjectId string=''

@description('Optional. Contains existing Log Analytics Workspace ID')
param existingLogAnalyticsWorkspaceId string = ''

@description('Optional. Contains existing AI Project Resource ID')
param azureExistingAIProjectResourceId string = ''

@description('Optional. Tags to be applied to the resources.')
param tags object = {}

//var abbrs = loadJsonContent('./abbreviations.json')
var aiServicesName = 'aisa-${solutionName}'
var aiServicesName_cu = 'aisa-${solutionName}-cu'
var location_cu = cuLocation
var workspaceName = 'log-${solutionName}'
var applicationInsightsName = 'appi-${solutionName}'
var keyvaultName = 'kv-${solutionName}'
var location = solutionLocation //'eastus2'
var aiProjectName = 'proj-${solutionName}'
var aiSearchName = 'srch-${solutionName}'
var aiSearchConnectionName = 'myCon-${solutionName}'

var aiModelDeployments = [
  {
    name: gptModelName
    model: gptModelName
    sku: {
      name: deploymentType
      capacity: gptDeploymentCapacity
    }
    version: gptModelVersion
    raiPolicyName: 'Microsoft.Default'
  }
  {
    name: embeddingModel
    model: embeddingModel
    sku: {
      name: 'GlobalStandard'
      capacity: embeddingDeploymentCapacity
    }
    raiPolicyName: 'Microsoft.Default'
  }
]

var useExisting = !empty(existingLogAnalyticsWorkspaceId)
var existingLawSubscription = useExisting ? split(existingLogAnalyticsWorkspaceId, '/')[2] : ''
var existingLawResourceGroup = useExisting ? split(existingLogAnalyticsWorkspaceId, '/')[4] : ''
var existingLawName = useExisting ? split(existingLogAnalyticsWorkspaceId, '/')[8] : ''

var existingOpenAIEndpoint = !empty(azureExistingAIProjectResourceId) ? format('https://{0}.openai.azure.com/', split(azureExistingAIProjectResourceId, '/')[8]) : ''
var existingProjEndpoint = !empty(azureExistingAIProjectResourceId) ? format('https://{0}.services.ai.azure.com/api/projects/{1}', split(azureExistingAIProjectResourceId, '/')[8], split(azureExistingAIProjectResourceId, '/')[10]) : ''
var existingAIServicesName = !empty(azureExistingAIProjectResourceId) ? split(azureExistingAIProjectResourceId, '/')[8] : ''
var existingAIProjectName = !empty(azureExistingAIProjectResourceId) ? split(azureExistingAIProjectResourceId, '/')[10] : ''
var existingAIServiceSubscription = !empty(azureExistingAIProjectResourceId) ? split(azureExistingAIProjectResourceId, '/')[2] : subscription().subscriptionId
var existingAIServiceResourceGroup = !empty(azureExistingAIProjectResourceId) ? split(azureExistingAIProjectResourceId, '/')[4] : resourceGroup().name

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: keyVaultName
}

resource existingLogAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = if (useExisting) {
  name: existingLawName
  scope: resourceGroup(existingLawSubscription ,existingLawResourceGroup)
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if (!useExisting){
  name: workspaceName
  location: location
  tags: tags
  properties: {
    retentionInDays: 30
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Disabled'
    WorkspaceResourceId: useExisting ? existingLogAnalyticsWorkspace.id : logAnalytics.id
  }
  tags : tags
}

resource aiServices 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' =  if (empty(azureExistingAIProjectResourceId)) {
  name: aiServicesName
  location: location
  sku: {
    name: 'S0'
  }
  kind: 'AIServices'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    allowProjectManagement: true
    customSubDomainName: aiServicesName
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false //needs to be false to access keys 
  }
  tags : tags
}

module existing_aiServicesModule 'existing_foundry_project.bicep' = if (!empty(azureExistingAIProjectResourceId)) {
  name: 'existing_foundry_project'
  scope: resourceGroup(existingAIServiceSubscription, existingAIServiceResourceGroup)
  params: {
    aiServicesName: existingAIServicesName
    aiProjectName: existingAIProjectName
  }
}

resource aiServices_CU 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = {
  name: aiServicesName_cu
  location: location_cu
  sku: {
    name: 'S0'
  }
  kind: 'AIServices'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    allowProjectManagement: true
    customSubDomainName: aiServicesName_cu
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false //needs to be false to access keys 
  }
  tags : tags
}

@batchSize(1)
resource aiServicesDeployments 'Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview' = [for aiModeldeployment in aiModelDeployments: if (empty(azureExistingAIProjectResourceId)) {
  parent: aiServices //aiServices_m
  name: aiModeldeployment.name
  properties: {
    model: {
      format: 'OpenAI'
      name: aiModeldeployment.model
    }
    raiPolicyName: aiModeldeployment.raiPolicyName
  }
  sku:{
    name: aiModeldeployment.sku.name
    capacity: aiModeldeployment.sku.capacity
  }
  tags : tags
}]

resource aiSearch 'Microsoft.Search/searchServices@2024-06-01-preview' = {
  name: aiSearchName
  location: solutionLocation
  sku: {
    name: 'basic'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: 'default'
    publicNetworkAccess: 'enabled'
    networkRuleSet: {
      ipRules: []
    }
    encryptionWithCmk: {
      enforcement: 'Unspecified'
    }
    disableLocalAuth: true
    semanticSearch: 'free'
  }
  tags : tags
}

resource aiProject 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' =  if (empty(azureExistingAIProjectResourceId)) {
  parent: aiServices
  name: aiProjectName
  location: solutionLocation
  kind: 'AIServices'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {}
  tags : tags
}

resource aiproject_aisearch_connection_new 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = if (empty(azureExistingAIProjectResourceId)) {
  name: aiSearchConnectionName
  parent: aiProject
  properties: {
    category: 'CognitiveSearch'
    target: 'https://${aiSearchName}.search.windows.net'
    authType: 'AAD'
    isSharedToAll: true
    metadata: {
      ApiType: 'Azure'
      ResourceId: aiSearch.id
      location: aiSearch.location
    }
  }
}

module existing_AIProject_SearchConnectionModule 'deploy_aifp_aisearch_connection.bicep' = if (!empty(azureExistingAIProjectResourceId)) {
  name: 'aiProjectSearchConnectionDeployment'
  scope: resourceGroup(existingAIServiceSubscription, existingAIServiceResourceGroup)
  params: {
    existingAIProjectName: existingAIProjectName
    existingAIServicesName: existingAIServicesName
    aiSearchName: aiSearchName
    aiSearchResourceId: aiSearch.id
    aiSearchLocation: aiSearch.location
    aiSearchConnectionName: aiSearchConnectionName
  }
}

resource aiUser 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '53ca6127-db72-4b80-b1b0-d745d6d5456d'
}


resource assignFoundryRoleToMI 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (empty(azureExistingAIProjectResourceId))  {
  name: guid(resourceGroup().id, aiServices.id, aiUser.id)
  scope: aiServices
  properties: {
    principalId: managedIdentityObjectId
    roleDefinitionId: aiUser.id
    principalType: 'ServicePrincipal'
  }
}
module assignFoundryRoleToMIExisting 'deploy_foundry_role_assignment.bicep' = if (!empty(azureExistingAIProjectResourceId)) {
  name: 'assignFoundryRoleToMI'
  scope: resourceGroup(existingAIServiceSubscription, existingAIServiceResourceGroup)
  params: {
    roleDefinitionId: aiUser.id
    roleAssignmentName: guid(resourceGroup().id, managedIdentityObjectId, aiUser.id, 'foundry')
    aiServicesName: existingAIServicesName
    aiProjectName: existingAIProjectName
    principalId: managedIdentityObjectId
    aiLocation: existing_aiServicesModule.outputs.location
    aiKind: existing_aiServicesModule.outputs.kind
    aiSkuName: existing_aiServicesModule.outputs.skuName
    customSubDomainName: existing_aiServicesModule.outputs.customSubDomainName
    publicNetworkAccess: existing_aiServicesModule.outputs.publicNetworkAccess
    enableSystemAssignedIdentity: true
    defaultNetworkAction: existing_aiServicesModule.outputs.defaultNetworkAction
    vnetRules: existing_aiServicesModule.outputs.vnetRules
    ipRules: existing_aiServicesModule.outputs.ipRules
    aiModelDeployments: aiModelDeployments // Pass the model deployments to the module if model not already deployed
  }
}

resource assignAiUserToAiFoundryCU 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, aiServices_CU.id, aiUser.id)
  scope: aiServices_CU
  properties: {
    principalId: managedIdentityObjectId
    roleDefinitionId: aiUser.id
    principalType: 'ServicePrincipal'
  }
}

resource cognitiveServicesOpenAIUser 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
}

resource assignOpenAIRoleToAISearch 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (empty(azureExistingAIProjectResourceId))  {
  name: guid(resourceGroup().id, aiServices.id, cognitiveServicesOpenAIUser.id)
  scope: aiServices
  properties: {
    principalId: aiSearch.identity.principalId
    roleDefinitionId: cognitiveServicesOpenAIUser.id
    principalType: 'ServicePrincipal'
  }
}

module assignOpenAIRoleToAISearchExisting 'deploy_foundry_role_assignment.bicep' = if (!empty(azureExistingAIProjectResourceId)) {
  name: 'assignOpenAIRoleToAISearchExisting'
  scope: resourceGroup(existingAIServiceSubscription, existingAIServiceResourceGroup)
  params: {
    roleDefinitionId: cognitiveServicesOpenAIUser.id
    roleAssignmentName: guid(resourceGroup().id, aiSearch.id, cognitiveServicesOpenAIUser.id, 'openai-foundry')
    aiServicesName: existingAIServicesName
    aiProjectName: existingAIProjectName
    principalId: aiSearch.identity.principalId
    enableSystemAssignedIdentity: false
  }
}

resource searchIndexDataReader 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '1407120a-92aa-4202-b7e9-c0e197c71c8f'
}

resource assignSearchIndexDataReaderToAiProject 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (empty(azureExistingAIProjectResourceId)) {
  name: guid(resourceGroup().id, aiProject.id, searchIndexDataReader.id)
  scope: aiSearch
  properties: {
    principalId: aiProject.identity.principalId
    roleDefinitionId: searchIndexDataReader.id
    principalType: 'ServicePrincipal'
  }
}

resource assignSearchIndexDataReaderToExistingAiProject 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(azureExistingAIProjectResourceId)) {
  name: guid(resourceGroup().id, existingAIProjectName, searchIndexDataReader.id, 'Existing')
  scope: aiSearch
  properties: {
    principalId: assignOpenAIRoleToAISearchExisting.outputs.aiProjectPrincipalId
    roleDefinitionId: searchIndexDataReader.id
    principalType: 'ServicePrincipal'
  }
}

resource searchServiceContributor 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
}

resource assignSearchServiceContributorToAiProject 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (empty(azureExistingAIProjectResourceId)) {
  name: guid(resourceGroup().id, aiProject.id, searchServiceContributor.id)
  scope: aiSearch
  properties: {
    principalId: aiProject.identity.principalId
    roleDefinitionId: searchServiceContributor.id
    principalType: 'ServicePrincipal'
  }
}

resource assignSearchServiceContributorToExistingAiProject 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(azureExistingAIProjectResourceId)) {
  name: guid(resourceGroup().id, existingAIProjectName, searchServiceContributor.id, 'Existing')
  scope: aiSearch
  properties: {
    principalId: assignOpenAIRoleToAISearchExisting.outputs.aiProjectPrincipalId
    roleDefinitionId: searchServiceContributor.id
    principalType: 'ServicePrincipal'
  }
}

resource searchIndexDataContributor 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
}

resource assignSearchIndexDataContributorToMI 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, aiProject.id, searchIndexDataContributor.id)
  scope: aiSearch
  properties: {
    principalId: managedIdentityObjectId
    roleDefinitionId: searchIndexDataContributor.id
    principalType: 'ServicePrincipal'
  }
}

resource tenantIdEntry 'Microsoft.KeyVault/vaults/secrets@2021-11-01-preview' = {
  parent: keyVault
  name: 'TENANT-ID'
  properties: {
    value: subscription().tenantId
  }
  tags : tags
}

resource azureOpenAIInferenceEndpoint 'Microsoft.KeyVault/vaults/secrets@2021-11-01-preview' = {
  parent: keyVault
  name: 'AZURE-OPENAI-INFERENCE-ENDPOINT'
  properties: {
    value:''
  }
  tags : tags
}

resource azureOpenAIInferenceKey 'Microsoft.KeyVault/vaults/secrets@2021-11-01-preview' = {
  parent: keyVault
  name: 'AZURE-OPENAI-INFERENCE-KEY'
  properties: {
    value:''
  }
  tags : tags
}

resource azureOpenAIDeploymentModel 'Microsoft.KeyVault/vaults/secrets@2021-11-01-preview' = {
  parent: keyVault
  name: 'AZURE-OPENAI-DEPLOYMENT-MODEL'
  properties: {
    value: gptModelName
  }
  tags : tags
}

resource azureOpenAIApiVersionEntry 'Microsoft.KeyVault/vaults/secrets@2021-11-01-preview' = {
  parent: keyVault
  name: 'AZURE-OPENAI-PREVIEW-API-VERSION'
  properties: {
    value: azureOpenAIApiVersion  //'2024-02-15-preview'
  }
  tags : tags
}

resource azureOpenAIEndpointEntry 'Microsoft.KeyVault/vaults/secrets@2021-11-01-preview' = {
  parent: keyVault
  name: 'AZURE-OPENAI-ENDPOINT'
  properties: {
    value: !empty(existingOpenAIEndpoint) ? existingOpenAIEndpoint : aiServices.properties.endpoints['OpenAI Language Model Instance API'] //aiServices_m.properties.endpoint
  }
  tags : tags
}

resource azureOpenAIEmbeddingDeploymentModel 'Microsoft.KeyVault/vaults/secrets@2021-11-01-preview' = {
  parent: keyVault
  name: 'AZURE-OPENAI-EMBEDDING-MODEL'
  properties: {
    value: embeddingModel
  }
  tags : tags
}

resource azureOpenAICUEndpointEntry 'Microsoft.KeyVault/vaults/secrets@2021-11-01-preview' = {
  parent: keyVault
  name: 'AZURE-OPENAI-CU-ENDPOINT'
  properties: {
    value: aiServices_CU.properties.endpoints['OpenAI Language Model Instance API']
  }
  tags : tags
}

resource azureOpenAICUApiVersionEntry 'Microsoft.KeyVault/vaults/secrets@2021-11-01-preview' = {
  parent: keyVault
  name: 'AZURE-OPENAI-CU-VERSION'
  properties: {
    value: '?api-version=2024-12-01-preview'
  }
  tags : tags
}

resource azureSearchServiceEndpointEntry 'Microsoft.KeyVault/vaults/secrets@2021-11-01-preview' = {
  parent: keyVault
  name: 'AZURE-SEARCH-ENDPOINT'
  properties: {
    value: 'https://${aiSearch.name}.search.windows.net'
  }
  tags : tags
}

resource azureSearchServiceEntry 'Microsoft.KeyVault/vaults/secrets@2021-11-01-preview' = {
  parent: keyVault
  name: 'AZURE-SEARCH-SERVICE'
  properties: {
    value: aiSearch.name
  }
  tags : tags
}

resource azureSearchIndexEntry 'Microsoft.KeyVault/vaults/secrets@2021-11-01-preview' = {
  parent: keyVault
  name: 'AZURE-SEARCH-INDEX'
  properties: {
    value: 'transcripts_index'
  }
  tags : tags
}

resource cogServiceEndpointEntry 'Microsoft.KeyVault/vaults/secrets@2021-11-01-preview' = {
  parent: keyVault
  name: 'COG-SERVICES-ENDPOINT'
  properties: {
    value: !empty(existingOpenAIEndpoint) ? existingOpenAIEndpoint : aiServices.properties.endpoints['OpenAI Language Model Instance API']
  }
  tags : tags
}

resource cogServiceNameEntry 'Microsoft.KeyVault/vaults/secrets@2021-11-01-preview' = {
  parent: keyVault
  name: 'COG-SERVICES-NAME'
  properties: {
    value: aiServicesName
  }
  tags : tags
}

resource azureSubscriptionIdEntry 'Microsoft.KeyVault/vaults/secrets@2021-11-01-preview' = {
  parent: keyVault
  name: 'AZURE-SUBSCRIPTION-ID'
  properties: {
    value: subscription().subscriptionId
  }
  tags : tags
}

resource resourceGroupNameEntry 'Microsoft.KeyVault/vaults/secrets@2021-11-01-preview' = {
  parent: keyVault
  name: 'AZURE-RESOURCE-GROUP'
  properties: {
    value: resourceGroup().name
  }
  tags : tags
}

resource azureLocatioEntry 'Microsoft.KeyVault/vaults/secrets@2021-11-01-preview' = {
  parent: keyVault
  name: 'AZURE-LOCATION'
  properties: {
    value: solutionLocation
  }
  tags : tags
}

@description('Contains KeyVault Name')
output keyvaultName string = keyvaultName

@description('Contains KeyVault ID')
output keyvaultId string = keyVault.id

@description('Contains AI Services Target')
output aiServicesTarget string = !empty(existingOpenAIEndpoint) ? existingOpenAIEndpoint : aiServices.properties.endpoints['OpenAI Language Model Instance API'] //aiServices_m.properties.endpoint

@description('Contains AI Services Name')
output aiServicesName string = !empty(existingAIServicesName) ? existingAIServicesName : aiServicesName

@description('Contains Search Name')
output aiSearchName string = aiSearchName

@description('Contains Search ID')
output aiSearchId string = aiSearch.id

@description('Contains AI Search Target')
output aiSearchTarget string = 'https://${aiSearch.name}.search.windows.net'

@description('Contains AI Search Service Name')
output aiSearchService string = aiSearch.name

@description('Contains AI Project Name')
output aiProjectName string = !empty(existingAIProjectName) ? existingAIProjectName : aiProject.name

@description('Contains AI Search Connection Name')
output aiSearchConnectionName string = aiSearchConnectionName

@description('Contains Application Insights ID')
output applicationInsightsId string = applicationInsights.id

@description('Contains LogAnalytics Workspace Resource Name')
output logAnalyticsWorkspaceResourceName string = useExisting ? existingLogAnalyticsWorkspace.name : logAnalytics.name

@description('Contains LogAnalytics Workspace Resource Group')
output logAnalyticsWorkspaceResourceGroup string = useExisting ? existingLawResourceGroup : resourceGroup().name

@description('Contains LogAnalytics Workspace Subscription')
output logAnalyticsWorkspaceSubscription string = useExisting ? existingLawSubscription : subscription().subscriptionId

@description('Contains Project Endpoint')
output projectEndpoint string = !empty(existingProjEndpoint) ? existingProjEndpoint : aiProject.properties.endpoints['AI Foundry API']

@description('Contains Application Insights Connection String')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString
