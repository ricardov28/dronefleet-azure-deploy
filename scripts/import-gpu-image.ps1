[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TargetSubscriptionId,
    [Parameter(Mandatory)][string]$TargetRegistryName,
    [string]$TargetResourceGroup = 'rg-dronefleet',
    [string]$SourceSubscriptionId = '',
    [string]$SourceResourceGroup = '',
    [string]$SourceRegistryName = '',
    [string]$Repository = 'ai-detection',
    [string]$Tag = 't4-v8',
    [string]$SourcePath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw 'Azure CLI is required.' }

$image = "${Repository}:${Tag}"

az account set --subscription $TargetSubscriptionId --only-show-errors
if ($LASTEXITCODE -ne 0) { throw 'Could not select the target subscription.' }

az acr show --name $TargetRegistryName --resource-group $TargetResourceGroup --only-show-errors --output none
if ($LASTEXITCODE -ne 0) { throw "Target registry '$TargetRegistryName' does not exist." }

if ($SourcePath) {
    $resolvedSource = (Resolve-Path -LiteralPath $SourcePath).Path
    if (-not (Test-Path -LiteralPath (Join-Path $resolvedSource 'Dockerfile'))) {
        throw "SourcePath '$resolvedSource' does not contain a Dockerfile."
    }
    $buildContext = Join-Path ([IO.Path]::GetTempPath()) "dronefleet-gpu-build-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $buildContext -Force | Out-Null
    try {
        foreach ($file in @('Dockerfile', 'requirements.txt', 'package.json', 'package-lock.json', 'webpack.config.js')) {
            Copy-Item -LiteralPath (Join-Path $resolvedSource $file) -Destination $buildContext
        }
        foreach ($directory in @('src', 'onnx', 'web')) {
            Copy-Item -LiteralPath (Join-Path $resolvedSource $directory) -Destination $buildContext -Recurse
        }
        az acr build `
            --registry $TargetRegistryName `
            --resource-group $TargetResourceGroup `
            --image $image `
            $buildContext `
            --only-show-errors
        if ($LASTEXITCODE -ne 0) { throw "Build of '$image' failed." }
    }
    finally {
        Remove-Item -LiteralPath $buildContext -Recurse -Force -ErrorAction SilentlyContinue
    }
}
else {
    if (-not $SourceSubscriptionId -or -not $SourceResourceGroup -or -not $SourceRegistryName) {
        throw 'Provide -SourcePath to build from source, or provide SourceSubscriptionId, SourceResourceGroup, and SourceRegistryName for an ACR import.'
    }
    $sourceRegistryId = "/subscriptions/$SourceSubscriptionId/resourceGroups/$SourceResourceGroup/providers/Microsoft.ContainerRegistry/registries/$SourceRegistryName"
    az acr import `
        --name $TargetRegistryName `
        --resource-group $TargetResourceGroup `
        --registry $sourceRegistryId `
        --source $image `
        --image $image `
        --force `
        --only-show-errors
    if ($LASTEXITCODE -ne 0) { throw "Import of '$image' failed." }
}

$digest = az acr repository show `
    --name $TargetRegistryName `
    --image $image `
    --query digest `
    --output tsv `
    --only-show-errors
if ($LASTEXITCODE -ne 0 -or -not $digest) { throw 'Imported image could not be verified.' }

Write-Host "Published and verified $image at digest $digest." -ForegroundColor Green