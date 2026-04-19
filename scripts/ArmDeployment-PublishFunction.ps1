# Runs inside Azure Deployment Script (managed identity). Publishes AzureFunctionJumpCloud from a GitHub repo archive.
# Called by azuredeploy_JumpCloud_API_FunctionApp.json with: -ResourceGroupName -FunctionAppName -StorageAccountName -ArchiveUrl

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string] $FunctionAppName,

    [Parameter(Mandatory = $true)]
    [string] $StorageAccountName,

    [Parameter(Mandatory = $true)]
    [string] $ArchiveUrl,

    [Parameter(Mandatory = $false)]
    [string] $BlobContainerName = 'function-packages',

    [Parameter(Mandatory = $false)]
    [string] $BlobName = 'jumpcloud-functionapp.zip'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Output "ArchiveUrl=$ArchiveUrl"
Write-Output "FunctionApp=$FunctionAppName RG=$ResourceGroupName Storage=$StorageAccountName"

# Deployment script image includes Az modules; MI is pre-authenticated.
Import-Module Az.Accounts, Az.Storage, Az.Functions -ErrorAction Stop

# Allow RBAC propagation (Contributor on RG was assigned to this MI before the script started).
for ($i = 0; $i -lt 24; $i++) {
    try {
        Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
        $sub = (Get-AzContext).Subscription.Id
        if ($sub) { break }
    }
    catch {
        Write-Output "Waiting for MI auth (attempt $($i + 1))..."
        Start-Sleep -Seconds 10
    }
}
if (-not (Get-AzContext).Subscription) {
    throw 'Connect-AzAccount -Identity failed after retries.'
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
    $repoZip = Join-Path $tmp 'repo.zip'
    Write-Output "Downloading $ArchiveUrl ..."
    Invoke-WebRequest -Uri $ArchiveUrl -OutFile $repoZip -UseBasicParsing -MaximumRedirection 5

    $extractRoot = Join-Path $tmp 'extract'
    Expand-Archive -LiteralPath $repoZip -DestinationPath $extractRoot -Force

    $funcDir = Get-ChildItem -Path $extractRoot -Recurse -Directory -ErrorAction SilentlyContinue |
        Where-Object { (Test-Path (Join-Path $_.FullName 'host.json')) -and ($_.Name -eq 'AzureFunctionJumpCloud') } |
        Select-Object -First 1

    if (-not $funcDir) {
        throw 'Could not find AzureFunctionJumpCloud/host.json inside the downloaded archive. Fork users: set FunctionSourceArchiveUrl to your repo zip.'
    }

    $pkgZip = Join-Path $tmp 'package.zip'
    if (Test-Path $pkgZip) { Remove-Item -LiteralPath $pkgZip -Force }
    $items = @(Get-ChildItem -LiteralPath $funcDir.FullName -Force | ForEach-Object { $_.FullName })
    Compress-Archive -LiteralPath $items -DestinationPath $pkgZip -CompressionLevel Optimal -Force

    $keys = Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName
    $ctx = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $keys[0].Value

    if (-not (Get-AzStorageContainer -Name $BlobContainerName -Context $ctx -ErrorAction SilentlyContinue)) {
        New-AzStorageContainer -Name $BlobContainerName -Context $ctx -Permission Off | Out-Null
    }

    Write-Output "Uploading blob $BlobContainerName/$BlobName ..."
    Set-AzStorageBlobContent -Container $BlobContainerName -Blob $BlobName -File $pkgZip -Context $ctx -Force | Out-Null

    $start = Get-Date
    $expiry = $start.AddYears(10)
    $sas = New-AzStorageBlobSASToken -Container $BlobContainerName -Blob $BlobName -Permission r -StartTime $start -ExpiryTime $expiry -FullUri -Context $ctx

    Write-Output "Setting WEBSITE_RUN_FROM_PACKAGE on Function App ..."
    Update-AzFunctionAppSetting -Name $FunctionAppName -ResourceGroupName $ResourceGroupName -AppSetting @{ WEBSITE_RUN_FROM_PACKAGE = $sas } | Out-Null

    $DeploymentScriptOutputs = @{
        Status = 'OK'
        Blob   = "$BlobContainerName/$BlobName"
    }
}
finally {
    if (Test-Path $tmp) {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
