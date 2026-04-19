<#
.SYNOPSIS
  Builds a zip of AzureFunctionJumpCloud and publishes it with Azure CLI zip deploy.

.DESCRIPTION
  Optional manual zip deploy using Azure CLI. Use when you changed code locally and do not
  want to redeploy the ARM template (the template also publishes code from GitHub automatically).

.PARAMETER ResourceGroupName
  Resource group that contains the Function App.

.PARAMETER FunctionAppName
  Name of the Azure Function App (the value shown in the portal after deployment).

.PARAMETER FunctionProjectPath
  Folder containing host.json and function folders. Defaults to ..\AzureFunctionJumpCloud next to this script.

.PARAMETER SubscriptionId
  Optional subscription GUID (uses default subscription if omitted).

.EXAMPLE
  .\Deploy-JumpCloudFunction.ps1 -ResourceGroupName "rg-sentinel" -FunctionAppName "asjcxxxx"

.NOTES
  Requires: Azure CLI (`az`), logged in (`az login`). Does not require Azure Functions Core Tools.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string] $FunctionAppName,

    [Parameter(Mandatory = $false)]
    [string] $FunctionProjectPath = '',

    [Parameter(Mandatory = $false)]
    [string] $SubscriptionId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $FunctionProjectPath) {
    $FunctionProjectPath = (Join-Path $PSScriptRoot '..\AzureFunctionJumpCloud' | Resolve-Path -ErrorAction Stop).Path
}

function Assert-AzCli {
    $az = Get-Command az -ErrorAction SilentlyContinue
    if (-not $az) {
        throw 'Azure CLI (`az`) not found. Install from https://aka.ms/installazurecliwindows then run `az login`.'
    }
}

Assert-AzCli

if (-not (Test-Path (Join-Path $FunctionProjectPath 'host.json'))) {
    throw "host.json not found under: $FunctionProjectPath"
}

Write-Host 'Checking Azure CLI session...'
$acct = az account show 2>$null | ConvertFrom-Json
if (-not $acct) {
    throw 'Not logged in. Run: az login'
}

if ($SubscriptionId) {
    az account set --subscription $SubscriptionId | Out-Null
}

$zipPath = Join-Path ([System.IO.Path]::GetTempPath()) ("jumpcloud-fn-{0}.zip" -f [Guid]::NewGuid().ToString('N'))
try {
    Write-Host "Creating package: $zipPath"
    Push-Location $FunctionProjectPath
    try {
        if (Test-Path $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
        # Zip root must match folder layout (host.json + function dirs at archive root).
        $items = @(Get-ChildItem -LiteralPath . -Force | ForEach-Object { $_.FullName })
        if ($items.Count -eq 0) {
            throw "No files found under $FunctionProjectPath"
        }
        Compress-Archive -LiteralPath $items -DestinationPath $zipPath -CompressionLevel Optimal -Force
    }
    finally {
        Pop-Location
    }

    Write-Host 'Removing WEBSITE_RUN_FROM_PACKAGE if set (old template used Microsoft aka.ms; that blocks your local code).'
    $null = & az functionapp config appsettings delete `
        --name $FunctionAppName `
        --resource-group $ResourceGroupName `
        --setting-names WEBSITE_RUN_FROM_PACKAGE 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host '  (No change or setting was already absent; continuing with zip deploy.)' -ForegroundColor DarkGray
    }

    Write-Host 'Uploading zip (this can take a minute)...'
    az functionapp deployment source config-zip `
        --resource-group $ResourceGroupName `
        --name $FunctionAppName `
        --src $zipPath

    if ($LASTEXITCODE -ne 0) {
        throw "Zip deploy failed (exit $LASTEXITCODE)."
    }

    Write-Host 'Done. Your Function App should now run the published project (including JCQueueTrigger1/run.ps1).'
    Write-Host 'Tip: In the portal, Function App -> Functions -> refresh; or wait ~1 minute and check Invocations / Log stream.'
}
finally {
    if (Test-Path $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
    }
}
