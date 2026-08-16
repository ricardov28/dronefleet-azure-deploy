param name string
param location string
param tags object
param identityPrincipalId string
param peSubnetId string
param vaultDnsZoneId string = ''
param networkIsolation string = 'privateEndpoint'
param allowedSubnetIds array = []

@secure()
@description('Optional external ACS recording destination container URL. Empty uses the deployment ADLS recordings container.')
param recordingDestinationContainerUrl string = ''

@secure()
@description('Optional shared key used by the external YOLO detector.')
param aiSharedKey string = ''

var usePrivateEndpoints = networkIsolation == 'privateEndpoint'

resource vault 'Microsoft.KeyVault/vaults@2024-11-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    tenantId: tenant().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enablePurgeProtection: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    publicNetworkAccess: usePrivateEndpoints ? 'Disabled' : 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      virtualNetworkRules: [for subnetId in (usePrivateEndpoints ? [] : allowedSubnetIds): {
        id: subnetId
        ignoreMissingVnetServiceEndpoint: false
      }]
    }
  }
}

resource secretsUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(vault.id, identityPrincipalId, 'key-vault-secrets-user')
  scope: vault
  properties: {
    principalId: identityPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
    principalType: 'ServicePrincipal'
  }
}

resource recordingDestinationSecret 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = if (!empty(recordingDestinationContainerUrl)) {
  parent: vault
  name: 'recording-destination-container-url'
  properties: {
    value: recordingDestinationContainerUrl
  }
}

resource aiSharedKeySecret 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = if (!empty(aiSharedKey)) {
  parent: vault
  name: 'ai-shared-key'
  properties: {
    value: aiSharedKey
  }
}

module privateEndpoint 'privateEndpoint.bicep' = if (usePrivateEndpoints) {
  name: 'pe-${name}'
  params: {
    name: 'pe-${name}'
    location: location
    tags: tags
    peSubnetId: peSubnetId
    serviceId: vault.id
    groupIds: [
      'vault'
    ]
    dnsZoneId: vaultDnsZoneId
  }
}

output id string = vault.id
output name string = vault.name
output uri string = vault.properties.vaultUri
