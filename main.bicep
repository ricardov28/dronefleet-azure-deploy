// =====================================================================================
// Dronefleet platform — end-to-end IaC (subscription-scope entry point).
//
// Stands up the ENTIRE drone platform in one resource group, secure-by-default:
// managed identity everywhere (no keys), private endpoints for data services,
// and app-settings wired to the created resources.
//
// Deploy:  az deployment sub create -l westus -f main.bicep -p main.bicepparam
//    or:   New-AzSubscriptionDeployment -Location westus -TemplateFile main.bicep -TemplateParameterFile main.bicepparam
//
// Layers (toggle each):
//   A Core telemetry+control   B Data/analytics   C Video (ACS)
//   D Cert handler (X.509)      E Control/front-end apps + Maps   F AI/vision
// =====================================================================================

targetScope = 'subscription'

@description('Short lowercase base name for all resources (e.g. dronefleet).')
@minLength(3)
@maxLength(12)
param namePrefix string = 'dronefleet'

@description('Primary Azure region.')
param location string = 'westus'

@description('Optional backend/Function compute region. Empty co-locates compute with the primary region.')
param computeLocation string = ''

@description('Optional Cosmos DB region. Empty co-locates Cosmos DB with the primary region.')
param cosmosLocation string = ''

@description('Optional seed to regenerate all globally-unique names. Change this (e.g. "v2") if you ever hit a "name already taken" clash; leave empty for stable, idempotent names.')
param uniqueSeed string = ''

@description('How application traffic reaches data services. privateEndpoint uses private IPs; serviceEndpoint uses subnet ACLs. IoT Hub routes use deny-by-default public endpoints with trusted-service exceptions in both modes.')
@allowed([
  'privateEndpoint'
  'serviceEndpoint'
])
param networkIsolation string = 'privateEndpoint'

@description('Layer F — AI / vision (OpenAI, vision, Logic App).')
param deployAiVision bool = true

@description('Microsoft Foundry region. East US 2 is the default because it supports both gpt-4o and gpt-realtime.')
param foundryLocation string = 'eastus2'

@description('Foundry gpt-4o model version.')
param foundryGpt4oModelVersion string = '2024-11-20'

@description('Foundry gpt-realtime model version.')
param foundryRealtimeModelVersion string = '2025-08-28'

@minValue(1)
@description('Usage-based capacity assigned to each Foundry model deployment.')
param foundryModelCapacity int = 10

@description('Application (client) ID of the Entra API registration that exposes Drone.Provision. Leave empty only for an initial infrastructure preview; authentication fails closed when deployed empty.')
param entraApiClientId string = ''

@description('Application (client) ID of the public client registration used by the browser and Android apps.')
param entraPublicClientId string = ''

@description('Delegated scope name required in pilot access tokens.')
param entraRequiredScope string = 'Drone.Provision'

@description('Comma-separated immutable pilot subject IDs with fleet-admin access.')
param adminPilotIds string = ''

@description('Comma-separated tenantId:userObjectId bootstrap administrators. Required by deployment tooling so a new tenant cannot be locked out.')
param bootstrapAdminIdentities string = ''

@description('Primary drone used by legacy single-device endpoints.')
param primaryDeviceId string = 'drone01RPI'

@description('Optional HTTPS endpoint of the GPU YOLO service.')
param aiGpuBaseUrl string = ''

@description('Creates the target ACR and South Central US GPU Container Apps environment. Requires Microsoft.App T4 quota.')
param deployGpuInfrastructure bool = false

@description('Creates the GPU detector app after its image has been imported into the target ACR.')
param deployGpuApp bool = false

@description('GPU Container Apps region. Empty uses the primary region.')
param gpuLocation string = ''

@description('Repository in the deployment-created ACR containing the detector image.')
param gpuImageRepository string = 'ai-detection'

@description('Detector image tag in the deployment-created ACR.')
param gpuImageTag string = 't4-v8'

@secure()
@description('Optional external writable Blob container URL used by ACS recording. Empty uses the deployment ADLS recordings container through ACS managed identity.')
param recordingDestinationContainerUrl string = ''

@secure()
@description('Optional shared key used by the external YOLO service. Supply through the deployment command, never commit it.')
param aiSharedKey string = ''

@description('Tags applied to every resource.')
param tags object = {
  workload: 'dronefleet'
  managedBy: 'bicep'
}

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-${namePrefix}'
  location: location
  tags: tags
}

module platform 'platform.bicep' = {
  scope: rg
  name: 'platform'
  params: {
    namePrefix: namePrefix
    location: location
    computeLocation: computeLocation
    cosmosLocation: cosmosLocation
    tags: tags
    uniqueSeed: uniqueSeed
    networkIsolation: networkIsolation
    deployAiVision: deployAiVision
    foundryLocation: foundryLocation
    foundryGpt4oModelVersion: foundryGpt4oModelVersion
    foundryRealtimeModelVersion: foundryRealtimeModelVersion
    foundryModelCapacity: foundryModelCapacity
    entraApiClientId: entraApiClientId
    entraPublicClientId: entraPublicClientId
    entraRequiredScope: entraRequiredScope
    adminPilotIds: adminPilotIds
    bootstrapAdminIdentities: bootstrapAdminIdentities
    primaryDeviceId: primaryDeviceId
    aiGpuBaseUrl: aiGpuBaseUrl
    deployGpuInfrastructure: deployGpuInfrastructure
    deployGpuApp: deployGpuApp
    gpuLocation: gpuLocation
    gpuImageRepository: gpuImageRepository
    gpuImageTag: gpuImageTag
    recordingDestinationContainerUrl: recordingDestinationContainerUrl
    aiSharedKey: aiSharedKey
  }
}

output resourceGroupName string = rg.name
output backendAppName string = platform.outputs.backendAppName
output backendUrl string = platform.outputs.backendUrl
output forwarderFunctionName string = platform.outputs.forwarderFunctionName
output keyVaultName string = platform.outputs.keyVaultName
output iotHubName string = platform.outputs.iotHubName
output webPubSubName string = platform.outputs.webPubSubName
output cosmosName string = platform.outputs.cosmosName
output storageAccountName string = platform.outputs.adlsName
output acsName string = platform.outputs.acsName
output foundryName string = platform.outputs.foundryName
output foundryProjectId string = platform.outputs.foundryProjectId
output gpuRegistryName string = platform.outputs.gpuRegistryName
output gpuEnvironmentId string = platform.outputs.gpuEnvironmentId
output gpuAppName string = platform.outputs.gpuAppName
output gpuBaseUrl string = platform.outputs.gpuBaseUrl
