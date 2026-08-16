[CmdletBinding()]
param(
    [switch]$RestoreDependencies
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw 'Azure CLI is required.' }

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$Quiet,
        [switch]$AllowFailure
    )

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if ($Quiet) { & $Command @Arguments 2>&1 | Out-Null }
        else { & $Command @Arguments }
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    if (-not $AllowFailure -and $exitCode -ne 0) {
        throw "$Command failed with exit code $exitCode."
    }
    return $exitCode
}

$bicepVersionExit = Invoke-NativeCommand -Command az -Arguments @('bicep', 'version', '--only-show-errors') -Quiet -AllowFailure
if ($bicepVersionExit -ne 0) {
    Write-Host 'Installing the Azure CLI Bicep component...' -ForegroundColor Cyan
    Invoke-NativeCommand -Command az -Arguments @('bicep', 'install', '--only-show-errors') | Out-Null
}

Write-Host 'Compiling main.bicep...' -ForegroundColor Cyan
Invoke-NativeCommand -Command az -Arguments @('bicep', 'build', '--file', (Join-Path $root 'main.bicep'), '--stdout', '--only-show-errors') -Quiet | Out-Null

Write-Host 'Compiling main.bicepparam...' -ForegroundColor Cyan
Invoke-NativeCommand -Command az -Arguments @('bicep', 'build-params', '--file', (Join-Path $root 'main.bicepparam'), '--stdout', '--only-show-errors') -Quiet | Out-Null

Write-Host 'Compiling postdeploy.bicep...' -ForegroundColor Cyan
Invoke-NativeCommand -Command az -Arguments @('bicep', 'build', '--file', (Join-Path $root 'postdeploy.bicep'), '--stdout', '--only-show-errors') -Quiet | Out-Null

$forwarder = Join-Path $root 'apps/forwarder'
$validationRoot = $forwarder
$temporaryRoot = $null
if ($RestoreDependencies) {
    $temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) "dronefleet-forwarder-validation-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
    foreach ($file in @('host.json', 'package.json', 'package-lock.json')) {
        Copy-Item -LiteralPath (Join-Path $forwarder $file) -Destination $temporaryRoot
    }
    Copy-Item -LiteralPath (Join-Path $forwarder 'src') -Destination $temporaryRoot -Recurse
    Copy-Item -LiteralPath (Join-Path $forwarder 'test') -Destination $temporaryRoot -Recurse
    $validationRoot = $temporaryRoot
}

Push-Location $validationRoot
try {
    if (-not (Test-Path package-lock.json)) { throw 'apps/forwarder/package-lock.json is missing.' }
    node -e "const p=require('./package-lock.json'); if(!p.packages?.['']?.dependencies) process.exit(1)"
    if ($LASTEXITCODE -ne 0) { throw 'Forwarder package lock is invalid.' }
    if ($RestoreDependencies) {
        Invoke-NativeCommand -Command npm.cmd -Arguments @('ci', '--ignore-scripts') | Out-Null
    }
    Invoke-NativeCommand -Command npm.cmd -Arguments @('test') | Out-Null

    foreach ($source in @(
        'src/index.js',
        'src/functions/forwardIotHubToWebPubSub.js',
        'src/lib/cosmosWriter.js',
        'src/lib/parseTelemetry.js',
        'src/lib/webPubSubSender.js'
    )) {
        Invoke-NativeCommand -Command node -Arguments @('--check', $source) -Quiet | Out-Null
    }
}
finally {
    Pop-Location
    if ($temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host 'Validation passed.' -ForegroundColor Green
