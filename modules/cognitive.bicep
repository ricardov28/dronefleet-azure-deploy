// Cognitive Services account (default OpenAI) with local auth off + MI data-plane role.
param name string
param location string
param tags object
param kind string = 'OpenAI'
param skuName string = 'S0'
param identityPrincipalId string

resource account 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: name
  location: location
  tags: tags
  kind: kind
  sku: {
    name: skuName
  }
  properties: {
    customSubDomainName: name
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: true
  }
}

// Cognitive Services OpenAI User for the platform MI.
resource role 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(account.id, identityPrincipalId, 'openai-user')
  scope: account
  properties: {
    principalId: identityPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd') // Cognitive Services OpenAI User
    principalType: 'ServicePrincipal'
  }
}

output id string = account.id
output name string = account.name
output endpoint string = account.properties.endpoint
