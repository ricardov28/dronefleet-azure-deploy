// User-assigned managed identity shared by the server-side compute (functions, web apps).
// Created FIRST so role assignments to data services exist BEFORE the apps boot
// (avoids the Flex Consumption chicken-and-egg where the host needs storage at startup).
param name string
param location string
param tags object

resource mi 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: name
  location: location
  tags: tags
}

output id string = mi.id
output principalId string = mi.properties.principalId
output clientId string = mi.properties.clientId
output name string = mi.name
