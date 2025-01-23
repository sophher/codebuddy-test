# Script to copy Hetzner speed test file directly to Azure Blob Storage using managed identity
# Requires Az.Storage module

# Configuration
$subscriptionId = "e4ca3d2d-0a67-424e-b08f-78b4c49a49f5"
$sourceUrl = "https://ash-speed.hetzner.com/100MB.bin"
$resourceGroupName = "agilox-jira-backup"
$storageAccountName = "agiloxjirabackupstorage"
$containerName = "agiloxjirabackupstorage"
$blobName = "speedtest.bin"

try {
    # Connect to Azure using managed identity
    Write-Output "Connecting to Azure using managed identity..."
    Connect-AzAccount -Identity

    # Set subscription context
    Write-Output "Setting subscription context..."
    Set-AzContext -SubscriptionId $subscriptionId
    $currentContext = Get-AzContext
    Write-Output "Current subscription: $($currentContext.Subscription.Name)"
    Write-Output "Current tenant: $($currentContext.Tenant.Id)"

    # Get storage account context
    Write-Output "Getting storage account context..."
    $storageAccount = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName
    if (-not $storageAccount) {
        throw "Could not find storage account '$storageAccountName' in resource group '$resourceGroupName'"
    }

    # Verify we have a valid context
    if (-not $storageAccount.Context) {
        throw "Failed to get valid storage context. Please verify managed identity permissions."
    }

    # Start the copy operation
    Start-AzStorageBlobCopy -AbsoluteUri $sourceUrl -DestContainer $containerName -DestBlob $blobName -Context $storageAccount.Context

    # Monitor copy progress
    $copyStatus = Get-AzStorageBlobCopyState -Container $containerName -Blob $blobName -Context $storageAccount.Context
    while ($copyStatus.Status -eq "Pending") {
        $progress = ($copyStatus.BytesCopied / $copyStatus.TotalBytes) * 100
        Write-Progress -Activity "Copying blob" -Status "$progress% Complete:" -PercentComplete $progress
        Start-Sleep -Seconds 2
        $copyStatus = Get-AzStorageBlobCopyState -Container $containerName -Blob $blobName -Context $storageAccount.Context
    }

    if ($copyStatus.Status -eq "Success") {
        Write-Output "File successfully copied to Azure Blob Storage"
    }
    else {
        throw "Copy operation failed with status: $($copyStatus.Status). Please check storage account permissions."
    }
}
catch {
    Write-Error "An error occurred: $($_.Exception.Message)`nStack trace: $($_.ScriptStackTrace)"
    throw
}
