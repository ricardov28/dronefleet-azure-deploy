[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SubscriptionId,
    [Parameter(Mandatory)][string]$DeploymentName,
    [Parameter(Mandatory)][string]$BackendSourcePath,
    [switch]$SkipBackendTests,
    [switch]$SkipBackendDeploy
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-Checked {
    param([Parameter(Mandatory)][string]$Command, [Parameter(Mandatory)][string[]]$Arguments)
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $Command @Arguments)
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousPreference }
    if ($exitCode -ne 0) { throw "$Command failed with exit code $exitCode." }
    return $output
}

function Copy-TreeWithoutLocalArtifacts {
    param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Destination)
    $excludedDirectories = @('node_modules', '.git', '.vscode', 'test', 'coverage')
    $excludedFiles = @('.env')
    Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
        if ($_.PSIsContainer -and $excludedDirectories -contains $_.Name) { return }
        if (-not $_.PSIsContainer -and ($excludedFiles -contains $_.Name -or $_.Extension -eq '.log')) { return }
        $target = Join-Path $Destination $_.Name
        if ($_.PSIsContainer) {
            New-Item -ItemType Directory -Path $target -Force | Out-Null
            Copy-TreeWithoutLocalArtifacts -Source $_.FullName -Destination $target
        } else {
            Copy-Item -LiteralPath $_.FullName -Destination $target -Force
        }
    }
}

function Copy-NodePackageClosure {
    param(
        [Parameter(Mandatory)][string]$PackageName,
        [Parameter(Mandatory)][string]$SourceNodeModules,
        [Parameter(Mandatory)][string]$DestinationNodeModules,
        [Parameter(Mandatory)][hashtable]$Visited
    )
    if ($Visited.ContainsKey($PackageName)) { return }
    $Visited[$PackageName] = $true

    $source = Join-Path $SourceNodeModules $PackageName
    $manifestPath = Join-Path $source 'package.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Required Function runtime package is missing: $PackageName"
    }

    $destination = Join-Path $DestinationNodeModules $PackageName
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Recurse -Force

    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($manifest.PSObject.Properties['dependencies'] -and $manifest.dependencies) {
        $dependencyNames = @($manifest.dependencies.PSObject.Properties | ForEach-Object { $_.Name })
        foreach ($dependency in $dependencyNames) {
            Copy-NodePackageClosure -PackageName $dependency `
                -SourceNodeModules $SourceNodeModules `
                -DestinationNodeModules $DestinationNodeModules `
                -Visited $Visited
        }
    }
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw 'Azure CLI is required.' }
if (-not (Get-Command func -ErrorAction SilentlyContinue)) { throw 'Azure Functions Core Tools is required for the telemetry forwarder deployment.' }
if (-not (Test-Path -LiteralPath $BackendSourcePath -PathType Container)) { throw "Backend source path not found: $BackendSourcePath" }
foreach ($required in @('package.json', 'package-lock.json', 'backend/server.js', 'frontend/index.html')) {
    if (-not (Test-Path -LiteralPath (Join-Path $BackendSourcePath $required))) { throw "Backend source is missing $required" }
}

Invoke-Checked -Command az -Arguments @('account', 'set', '--subscription', $SubscriptionId) | Out-Null
$outputsJson = Invoke-Checked -Command az -Arguments @('deployment', 'sub', 'show', '--name', $DeploymentName, '--query', 'properties.outputs', '--output', 'json', '--only-show-errors')
$outputs = ($outputsJson -join "`n") | ConvertFrom-Json
$resourceGroup = $outputs.resourceGroupName.value
$backendApp = $outputs.backendAppName.value
$backendUrl = $outputs.backendUrl.value
$forwarderFunction = $outputs.forwarderFunctionName.value
$acsName = $outputs.acsName.value

if (-not $SkipBackendTests) {
    Push-Location $BackendSourcePath
    try { Invoke-Checked -Command npm -Arguments @('test') }
    finally { Pop-Location }
}

$artifactRoot = Join-Path ([IO.Path]::GetTempPath()) "dronefleet-deploy-$([guid]::NewGuid().ToString('N'))"
$backendStage = Join-Path $artifactRoot 'backend'
$backendZip = Join-Path $artifactRoot 'backend.zip'
New-Item -ItemType Directory -Path $backendStage -Force | Out-Null
try {
    $webpackCommand = Join-Path $BackendSourcePath 'backend/node_modules/.bin/webpack.cmd'
    if (-not (Test-Path -LiteralPath $webpackCommand -PathType Leaf)) {
        throw "Backend Webpack CLI not found: $webpackCommand"
    }
    if (-not $SkipBackendDeploy) {
    foreach ($name in @('package.json', 'package-lock.json')) {
        $source = Join-Path $BackendSourcePath $name
        if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination $backendStage -Force }
    }
    $frontendStage = Join-Path $backendStage 'frontend'
    New-Item -ItemType Directory -Path $frontendStage -Force | Out-Null
    Copy-TreeWithoutLocalArtifacts -Source (Join-Path $BackendSourcePath 'frontend') -Destination $frontendStage

    $bundleStage = Join-Path $backendStage 'backend'
    New-Item -ItemType Directory -Path $bundleStage -Force | Out-Null
    $previousEntry = $env:DRONEFLEET_BACKEND_ENTRY
    $previousOutput = $env:DRONEFLEET_BACKEND_OUTPUT
    try {
        $env:DRONEFLEET_BACKEND_ENTRY = Join-Path $BackendSourcePath 'backend/server.js'
        $env:DRONEFLEET_BACKEND_OUTPUT = $bundleStage
        Invoke-Checked -Command $webpackCommand -Arguments @(
            '--config', (Join-Path $PSScriptRoot 'webpack-backend.cjs'), '--stats=errors-warnings'
        )
    }
    finally {
        $env:DRONEFLEET_BACKEND_ENTRY = $previousEntry
        $env:DRONEFLEET_BACKEND_OUTPUT = $previousOutput
    }
    Invoke-Checked -Command node -Arguments @('--check', (Join-Path $bundleStage 'server.js')) | Out-Null
    Compress-Archive -Path (Join-Path $backendStage '*') -DestinationPath $backendZip -CompressionLevel Optimal

    Write-Host "Deploying combined backend to $backendApp..." -ForegroundColor Cyan
    Invoke-Checked -Command az -Arguments @(
        'webapp', 'config', 'appsettings', 'set', '--resource-group', $resourceGroup, '--name', $backendApp,
        '--settings', 'SCM_DO_BUILD_DURING_DEPLOYMENT=false', '--only-show-errors'
    ) | Out-Null
    Invoke-Checked -Command az -Arguments @(
        'webapp', 'deploy', '--resource-group', $resourceGroup, '--name', $backendApp,
        '--src-path', $backendZip, '--type', 'zip', '--clean', 'true', '--restart', 'true',
        '--ignore-stack', 'true', '--track-status', 'false', '--timeout', '7200000', '--only-show-errors'
    )
    }

    $forwarderPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'apps/forwarder'
    Push-Location $forwarderPath
    try {
        Invoke-Checked -Command npm -Arguments @('test')
    }
    finally { Pop-Location }

    $forwarderStage = Join-Path $artifactRoot 'forwarder'
    $forwarderSourceStage = Join-Path $forwarderStage 'src'
    New-Item -ItemType Directory -Path $forwarderSourceStage -Force | Out-Null
    foreach ($name in @('host.json', 'package.json', 'package-lock.json')) {
        Copy-Item -LiteralPath (Join-Path $forwarderPath $name) -Destination $forwarderStage -Force
    }
    $previousForwarderEntry = $env:DRONEFLEET_FORWARDER_ENTRY
    $previousForwarderOutput = $env:DRONEFLEET_FORWARDER_OUTPUT
    $previousForwarderModules = $env:DRONEFLEET_FORWARDER_MODULES
    try {
        $forwarderNodeModules = Join-Path $forwarderPath 'node_modules'
        $functionsPackage = Join-Path $forwarderNodeModules '@azure/functions/package.json'
        $fallbackNodeModules = $null
        if (-not (Test-Path -LiteralPath $functionsPackage -PathType Leaf)) {
            $reposRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $forwarderPath))
            $fallbackNodeModules = Get-ChildItem -LiteralPath $reposRoot -Directory | ForEach-Object {
                $candidate = Join-Path $_.FullName 'node_modules'
                if (Test-Path -LiteralPath (Join-Path $candidate '@azure/functions/package.json') -PathType Leaf) {
                    $candidate
                }
            } | Select-Object -First 1
        }
        if (-not (Test-Path -LiteralPath $functionsPackage -PathType Leaf) -and -not $fallbackNodeModules) {
            Push-Location $forwarderPath
            try {
                Invoke-Checked -Command npm -Arguments @(
                    'ci', '--ignore-scripts', '--prefer-offline',
                    '--fetch-retries=5', '--fetch-retry-mintimeout=2000', '--fetch-retry-maxtimeout=20000'
                )
            }
            finally { Pop-Location }
        }
        $functionsNodeModules = if (Test-Path -LiteralPath $functionsPackage -PathType Leaf) {
            $forwarderNodeModules
        } else {
            $fallbackNodeModules
        }
        $env:DRONEFLEET_FORWARDER_ENTRY = Join-Path $forwarderPath 'src/index.js'
        $env:DRONEFLEET_FORWARDER_OUTPUT = $forwarderSourceStage
        $env:DRONEFLEET_FORWARDER_MODULES = (@(
            $forwarderNodeModules,
            $fallbackNodeModules,
            (Join-Path $BackendSourcePath 'node_modules'),
            (Join-Path $BackendSourcePath 'backend/node_modules')
        ) | Where-Object { $_ }) -join [IO.Path]::PathSeparator
        Invoke-Checked -Command $webpackCommand -Arguments @(
            '--config', (Join-Path $PSScriptRoot 'webpack-forwarder.cjs'), '--stats=errors-warnings'
        )
    }
    finally {
        $env:DRONEFLEET_FORWARDER_ENTRY = $previousForwarderEntry
        $env:DRONEFLEET_FORWARDER_OUTPUT = $previousForwarderOutput
        $env:DRONEFLEET_FORWARDER_MODULES = $previousForwarderModules
    }
    Invoke-Checked -Command node -Arguments @('--check', (Join-Path $forwarderSourceStage 'index.js')) | Out-Null
    $forwarderRuntimeModules = Join-Path $forwarderStage 'node_modules'
    Copy-NodePackageClosure -PackageName '@azure/functions' `
        -SourceNodeModules $functionsNodeModules `
        -DestinationNodeModules $forwarderRuntimeModules `
        -Visited @{}

    Push-Location $forwarderStage
    try {
        Write-Host "Deploying telemetry forwarder to $forwarderFunction..." -ForegroundColor Cyan
        Invoke-Checked -Command func -Arguments @(
            'azure', 'functionapp', 'publish', $forwarderFunction, '--javascript', '--no-build', '--force'
        )
    }
    finally { Pop-Location }

    Invoke-Checked -Command az -Arguments @(
        'functionapp', 'restart', '--resource-group', $resourceGroup, '--name', $forwarderFunction,
        '--only-show-errors'
    ) | Out-Null
    $syncUrl = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Web/sites/$forwarderFunction/syncfunctiontriggers?api-version=2022-03-01"
    Invoke-Checked -Command az -Arguments @(
        'rest', '--method', 'post', '--url', $syncUrl, '--only-show-errors'
    ) | Out-Null
    $registeredJson = Invoke-Checked -Command az -Arguments @(
        'functionapp', 'function', 'list', '--resource-group', $resourceGroup, '--name', $forwarderFunction,
        '--output', 'json', '--only-show-errors'
    )
    $registeredFunctions = @(($registeredJson -join "`n") | ConvertFrom-Json)
    if (-not ($registeredFunctions | Where-Object { $_.name -like '*/forwardIotHubToWebPubSub' })) {
        throw "Telemetry Function deployment completed, but forwardIotHubToWebPubSub is not registered."
    }

    Write-Host 'Probing backend runtime configuration...' -ForegroundColor Cyan
    $config = Invoke-RestMethod -Uri "$backendUrl/api/runtime-config" -Method Get -TimeoutSec 60
    if (-not $config.entraPublicClientId -or -not $config.entraApiScope) {
        throw 'Backend is reachable, but Entra runtime configuration is incomplete.'
    }
    Write-Host "Backend healthy: $backendUrl" -ForegroundColor Green

    $webhookEndpoint = "$($backendUrl.TrimEnd('/'))/filestatus"
    $validationCode = [guid]::NewGuid().ToString()
    $validationEvents = @(@{
        id = [guid]::NewGuid().ToString()
        eventType = 'Microsoft.EventGrid.SubscriptionValidationEvent'
        subject = ''
        eventTime = (Get-Date).ToUniversalTime().ToString('o')
        data = @{
            validationCode = $validationCode
            validationUrl = 'https://example.invalid/validation'
        }
        dataVersion = '1.0'
    })
    $validationBody = ConvertTo-Json -InputObject $validationEvents -Depth 5 -Compress
    $validationResponse = Invoke-RestMethod -Uri $webhookEndpoint -Method Post `
        -ContentType 'application/json' -Body $validationBody -TimeoutSec 60
    if ($validationResponse.validationResponse -ne $validationCode) {
        throw 'The /filestatus endpoint did not complete Event Grid webhook validation.'
    }

    $postdeployTemplate = Join-Path (Split-Path -Parent $PSScriptRoot) 'postdeploy.bicep'
    $postdeployName = "dronefleet-recording-events-$(Get-Date -Format 'yyyyMMddHHmmss')"
    $postdeployArgs = @(
        '--resource-group', $resourceGroup,
        '--template-file', $postdeployTemplate,
        '--parameters', "acsName=$acsName", "webhookEndpoint=$webhookEndpoint",
        '--only-show-errors'
    )
    Write-Host 'Previewing ACS recording Event Grid subscription...' -ForegroundColor Cyan
    Invoke-Checked -Command az -Arguments (@('deployment', 'group', 'what-if') + $postdeployArgs) | Out-Null
    Write-Host 'Deploying ACS recording Event Grid subscription...' -ForegroundColor Cyan
    Invoke-Checked -Command az -Arguments (@('deployment', 'group', 'create', '--name', $postdeployName) + $postdeployArgs) | Out-Null
}
finally {
    Remove-Item -LiteralPath $artifactRoot -Recurse -Force -ErrorAction SilentlyContinue
}
