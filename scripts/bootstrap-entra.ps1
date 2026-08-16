[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$TenantId,

    [string]$ApiDisplayName = 'dronefleet-api',
    [string]$PublicClientDisplayName = 'dronefleet-public-client',
    [string]$ScopeName = 'Drone.Provision',
    [string]$BackendUrl = '',
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-AzJson {
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'POST', 'PATCH')][string]$Method,
        [Parameter(Mandatory)][string]$Url,
        [object]$Body
    )

    $arguments = @('rest', '--method', $Method, '--url', $Url, '--output', 'json', '--only-show-errors')
    $temporaryFile = $null
    try {
        if ($null -ne $Body) {
            $temporaryFile = [IO.Path]::GetTempFileName()
            $Body | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $temporaryFile -Encoding utf8
            $arguments += @('--headers', 'Content-Type=application/json', '--body', "@$temporaryFile")
        }
        $previousPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $json = @(& az @arguments)
            $exitCode = $LASTEXITCODE
        }
        finally { $ErrorActionPreference = $previousPreference }
        if ($exitCode -ne 0) { throw "Azure CLI request failed: $Method $Url" }
        if ([string]::IsNullOrWhiteSpace(($json -join "`n"))) { return $null }
        return ($json -join "`n") | ConvertFrom-Json
    }
    finally {
        if ($temporaryFile) { Remove-Item -LiteralPath $temporaryFile -Force -ErrorAction SilentlyContinue }
    }
}

function Get-ApplicationByDisplayName {
    param([Parameter(Mandatory)][string]$DisplayName)
    $filter = [Uri]::EscapeDataString("displayName eq '$($DisplayName.Replace("'", "''"))'")
    # Keep the query to one parameter: Windows invokes az through az.cmd, whose
    # command processor otherwise treats '&$select' as a second command.
    $url = "https://graph.microsoft.com/v1.0/applications?`$filter=$filter"
    $response = Invoke-AzJson -Method GET -Url $url
    $matches = @(if ($response -and $response.PSObject.Properties['value']) { $response.value })
    if ($matches.Count -gt 1) { throw "More than one app registration is named '$DisplayName'. Rename duplicates before continuing." }
    return $matches | Select-Object -First 1
}

function Ensure-ServicePrincipal {
    param([Parameter(Mandatory)][string]$AppId)
    $filter = [Uri]::EscapeDataString("appId eq '$AppId'")
    $url = "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=$filter"
    $response = Invoke-AzJson -Method GET -Url $url
    $existing = if ($response -and $response.PSObject.Properties['value']) {
        @($response.value) | Select-Object -First 1
    } else { $null }
    if ($existing) { return $existing }
    return Invoke-AzJson -Method POST -Url 'https://graph.microsoft.com/v1.0/servicePrincipals' -Body @{ appId = $AppId }
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw 'Azure CLI is required. Install it, then run az login --tenant <tenant-id>.' }

$previousPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $accountJson = @(& az account show --output json --only-show-errors)
    $accountExitCode = $LASTEXITCODE
}
finally { $ErrorActionPreference = $previousPreference }
if ($accountExitCode -ne 0) { throw "Sign in first with: az login --tenant $TenantId" }
$account = ($accountJson -join "`n") | ConvertFrom-Json
if ($account.tenantId -ne $TenantId) {
    throw "Azure CLI is signed into tenant '$($account.tenantId)', not '$TenantId'. Run: az login --tenant $TenantId"
}

$androidRedirects = @(
    'msauth://com.androidpilot.app/OStPVeK30u7Dl1Y25hjpoaIrK+U=',
    'msauth://com.androiddrone.app/OStPVeK30u7Dl1Y25hjpoaIrK+U='
)
$browserRedirects = @('http://localhost:8080/')
if ($BackendUrl) { $browserRedirects += ($BackendUrl.TrimEnd('/') + '/') }
$browserRedirects = @($browserRedirects | Sort-Object -Unique)

$apiApp = Get-ApplicationByDisplayName -DisplayName $ApiDisplayName
$publicApp = Get-ApplicationByDisplayName -DisplayName $PublicClientDisplayName

if (-not $Apply) {
    Write-Host 'Preview only. No Entra objects were changed.' -ForegroundColor Yellow
    Write-Host "API app:    $(if ($apiApp) { $apiApp.appId } else { '<create>' })"
    Write-Host "Public app: $(if ($publicApp) { $publicApp.appId } else { '<create>' })"
    Write-Host "Scope:      $ScopeName"
    Write-Host "SPA URIs:   $($browserRedirects -join ', ')"
    Write-Host "Android:    $($androidRedirects -join ', ')"
    Write-Host 'Rerun with -Apply to create or update these registrations.' -ForegroundColor Cyan
    return
}

if (-not $apiApp) {
    $apiApp = Invoke-AzJson -Method POST -Url 'https://graph.microsoft.com/v1.0/applications' -Body @{
        displayName = $ApiDisplayName
        signInAudience = 'AzureADandPersonalMicrosoftAccount'
    }
}

$scope = @($apiApp.api.oauth2PermissionScopes | Where-Object value -eq $ScopeName) | Select-Object -First 1
$scopeId = if ($scope) { $scope.id } else { [guid]::NewGuid().ToString() }
$apiPatch = @{
    identifierUris = @("api://$($apiApp.appId)")
    api = @{
        requestedAccessTokenVersion = 2
        oauth2PermissionScopes = @(@{
            adminConsentDescription = 'Operate assigned drones and provision approved drone installations.'
            adminConsentDisplayName = 'Operate and provision drones'
            id = $scopeId
            isEnabled = $true
            type = 'User'
            userConsentDescription = 'Operate drones assigned to you.'
            userConsentDisplayName = 'Operate assigned drones'
            value = $ScopeName
        })
    }
}
Invoke-AzJson -Method PATCH -Url "https://graph.microsoft.com/v1.0/applications/$($apiApp.id)" -Body $apiPatch | Out-Null
$apiApp = Get-ApplicationByDisplayName -DisplayName $ApiDisplayName
Ensure-ServicePrincipal -AppId $apiApp.appId | Out-Null

$publicPayload = @{
    displayName = $PublicClientDisplayName
    signInAudience = 'AzureADandPersonalMicrosoftAccount'
    isFallbackPublicClient = $true
    publicClient = @{ redirectUris = $androidRedirects }
    spa = @{ redirectUris = $browserRedirects }
    requiredResourceAccess = @(@{
        resourceAppId = $apiApp.appId
        resourceAccess = @(@{ id = $scopeId; type = 'Scope' })
    })
}

if (-not $publicApp) {
    $publicApp = Invoke-AzJson -Method POST -Url 'https://graph.microsoft.com/v1.0/applications' -Body $publicPayload
} else {
    Invoke-AzJson -Method PATCH -Url "https://graph.microsoft.com/v1.0/applications/$($publicApp.id)" -Body $publicPayload | Out-Null
    $publicApp = Get-ApplicationByDisplayName -DisplayName $PublicClientDisplayName
}
Ensure-ServicePrincipal -AppId $publicApp.appId | Out-Null

$apiPatch.api.preAuthorizedApplications = @(@{
    appId = $publicApp.appId
    delegatedPermissionIds = @($scopeId)
})
Invoke-AzJson -Method PATCH -Url "https://graph.microsoft.com/v1.0/applications/$($apiApp.id)" -Body $apiPatch | Out-Null

$result = [ordered]@{
    tenantId = $TenantId
    apiClientId = $apiApp.appId
    publicClientId = $publicApp.appId
    scopeName = $ScopeName
    scope = "api://$($apiApp.appId)/$ScopeName"
    backendUrl = $BackendUrl
}
$result | ConvertTo-Json
Write-Host "`nUse these values for deployment:" -ForegroundColor Green
Write-Host "  -EntraApiClientId '$($apiApp.appId)' -EntraPublicClientId '$($publicApp.appId)'"
