param name string
param projectName string
param location string
param privateEndpointLocation string
param tags object
param identityId string
param identityPrincipalId string
param peSubnetId string
param dnsZoneIds array = []
param networkIsolation string = 'privateEndpoint'
param gpt4oDeploymentName string = 'gpt-4o'
param gpt4oModelVersion string = '2024-11-20'
param gpt4oSkuName string = 'GlobalStandard'
param gpt4oCapacity int = 10
param realtimeDeploymentName string = 'gpt-realtime'
param realtimeModelVersion string = '2025-08-28'
param realtimeSkuName string = 'GlobalStandard'
param realtimeCapacity int = 10

var usePrivateEndpoints = networkIsolation == 'privateEndpoint'

resource account 'Microsoft.CognitiveServices/accounts@2026-05-01' = {
  name: name
  location: location
  tags: tags
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  properties: {
    allowProjectManagement: true
    customSubDomainName: name
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
      ipRules: []
      virtualNetworkRules: []
    }
  }
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2026-05-01' = {
  parent: account
  name: projectName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  properties: {
    displayName: projectName
    description: 'Dronefleet vision and real-time voice project'
  }
}

resource gpt4o 'Microsoft.CognitiveServices/accounts/deployments@2026-05-01' = {
  parent: account
  name: gpt4oDeploymentName
  sku: {
    name: gpt4oSkuName
    capacity: gpt4oCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4o'
      version: gpt4oModelVersion
    }
    versionUpgradeOption: 'NoAutoUpgrade'
  }
  dependsOn: [
    project
  ]
}

resource realtime 'Microsoft.CognitiveServices/accounts/deployments@2026-05-01' = {
  parent: account
  name: realtimeDeploymentName
  sku: {
    name: realtimeSkuName
    capacity: realtimeCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-realtime'
      version: realtimeModelVersion
    }
    versionUpgradeOption: 'NoAutoUpgrade'
  }
  dependsOn: [
    gpt4o
  ]
}

var invocationRoleIds = [
  '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd' // Cognitive Services OpenAI User
  'a97b65f3-24c7-4388-baec-2e87135dc908' // Cognitive Services User
  '53ca6127-db72-4b80-b1b0-d745d6d5456d' // Foundry User
]

resource invocationRoles 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for roleId in invocationRoleIds: {
  name: guid(account.id, identityPrincipalId, roleId)
  scope: account
  properties: {
    principalId: identityPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleId)
    principalType: 'ServicePrincipal'
  }
}]

module privateEndpoint 'privateEndpoint.bicep' = if (usePrivateEndpoints) {
  name: 'pe-${name}'
  params: {
    name: 'pe-${name}'
    location: privateEndpointLocation
    tags: tags
    peSubnetId: peSubnetId
    serviceId: account.id
    groupIds: [
      'account'
    ]
    dnsZoneIds: dnsZoneIds
  }
}

output id string = account.id
output name string = account.name
output projectId string = project.id
output foundryEndpoint string = 'https://${account.name}.services.ai.azure.com'
output voiceLiveEndpoint string = 'https://${account.name}.cognitiveservices.azure.com'
output gpt4oDeploymentName string = gpt4o.name
output realtimeDeploymentName string = realtime.name
