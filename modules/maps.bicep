// Azure Maps account (Gen2) for the browser map.
param name string
param tags object
param keyVaultName string

resource maps 'Microsoft.Maps/accounts@2023-06-01' = {
  name: name
  location: 'global'
  tags: tags
  sku: {
    name: 'G2'
  }
  kind: 'Gen2'
  properties: {
    disableLocalAuth: false
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' existing = {
  name: keyVaultName
}

resource subscriptionKeySecret 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = {
  parent: keyVault
  name: 'azure-maps-subscription-key'
  properties: {
    value: maps.listKeys().primaryKey
  }
}

output id string = maps.id
output name string = maps.name
output clientId string = maps.properties.uniqueId
