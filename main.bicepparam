using './main.bicep'

param namePrefix = 'dronefleet'
param location = 'southcentralus'
param computeLocation = 'centralus'
param cosmosLocation = 'centralus'

// Application data traffic uses private endpoints in production. IoT Hub routing still
// uses each destination's deny-by-default public endpoint plus trusted-service access.
// serviceEndpoint is the lower-cost development option for application traffic.
param networkIsolation = 'privateEndpoint'

// Foundry account, project, gpt-4o, and gpt-realtime deployments.
param deployAiVision = true
param foundryLocation = 'eastus2'
param foundryGpt4oModelVersion = '2024-11-20'
param foundryRealtimeModelVersion = '2025-08-28'
param foundryModelCapacity = 10

// Create the two Entra app registrations first (see docs/DEPLOYMENT.md), then set the
// API application's client ID here. An empty value is safe for what-if only; the
// deployed backend deliberately rejects pilot authentication until configured.
param entraApiClientId = ''
param entraPublicClientId = ''
param entraRequiredScope = 'Drone.Provision'
param adminPilotIds = ''
param bootstrapAdminIdentities = ''
param primaryDeviceId = 'drone01RPI'
param aiGpuBaseUrl = ''

// South Central US supports T4 serverless GPUs, but this subscription must receive
// Managed Environment Consumption T4 GPU quota before these gates are enabled.
param deployGpuInfrastructure = false
param deployGpuApp = false
param gpuLocation = 'southcentralus'
param gpuImageRepository = 'ai-detection'
param gpuImageTag = 't4-v8'
