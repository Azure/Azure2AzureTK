<#
.SYNOPSIS
    Run a series of resource graph queries and place the outputs in Excel tabs
.EXAMPLE
    PS C:\> graph_query.ps1
.INPUTS
    None
.OUTPUTS
    Various, depending on the RGE queries run
.NOTES
    Requires a modern version of module Az.ResourceGraph that supports skip tokens (0.13.0 confirmed to work)
    https://learn.microsoft.com/en-us/azure/governance/resource-graph/troubleshoot/general#scenario-too-many-subscriptions
    https://learn.microsoft.com/en-us/azure/governance/resource-graph/concepts/work-with-data#paging-results

    Requires module ImportExcel to export the results to Excel
    https://www.powershellgallery.com/packages/ImportExcel/
    PS1> Install-Module -Name ImportExcel

    The export to Excel will fail if sensitivity labels are applied to the file. To avoid this, create a blank Excel
    file with General or lower sensitivity before running the script.

    If the export to Excel fails then it might be due to sensitivity labels. Try creating an unencrypted blank Excel file
    and running the script again. The script will then write to that file instead of creating a new one.
#>

function runQuery ($query, $outputTab) {
    # Resource Graph queries are limited to 1000 results at a time and can look at 1000 subscriptions at a time
    # For both subscriptions and results therefore we need to process them in batches

    # Create a counter, set the batch size for subscriptions, and prepare a variable for the results
    $counter = [PSCustomObject] @{ Value = 0 }
    $batchSize = 1000
    $resultSet = @()

    # Group the subscriptions into batches
    $subscriptionsBatch = $subscriptionIds | Group-Object -Property { [math]::Floor($counter.Value++ / $batchSize) }

    # Run the query(ies) for each batch
    foreach ($batch in $subscriptionsBatch) {
        # Run the first query
        $response = Search-AzGraph -Query $query -Subscription $batch.Group -First 1000
        $resultSet += $response

        # If a skip token is returned, there are more results to fetch
        while ($null -ne $response.SkipToken) {
            $response = Search-AzGraph -Query $query -Subscription $batch.Group -First 1000 -SkipToken $response.SkipToken
            $resultSet += $response
        }
    }

    # View the completed results of the query on all subscriptions
    #$resultSet.id | Out-File -FilePath $outputFile -Width 1000

    $resultSet | Export-Excel -WorksheetName $outputTab -TableName $outputTab -Path .\$excelName
    # $resultSet | Export-Csv -Path $outputFile -UseQuotes Never
    Write-Output "$($resultSet.Count) results written to tab $outputTab"
}

# Input file
$workloadFile = ".\subscriptions.json"
$workloads = @()

# Add specialised workloads here
$workloadAro = $true
$workloadAks = $false
$workloadDatabricks = $false
$excelName = "ResourceGraphQueries.xlsx"

<#
Connect-AzAccount -tenant $tenantId
#>

# Read the content of the workloads file
$jsonContent = Get-Content -Path $workloadFile -Raw

# Convert the JSON content to a PowerShell object
$workloads = $jsonContent | ConvertFrom-Json
$subscriptionIds = $workloads.Subscriptions

# VM count by SKU
#$query = 'resources | where type =~ "microsoft.compute/virtualmachines" | project vmSku = tostring(properties.hardwareProfile.vmSize) | summarize count() by vmSku | order by count_ desc'
#runQuery $query "vmCountBySku.txt"

# Show the resource types in use
$query = 'resources | summarize count() by type'
runQuery $query "ResourceTypes"

# Show number of resources by type and location
#$query = 'resources | summarize count() by subscriptionId, type, location'
$query = 'resources | project subscriptionId, name, type, location'
runQuery $query "ResourceCount"

# VM redundancy settings (none / AvSet / AvZone)
$query = @'
resources
| where type =~ "Microsoft.Compute/virtualMachines"
| extend availabilitySet = properties.availabilitySet.id, availabilityZone = zones, vmSize = properties.hardwareProfile.vmSize, PPG = split(properties.proximityPlacementGroup.id, "/")[-1]
| project subscriptionId, resourceGroup, name, location, vmSize, availabilitySet, availabilityZone, PPG, tags
'@
runQuery $query "VMs"

# Disks
$query = @'
resources
| extend lowerId = tolower(id)
| join kind=inner (
    resources
    | where type == "microsoft.compute/disks"
    | extend diskSku = tostring(sku.name)
    | project diskName = name, diskSku, vmId = tolower(managedBy), sizeGb = properties.diskSizeGB
) on $left.lowerId == $right.vmId
| project-away vmId
| project subscriptionId, vmName = name, location, diskName, diskSku, sizeGb, tags
'@
runQuery $query "Disks"

# Recovery services vaults
$query = @'
resources
| where type == "microsoft.recoveryservices/vaults"
| extend sku = tostring(properties.redundancySettings.standardTierStorageRedundancy)
| project subscriptionId, resourceGroup, location, name, sku, tags
'@
runQuery $query "RecoveryServicesVaults"

# Storage accounts
$query = @'
resources
| where type == "microsoft.storage/storageaccounts"
| extend sku = tostring(sku.name)
| project subscriptionId, resourceGroup, name, location, kind, sku, tags
'@
runQuery $query "StorageAccounts"

# Specialised workload - ARO
if ($workloadAro) {
    $query = @'
    resources
    | where type =~ "microsoft.redhatopenshift/openshiftclusters"
    | mv-expand wp = properties.workerProfiles
    | extend nodeName = wp.name, nodeSize = wp.vmSize
    | project subscriptionId, resourceGroup, name, location, version = properties.clusterProfile.version, nodeName, nodeSize, tags
'@
    runQuery $query "ARO"
}