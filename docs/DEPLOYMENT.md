# New-tenant deployment runbook

This runbook creates a separate Dronefleet environment in a new Entra tenant and Azure subscription. Commands are PowerShell and should be run from the repository root.

## 1. Prerequisites

Install and verify:

- PowerShell 7 or Windows PowerShell 5.1
- Azure CLI
- Node.js 22 and npm
- Azure Functions Core Tools 4
- Permission to create resource groups/resources and role assignments in the subscription
- Permission to create application registrations in the Entra tenant

```powershell
az version
func --version
node --version
az login --tenant '<tenant-id>'
az account set --subscription '<subscription-id>'
az account show --query '{tenantId:tenantId,subscription:id,user:user.name}'
```

Register resource providers if the subscription is new:

```powershell
@(
  'Microsoft.App',
  'Microsoft.Communication',
  'Microsoft.CognitiveServices',
  'Microsoft.DocumentDB',
  'Microsoft.Devices',
  'Microsoft.EventHub',
  'Microsoft.EventGrid',
  'Microsoft.Insights',
  'Microsoft.KeyVault',
  'Microsoft.ManagedIdentity',
  'Microsoft.Maps',
  'Microsoft.Network',
  'Microsoft.OperationalInsights',
  'Microsoft.SignalRService',
  'Microsoft.Storage',
  'Microsoft.Web'
) | ForEach-Object { az provider register --namespace $_ }
```

## 2. Create Entra registrations

Preview first:

```powershell
./scripts/bootstrap-entra.ps1 -TenantId '<tenant-id>'
```

Apply:

```powershell
./scripts/bootstrap-entra.ps1 -TenantId '<tenant-id>' -Apply
```

Save the emitted values:

```text
apiClientId
publicClientId
scope = api://<api-client-id>/Drone.Provision
```

The first pass configures localhost plus the Android signature-bound redirects. The cloud browser callback is added after Azure emits the backend hostname.

Resolve the first fleet administrator's immutable object ID in the destination
tenant. For the currently signed-in deployment operator:

```powershell
$adminObjectId = az ad signed-in-user show --query id -o tsv
$bootstrapAdmin = '<tenant-id>:' + $adminObjectId
```

Use the object ID, not an email address. At least one bootstrap administrator is
required by the deployment script.

## 3. Select parameters

Review `main.bicepparam`:

- `namePrefix`: 3-12 lowercase characters; determines resource names.
- `location`: primary region. This test deployment uses `southcentralus`; global services such as ACS and Maps remain global.
- `computeLocation`: optional backend/Function region. This test uses `centralus` because South Central App Service worker quota is unavailable.
- `cosmosLocation`: optional Cosmos DB region. This test uses `centralus` because the subscription cannot currently reserve South Central Cosmos capacity. Its private endpoint remains in the South Central VNet and is resolved from both peered VNets.
- `uniqueSeed`: change only for globally unique name conflicts.
- `networkIsolation`: `privateEndpoint` for production application traffic or `serviceEndpoint` for lower-cost development. IoT Hub routes always use firewall-restricted public destination endpoints with trusted-service exceptions.
- `deployAiVision`: creates a Microsoft Foundry account/project plus `gpt-4o` and `gpt-realtime` deployments in `foundryLocation` (East US 2 by default).
- `deployGpuInfrastructure`: creates the target ACR and T4 Container Apps environment after quota is approved.
- `deployGpuApp`: creates the detector app after its image is present in the target ACR. It requires `deployGpuInfrastructure` and `DRONEFLEET_AI_SHARED_KEY`.
- `gpuLocation`: defaults to South Central US. Microsoft Learn lists T4 support there, but the subscription must expose Managed Environment Consumption T4 GPU quota.
- `primaryDeviceId`: the legacy/default drone ID.
- The backend and telemetry Function share Premium v3 P0v3 by default. Confirm its regional quota and price; edit `modules/appServicePlan.bicep` only if the destination subscription supports a different production SKU.

Do not put secrets in `main.bicepparam`.

Optional overrides are read from process environment variables:

```powershell
$env:DRONEFLEET_RECORDING_DESTINATION_CONTAINER_URL = '<external-writable-recording-container-url>'
$env:DRONEFLEET_AI_SHARED_KEY = '<generated-long-random-value>'
```

When the recording override is unset, ACS writes to the deployment ADLS `recordings` container through managed identity. If an external URL is supplied, grant the deployed ACS system identity Storage Blob Data Contributor on that external account.

Foundry deploys with keys disabled. Its Private Endpoint is used by the backend, while Entra-secured public access remains enabled for the browser's direct Voice Live WebSocket.

After T4 quota is approved, stage GPU deployment:

```powershell
./scripts/deploy.ps1 @deployment -DeployGpuInfrastructure -Apply

./scripts/import-gpu-image.ps1 `
  -TargetSubscriptionId '<subscription-id>' `
  -TargetRegistryName '<gpuRegistryName deployment output>' `
  -SourcePath '<path-to-AI-container-source>'

$env:DRONEFLEET_AI_SHARED_KEY = '<generated-long-random-value>'
./scripts/deploy.ps1 @deployment -DeployGpuInfrastructure -DeployGpuApp -Apply
```

Run each `deploy.ps1` invocation without `-Apply` first and review what-if.
Omit `-SourcePath` to import the verified `ai-detection:t4-v8` image from the legacy ACR instead of rebuilding it. The source-build path is preferred for independent tenant reproduction.

## 4. Validate locally

```powershell
./scripts/validate.ps1
```

This compiles `main.bicep`, `main.bicepparam`, and `postdeploy.bicep`, validates the forwarder lock, runs its parsing tests, and loads its managed-identity startup configuration.

## 5. Preview Azure changes

The deploy script is preview-only unless `-Apply` is present:

```powershell
$deployment = @{
  SubscriptionId = '<subscription-id>'
  TenantId = '<tenant-id>'
  Location = 'southcentralus'
  ComputeLocation = 'centralus'
  CosmosLocation = 'centralus'
  FoundryLocation = 'eastus2'
  EntraApiClientId = '<api-client-id>'
  EntraPublicClientId = '<public-client-id>'
  BootstrapAdminIdentities = $bootstrapAdmin
  PrimaryDeviceId = 'drone01RPI'
}

./scripts/deploy.ps1 @deployment
```

Review the complete subscription-level what-if. Pay particular attention to deletions, SKU changes, role assignments, public-network settings, and global name replacements.

`AdminPilotIds` remains available only as an optional backward-compatible or
break-glass list of exact pilot IDs. A normal new-tenant deployment needs only
`BootstrapAdminIdentities`.

## 6. Deploy infrastructure and code

The current combined backend source is:

```text
C:\Users\ricar\OneDrive\repos\May2026 - JS preflight and video combinado\ACS raw - express - ADLS - rec
```

Deploy infrastructure, then package and publish both code artifacts:

```powershell
./scripts/deploy.ps1 @deployment `
  -Apply `
  -DeployCode `
  -BackendSourcePath 'C:\Users\ricar\OneDrive\repos\May2026 - JS preflight and video combinado\ACS raw - express - ADLS - rec'
```

The script always validates first and runs what-if before create unless `-SkipWhatIf` is explicitly supplied. Do not use `-SkipWhatIf` for normal deployments.

It writes deployment outputs under `.deployment/` and prints:

- deployment name
- resource group
- actual stamped backend URL
- App Service name
- Function name
- Key Vault, IoT Hub, Web PubSub, Cosmos, and storage names

To publish code again without changing infrastructure:

```powershell
./scripts/deploy-code.ps1 `
  -SubscriptionId '<subscription-id>' `
  -DeploymentName '<deployment-name>' `
  -BackendSourcePath 'C:\Users\ricar\OneDrive\repos\May2026 - JS preflight and video combinado\ACS raw - express - ADLS - rec'
```

The backend archive excludes `.env`, logs, tests, local editor metadata, and the raw dependency tree. After tests pass, the deployment script uses the backend-local Webpack 5 toolchain to create a Node-targeted server bundle, validates its syntax, and packages that compact bundle with the frontend. Remote Oryx builds are disabled, producing a deterministic ZipDeploy artifact without a large `node_modules` copy.

The telemetry Function is also compiled into a compact Node bundle after its tests pass. Core Tools publishes the staged `host.json`, package metadata, and bundled source with `--no-build`; `@azure/functions-core` remains external because the Functions worker supplies it at runtime.

After code is healthy, `deploy-code.ps1` sends a harmless Event Grid validation event to `/filestatus`, previews `postdeploy.bicep`, and creates the ACS `RecordingFileStatusUpdated` subscription. This ordering is required because Event Grid validates a webhook when the subscription is created.

## 7. Add the cloud Entra callback

Rerun the bootstrap with the exact `backendUrl` deployment output:

```powershell
./scripts/bootstrap-entra.ps1 `
  -TenantId '<tenant-id>' `
  -BackendUrl 'https://<actual-stamped-hostname>' `
  -Apply
```

The backend exposes public runtime auth configuration at `/api/runtime-config`; the browser no longer depends on hardcoded production tenant IDs.

## 8. Rebuild Android applications

Azure infrastructure cannot rewrite installed APKs. Update production build constants in:

- `AndroidPilot/app/build.gradle.kts`
- `androidDrone/androidApp/build.gradle.kts`

Set:

```text
API_BASE_URL or DRONE_API_BASE_URL = <backendUrl output>
ENTRA_CLIENT_ID = <publicClientId>
ENTRA_API_SCOPE = api://<apiClientId>/Drone.Provision
```

Keep the existing package names and signing key. The Entra Android redirect URIs are signature-bound to those values. Build, sign, distribute, and reinstall/update the APKs using the normal Android release process.

## 9. Provision environment data

Infrastructure deployment intentionally does not clone tenant data.

It also creates no `pilotAssignments` documents. The bootstrap administrator is
authorized from the deployment setting and has fleet-wide admin access without a
drone assignment.

1. Create or enroll each IoT Hub device identity.
2. Install device certificates/credentials on the matching drone agent.
3. Sign in as the bootstrap administrator.
4. Create pilot-to-drone assignments in the admin UI/API.
5. Create installation enrollment bundles for Android drone phones as needed.
6. Verify every device is disarmed before testing control.

## 10. Verification checklist

### Azure resources

```powershell
az resource list --resource-group 'rg-<namePrefix>' --query '[].{name:name,type:type}' -o table
```

Confirm:

- Key Vault references resolve in App Service configuration.
- ACS has a system-assigned identity with Storage Blob Data Contributor on ADLS.
- App Service `RECORDING_DESTINATION_CONTAINER_URL` points to the generated `recordings` container unless explicitly overridden.
- Event Grid subscription `acs-recording-file-status` targets the backend `/filestatus` endpoint and filters on `Microsoft.Communication.RecordingFileStatusUpdated`.
- Cosmos local auth is disabled and all nine containers exist.
- ADLS shared-key access is disabled and all four containers exist.
- IoT Hub routes are enabled for built-in telemetry, ADLS archive, and Event Hubs.
- IoT Hub routes telemetry to the custom private Event Hub by system identity; the Function consumes its `analytics` group by managed identity and persists `flightSummary` messages to the private Cosmos `flights` container. The IoT Hub built-in endpoint is not used because it does not support Entra authentication for message consumption.
- IoT Hub uses its system-assigned identity for route destinations; endpoint health reports healthy after test telemetry.
- Storage and Event Hubs have deny-by-default public firewalls with trusted Microsoft services enabled. Cosmos remains private/subnet-restricted and is reached by the VNet-integrated Function and App Service.
- Function app is running and has `forwardIotHubToWebPubSub` registered.
- App Service returns `/api/runtime-config` with the new public client ID and API scope.

### Safe application smoke test

1. Sign into the browser and AndroidPilot.
2. Confirm assigned drones list correctly.
3. Keep aircraft disarmed.
4. Confirm telemetry reaches `attitude-<deviceId>`.
5. Claim/release calibration and flight without starting motors.
6. Verify ACS video only when a drone is presenting.
7. Verify ARM remains disabled without fresh telemetry.
8. Verify snapshots/recording only with live video and configured storage.

### Logs

```powershell
az webapp log tail --resource-group 'rg-<namePrefix>' --name '<backend-app-name>'
func azure functionapp logstream '<forwarder-function-name>'
```

## Updating an existing environment

1. Modify Bicep or code.
2. Run `./scripts/validate.ps1`.
3. Run `./scripts/deploy.ps1 @deployment` and review what-if.
4. Run again with `-Apply` only after review.
5. Publish code with `deploy-code.ps1` or `-DeployCode`.
6. Run the safe smoke test.

Bicep deployments are idempotent when `namePrefix`, subscription, resource group, and `uniqueSeed` are unchanged.

## GitHub Actions setup

Infrastructure pushes compile Bicep only. Manual workflow runs perform what-if, and deploy only when the `apply` input is checked.

Configure repository secrets:

```text
AZURE_CLIENT_ID
AZURE_TENANT_ID
AZURE_SUBSCRIPTION_ID
```

Configure repository variables after running the Entra bootstrap:

```text
ENTRA_API_CLIENT_ID
ENTRA_PUBLIC_CLIENT_ID
ADMIN_PILOT_IDS                  optional
BOOTSTRAP_ADMIN_IDENTITIES       optional
DRONEFLEET_RESOURCE_GROUP        optional; defaults to rg-dronefleet
DRONEFLEET_NAME_PREFIX           optional; defaults to dronefleet
```

## Backup and disaster recovery

The templates recreate infrastructure, not data. Before a tenant migration or destructive recovery, export separately:

- Cosmos containers and pilot/device records
- required ADLS blobs and recordings
- IoT device identity/certificate inventory
- Entra pilot subject mapping
- Android signing key and release configuration
- external YOLO image digest/configuration if that workload is required

Restore data only after the destination schema and role assignments exist.

## Teardown

Preview deletion impact and ensure required data has been exported. The environment is grouped under one resource group:

```powershell
az group delete --name 'rg-<namePrefix>' --yes --no-wait
```

Resource-group deletion does not remove Entra app registrations. Delete those separately only when no environment or Android release still uses them. Key Vault purge protection intentionally prevents immediate permanent purge.
