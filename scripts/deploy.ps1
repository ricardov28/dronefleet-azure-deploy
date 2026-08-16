[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SubscriptionId,
    [Parameter(Mandatory)][string]$EntraApiClientId,
    [Parameter(Mandatory)][string]$EntraPublicClientId,
    [string]$TenantId = '',
    [string]$Location = 'westus',
    [string]$ComputeLocation = '',
    [string]$CosmosLocation = '',
    [string]$FoundryLocation = 'eastus2',
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$AdminIdentities,
    [string]$PrimaryDeviceId = 'drone01RPI',
    [string]$AiGpuBaseUrl = '',
    [switch]$DeployGpuInfrastructure,
    [switch]$DeployGpuApp,
    [string]$GpuLocation = 'southcentralus',
    [string]$GpuImageRepository = 'ai-detection',
    [string]$GpuImageTag = 't4-v8',
    [string]$BackendSourcePath = '',
    [switch]$Apply,
    [switch]$DeployCode,
    [switch]$SkipWhatIf
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Set-StrictMode -Version Latest

function Invoke-AzChecked {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& az @Arguments)
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousPreference }
    if ($exitCode -ne 0) {
        $safeArguments = $Arguments | ForEach-Object {
            if ($_ -match '^(aiSharedKey|recordingDestinationContainerUrl)=') {
                "$($Matches[1])=[REDACTED]"
            }
            else { $_ }
        }
        throw "Azure CLI failed: az $($safeArguments -join ' ')"
    }
    return $output
}

$root = Split-Path -Parent $PSScriptRoot
$template = Join-Path $root 'main.bicep'
$params = Join-Path $root 'main.bicepparam'
$name = "dronefleet-$(Get-Date -Format 'yyyyMMddHHmmss')"

if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw 'Azure CLI is required.' }
if ($DeployCode -and -not $Apply) { throw '-DeployCode requires -Apply.' }
if ($DeployCode -and -not $BackendSourcePath) { throw '-DeployCode requires -BackendSourcePath.' }
if ($AdminIdentities -notmatch '^[0-9a-fA-F-]{36}:[0-9a-fA-F-]{36}(\s*,\s*[0-9a-fA-F-]{36}:[0-9a-fA-F-]{36})*$') {
    throw '-AdminIdentities must contain one or more comma-separated tenantId:userObjectId values.'
}
if ($DeployGpuApp -and -not $DeployGpuInfrastructure) {
    throw '-DeployGpuApp requires -DeployGpuInfrastructure.'
}
if ($DeployGpuApp -and -not $env:DRONEFLEET_AI_SHARED_KEY) {
    throw '-DeployGpuApp requires DRONEFLEET_AI_SHARED_KEY.'
}

$accountJson = Invoke-AzChecked -Arguments @('account', 'show', '--output', 'json', '--only-show-errors')
$account = ($accountJson -join "`n") | ConvertFrom-Json
if ($TenantId -and $account.tenantId -ne $TenantId) {
    throw "Azure CLI is signed into tenant '$($account.tenantId)', not '$TenantId'."
}
Invoke-AzChecked -Arguments @('account', 'set', '--subscription', $SubscriptionId)

if ($DeployGpuInfrastructure) {
    $featureJson = Invoke-AzChecked -Arguments @(
        'feature', 'show',
        '--subscription', $SubscriptionId,
        '--namespace', 'Microsoft.Network',
        '--name', 'AllowBringYourOwnPublicIpAddress',
        '--output', 'json',
        '--only-show-errors'
    )
    $feature = ($featureJson -join "`n") | ConvertFrom-Json
    if ($feature.properties.state -ne 'Registered') {
        if (-not $Apply) {
            throw 'GPU infrastructure requires Microsoft.Network/AllowBringYourOwnPublicIpAddress. Register it or rerun this command with -Apply.'
        }
        Write-Host 'Registering the Container Apps VNet networking feature...' -ForegroundColor Cyan
        Invoke-AzChecked -Arguments @(
            'feature', 'register',
            '--subscription', $SubscriptionId,
            '--namespace', 'Microsoft.Network',
            '--name', 'AllowBringYourOwnPublicIpAddress',
            '--only-show-errors'
        ) | Out-Null
        Invoke-AzChecked -Arguments @(
            'provider', 'register',
            '--subscription', $SubscriptionId,
            '--namespace', 'Microsoft.Network',
            '--only-show-errors'
        ) | Out-Null
        $featureJson = Invoke-AzChecked -Arguments @(
            'feature', 'show',
            '--subscription', $SubscriptionId,
            '--namespace', 'Microsoft.Network',
            '--name', 'AllowBringYourOwnPublicIpAddress',
            '--output', 'json',
            '--only-show-errors'
        )
        $feature = ($featureJson -join "`n") | ConvertFrom-Json
        if ($feature.properties.state -ne 'Registered') {
            throw 'Azure accepted the networking feature registration but it is not active yet. Rerun after its state becomes Registered.'
        }
    }
}

& (Join-Path $PSScriptRoot 'validate.ps1')

$overrides = @(
    "location=$Location",
    "computeLocation=$ComputeLocation",
    "cosmosLocation=$CosmosLocation",
    "foundryLocation=$FoundryLocation",
    "entraApiClientId=$EntraApiClientId",
    "entraPublicClientId=$EntraPublicClientId",
    "adminIdentities=$AdminIdentities",
    "primaryDeviceId=$PrimaryDeviceId",
    "aiGpuBaseUrl=$AiGpuBaseUrl",
    "deployGpuInfrastructure=$($DeployGpuInfrastructure.IsPresent.ToString().ToLowerInvariant())",
    "deployGpuApp=$($DeployGpuApp.IsPresent.ToString().ToLowerInvariant())",
    "gpuLocation=$GpuLocation",
    "gpuImageRepository=$GpuImageRepository",
    "gpuImageTag=$GpuImageTag"
)
if ($env:DRONEFLEET_RECORDING_DESTINATION_CONTAINER_URL) {
    $overrides += "recordingDestinationContainerUrl=$($env:DRONEFLEET_RECORDING_DESTINATION_CONTAINER_URL)"
}
if ($env:DRONEFLEET_AI_SHARED_KEY) {
    $overrides += "aiSharedKey=$($env:DRONEFLEET_AI_SHARED_KEY)"
}

$deploymentArguments = @(
    '--location', $Location,
    '--template-file', $template,
    '--parameters', $params,
    '--parameters'
) + $overrides

if (-not $SkipWhatIf) {
    Write-Host 'Running subscription deployment what-if...' -ForegroundColor Cyan
    Invoke-AzChecked -Arguments (@('deployment', 'sub', 'what-if') + $deploymentArguments)
}

if (-not $Apply) {
    Write-Host 'Preview complete. No Azure resources were changed. Rerun with -Apply to deploy.' -ForegroundColor Yellow
    return
}

Write-Host "Deploying subscription template as '$name'..." -ForegroundColor Cyan
Invoke-AzChecked -Arguments (@('deployment', 'sub', 'create', '--name', $name) + $deploymentArguments)

$outputsJson = Invoke-AzChecked -Arguments @('deployment', 'sub', 'show', '--name', $name, '--query', 'properties.outputs', '--output', 'json', '--only-show-errors')
$outputDirectory = Join-Path $root '.deployment'
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$outputPath = Join-Path $outputDirectory "$name.outputs.json"
($outputsJson -join "`n") | Set-Content -LiteralPath $outputPath -Encoding utf8
$outputs = ($outputsJson -join "`n") | ConvertFrom-Json

Write-Host "Infrastructure deployed. Outputs: $outputPath" -ForegroundColor Green
Write-Host "Backend URL: $($outputs.backendUrl.value)"

if ($DeployCode) {
    & (Join-Path $PSScriptRoot 'deploy-code.ps1') `
        -SubscriptionId $SubscriptionId `
        -DeploymentName $name `
        -BackendSourcePath $BackendSourcePath
}

Write-Host "Deployment name: $name" -ForegroundColor Green
