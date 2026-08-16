// Shared Linux App Service plan for the platform's backend.
// Premium v3 provides VNet integration and is available in subscriptions where
// Basic/Standard worker quota starts at zero.
param name string
param location string
param tags object
param skuName string = 'P0v3'
param skuTier string = 'PremiumV3'

resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: skuTier
  }
  kind: 'linux'
  properties: {
    reserved: true
  }
}

output id string = plan.id
output name string = plan.name
