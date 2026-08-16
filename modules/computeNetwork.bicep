param vnetName string
param location string
param tags object
param addressPrefix string = '10.41.0.0/16'
param appsSubnetPrefix string = '10.41.1.0/24'

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefix
      ]
    }
    subnets: [
      {
        name: 'snet-apps-integration'
        properties: {
          addressPrefix: appsSubnetPrefix
          delegations: [
            {
              name: 'appServicePlan'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
    ]
  }
}

output vnetId string = vnet.id
output vnetName string = vnet.name
output appsSubnetId string = '${vnet.id}/subnets/snet-apps-integration'
