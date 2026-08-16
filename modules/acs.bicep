// Azure Communication Services — the ACS resource for video calling/rooms + recording.
// Global resource; data residency set by dataLocation.
param name string
param tags object
param keyVaultName string
param dataLocation string = 'United States'

resource acs 'Microsoft.Communication/communicationServices@2023-04-01' = {
  name: name
  location: 'global'
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dataLocation: dataLocation
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' existing = {
  name: keyVaultName
}

resource serviceConnectionSecret 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = {
  parent: keyVault
  name: 'acs-connection-string'
  properties: {
    value: acs.listKeys().primaryConnectionString
  }
}

output id string = acs.id
output name string = acs.name
output principalId string = acs.identity.principalId
