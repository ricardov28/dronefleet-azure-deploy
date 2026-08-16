# Dronefleet Azure deployment

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fricardov28%2Fdronefleet-azure-deploy%2Fv1.1.0%2Fazuredeploy.json)

The button opens a subscription-scope Azure Portal deployment using the
versioned `v1.1.0` template. Before using it, run the one-time Entra bootstrap
described below and enter its two client IDs plus your
`tenantId:userObjectId` bootstrap administrator in the portal form.

This repository recreates the core Dronefleet cloud backend in a new Azure subscription and tenant. It contains subscription-scope Bicep, the IoT Hub telemetry forwarder, Entra bootstrap automation, deployment scripts, and operational documentation.

The deployment is preview-first: scripts do not change Azure or Entra unless `-Apply` is supplied.

## What it deploys

- One resource group, VNet, delegated subnets, private DNS, and optional private endpoints
- User-assigned managed identity and least-privilege data-plane roles
- Key Vault with RBAC, soft delete, and purge protection
- Log Analytics and Application Insights
- IoT Hub with identity-based routes to:
  - ADLS for raw telemetry archival
  - a custom Event Hub for the telemetry forwarder and analytics consumers
- The telemetry Function persists `flightSummary` messages to private Cosmos DB
- Web PubSub hub `dronefleet`
- Dedicated Linux Function on the shared P0v3 plan plus source code for custom Event Hub to Web PubSub forwarding
- Cosmos DB database `droneOps` and all application containers
- ADLS containers for analytics, snapshots, recordings, and raw IoT telemetry
- Linux App Service plan and the combined Node/Express backend
- Azure Communication Services and Azure Maps
- ACS system identity with write access to the ADLS `recordings` container
- Post-code Event Grid subscription for recording-file status notifications
- Microsoft Foundry account/project with `gpt-5.1` snapshot analysis and `gpt-realtime` voice deployments
- Optional quota-gated T4 serverless GPU Container App and target ACR

Service credentials still required by the current Node SDK code are generated during deployment, stored in Key Vault, and injected through App Service Key Vault references. Cosmos and storage use managed identity.

## What remains separate

- Entra application registrations are created by [`scripts/bootstrap-entra.ps1`](scripts/bootstrap-entra.ps1), not ARM.
- The combined backend source currently lives in the adjacent application repository and is packaged by [`scripts/deploy-code.ps1`](scripts/deploy-code.ps1).
- Android APKs must be rebuilt with the new backend URL and Entra IDs.
- Drone IoT identities, pilot assignments, and bootstrap administrators are environment data, not reusable infrastructure.
- The GPU detector is Bicep-managed but deployed in two stages: create ACR/environment, build or import the versioned image with [`scripts/import-gpu-image.ps1`](scripts/import-gpu-image.ps1), then enable the app. South Central US T4 quota is required.

## Start here

1. Read [Project architecture](docs/PROJECT.md).
2. Follow [New-tenant deployment](docs/DEPLOYMENT.md).
3. Run local validation:

```powershell
./scripts/validate.ps1
```

4. Preview infrastructure before applying:

```powershell
./scripts/deploy.ps1 `
  -SubscriptionId '<subscription-id>' `
  -TenantId '<tenant-id>' `
  -EntraApiClientId '<api-client-id>' `
  -EntraPublicClientId '<public-client-id>' `
  -BootstrapAdminIdentities '<tenant-id>:<user-object-id>'
```

The script runs Bicep validation and `az deployment sub what-if`; without `-Apply`, it stops there.

Every environment must pass at least one bootstrap administrator as
`<tenant-id>:<user-object-id>`. The deployment creates no pilot assignment
documents. After signing in, that administrator assigns pilots to drones through
the admin UI/API as the fleet is onboarded.

## Deploy from GitHub

1. Sign in to the target tenant with Azure CLI.
2. Run [`scripts/bootstrap-entra.ps1`](scripts/bootstrap-entra.ps1) with
  `-Apply`; it creates or reuses the two Entra registrations and prints their
  client IDs.
3. Select **Deploy to Azure** above, choose the subscription and regions, and
  enter the client IDs and bootstrap administrator identity.
4. Leave `deployGpuInfrastructure` and `deployGpuApp` off unless the selected
  region has approved **Managed Environment Consumption T4 GPUs** quota and
  the detector image has been published to the deployment-created ACR.
5. After infrastructure succeeds, publish the backend/Function code and rerun
  the Entra bootstrap with the deployed backend URL.

Azure Portal deploys the committed, self-contained ARM JSON file. GitHub Actions
verifies that it still matches [`main.bicep`](main.bicep) on every change. New
versions use a new Git tag so existing deployment links remain immutable.

## Repository layout

```text
main.bicep                 Subscription entry point and resource-group creation
main.bicepparam            Environment defaults; contains no secrets
postdeploy.bicep           ACS Event Grid webhook subscription, applied after code
platform.bicep             Resource-group orchestration and backend settings
modules/                   Reusable Azure resource modules
apps/forwarder/            Deployable Node v4 telemetry Function
scripts/bootstrap-entra.ps1  Idempotent Entra registration bootstrap
scripts/validate.ps1         Bicep and forwarder validation
scripts/deploy.ps1           What-if-first infrastructure deployment
scripts/deploy-code.ps1      Combined backend and Function deployment
scripts/import-gpu-image.ps1 Secure registry-to-registry detector image import
docs/PROJECT.md            Architecture and service ownership
docs/DEPLOYMENT.md         New-tenant deployment and recovery runbook
```

## Security model

- No secrets belong in `main.bicepparam`, source control, or Android builds.
- Key Vault references provide ACS, IoT Hub service, Web PubSub, Maps, recording, and optional detector credentials to App Service.
- App Service, Function, Cosmos, storage, Event Hubs, and Web PubSub use managed identity where supported by the current code/SDK.
- Foundry local authentication is disabled. Backend inference uses managed identity; browser Voice Live uses a short-lived Entra token.
- The GPU app uses managed identity for ACR pull and Key Vault secret resolution. Its public HTTPS ingress accepts the existing shared-key service contract and scales to zero.
- Pilot API authentication fails closed when the Entra API client ID is missing.
- IoT Hub remains public for field devices but uses per-device credentials or X.509 identities.
- `privateEndpoint` is the production default for application data access; `serviceEndpoint` is the lower-cost development option.
- The backend App Service plan defaults to Premium v3 P0v3 because some new subscriptions have zero Basic/Standard worker quota. Confirm regional quota and pricing before each deployment.
- IoT Hub routing cannot use destination private endpoints. ADLS and Event Hubs retain deny-by-default public endpoints with trusted Microsoft service exceptions and system-identity RBAC for the hub. Cosmos stays private; the VNet-integrated telemetry Function persists flight summaries through managed identity.
