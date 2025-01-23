# Script to copy Hetzner speed test file directly to Azure Blob Storage using managed identity
# Requires Az.Storage module

# Configuration
$sourceUrl = "http://ipv4.download.thinkbroadband.com/5MB.zip"
$subscriptionId = "e4ca3d2d-0a67-424e-b08f-78b4c49a49f5"
$storageAccountName = "agiloxjirabackupstorage"
$containerName = "agiloxjirabackupstorage"
$blobName = "5MB.zip"

# Validate source URL
function Test-SourceUrl {
    param($Url)
    try {
        $response = Invoke-WebRequest -Uri $Url -Method Head -UseBasicParsing
        return $response.StatusCode -eq 200
    } catch {
        throw "Source URL is not accessible: $($_.Exception.Message)"
    }
}

# Helper function to verify container exists
function Test-StorageContainer {
    param($Context, $ContainerName)
    try {
        return Get-AzStorageContainer -Name $ContainerName -Context $Context -ErrorAction Stop
    }
    catch {
        throw "Container '$ContainerName' not found or access denied. Error: $($_.Exception.Message)"
    }
}

try {
    # Connect to Azure using managed identity
    Write-Output "Connecting to Azure using managed identity..."
    Connect-AzAccount -Identity

    # Set subscription context
    Write-Output "Setting subscription context..."
    $null = Set-AzContext -SubscriptionId $subscriptionId
    $currentContext = Get-AzContext
    Write-Output "Current subscription: $($currentContext.Subscription.Name)"
    Write-Output "Current tenant: $($currentContext.Tenant.Id)"

    # Get storage account context
    $storageAccountContext = New-AzStorageContext -UseConnectedAccount -StorageAccountName $storageAccountName
    if (-not $storageAccountContext) {
        throw "Failed to get valid storage context."
    }
    Write-Output "Storage account context obtained successfully."

    # Verify container exists
    Write-Output "Verifying container exists..."
    $null = Test-StorageContainer -Context $storageAccountContext -ContainerName $containerName
    Write-Output "Container verification successful."

    # Validate source URL
    Write-Output "Validating source URL..."
    $null = Test-SourceUrl -Url $sourceUrl
    Write-Output "Source URL validation successful."

    # Start the copy operation
    Write-Output "Starting copy operation..."
    
    # Start the actual copy operation
    $blob = Start-AzStorageBlobCopy -AbsoluteUri $sourceUrl -DestContainer $containerName -DestBlob $blobName -Context $storageAccountContext -Force
    if (-not $blob) {
        throw "Failed to initiate copy operation."
    }

    # Initialize timeout counter
    $timeout = 300 # 5 minutes timeout
    $timer = [System.Diagnostics.Stopwatch]::StartNew()

    # Monitor copy progress
    $copyStatus = $blob | Get-AzStorageBlobCopyState
    if (-not $copyStatus) {
        throw "Failed to get copy status."
    }

    while ($copyStatus.Status -eq "Pending" -and $timer.Elapsed.TotalSeconds -lt $timeout) {
        $progress = ($copyStatus.BytesCopied / $copyStatus.TotalBytes) * 100
        Write-Progress -Activity "Copying blob" -Status "$progress% Complete:" -PercentComplete $progress
        Start-Sleep -Seconds 2
        $copyStatus = $blob | Get-AzStorageBlobCopyState
    }

    $timer.Stop()
    
    if ($timer.Elapsed.TotalSeconds -ge $timeout) {
        throw "Copy operation timed out after $timeout seconds."
    }

    if ($copyStatus.Status -eq "Success") {
        Write-Output "File successfully copied to Azure Blob Storage"
    }
    else {
        throw "Copy operation failed with status: $($copyStatus.Status)."
    }
}
catch {
    Write-Error "An error occurred: $($_.Exception.Message)`nStack trace: $($_.ScriptStackTrace)"
    throw
}
