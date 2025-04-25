<#.SYNOPSIS
    Assess Azure availabilities by querying Resource Graph and extracting specific properties or metadata.
    Then those extracted information will be compared against actual 

.DESCRIPTION
    This script evaluates the availability of Azure services, resources, and SKUs across different regions.
    When combined with the output from the 1-Collect script, it provides a comprehensive overview of potential
    migration destinations, identifying feasible regions and the reasons for their suitability or limitations,
    such as availability constraints per region.
    All data, including availability details and region-specific insights, will be stored in JSON files.

.EXAMPLE
    PS C:\> .\Get-AvailabilityInformation.ps1
    Runs the script outputs the results to the default files.

.OUTPUTS
    JSON files containing the service, resource, SKU availabilities, and per-region availabilities for a specific implementation.

.NOTES
    - Requires Azure PowerShell module to be installed and authenticated.
#>

clear-host
# REST API: Retrieve access token for REST API
Write-Host "Retrieving access token for REST API" -ForegroundColor Yellow
$AccessToken = az account get-access-token --query accessToken -o tsv
$SubscriptionId = az account show --query id -o tsv  # Automatically retrieve the current subscription ID
$BaseUri = "https://management.azure.com/subscriptions"

# REST API: Define headers with the access token
$Headers = @{
    Authorization = "Bearer $AccessToken"
}
Write-Host ""

# Namespaces and resource types: Start
Write-Host "Retrieving all available namespaces and resource types" -ForegroundColor Yellow
$Overview = az provider list --query "[].{Namespace:namespace, ResourceTypes:resourceTypes[].{Type:resourceType, Locations:locations}}" -o json | ConvertFrom-Json

# Namespaces and resource types: Save namespaces and resource types to a JSON file
Write-Host "Saving namespaces and resource types to file: Azure_Resources.json" -ForegroundColor Green
$Overview | ConvertTo-Json -Depth 10 | Out-File "$(Get-Location)\Azure_Resources.json"
Write-Host ""

# Region information: Start
Write-Host "Working on locations" -ForegroundColor Yellow
Write-Host "Retrieving locations information" -ForegroundColor Green
$LocationUri = "$BaseUri/$SubscriptionId/locations?api-version=2022-12-01"
$LocationResponse = Invoke-RestMethod -Uri $LocationUri -Headers $Headers -Method Get

# Region information: Move everything under metadata to the top level to flatten data, and clean up top-level ID and pairedRegion so that the subscription ID used for retrieval is removed
Write-Host "Location information flattening and PII deletion" -ForegroundColor Green
$TotalRegionsFlat = $LocationResponse.value.Count
$CurrentFlatIndex = 0
foreach ($region in $LocationResponse.value) {
    $CurrentFlatIndex++
    Write-Host ("   Cleaning up location information for region {0:D3} of {1:D3}: {2}" -f $CurrentFlatIndex, $TotalRegionsFlat, $region.displayName) -ForegroundColor Blue

    if ($region.metadata) {
        # Remove subscription ID from pairedRegion and just keep the region name
        if ($region.metadata.pairedRegion) {
            $region.metadata.pairedRegion = $region.metadata.pairedRegion | ForEach-Object { $_.name }
        }
        # Lift all properties from metadata to the top level
        foreach ($key in $region.metadata.PSObject.Properties.Name) {
            $region | Add-Member -MemberType NoteProperty -Name $key -Value $region.metadata.$key -Force
        }
        # Remove the now redundant metadata property
        $region.PSObject.Properties.Remove("metadata")
    }
    # Remove subscription ID from top-level
    $region.PSObject.Properties.Remove("id")
}

# Region information: Save regions to a JSON file
Write-Host "Saving regions to file: Azure_Regions.json" -ForegroundColor Green
$LocationResponse | ConvertTo-Json -Depth 10 | Out-File "$(Get-Location)\Azure_Regions.json"
Write-Host ""

# VM SKUs: Start
Write-Host "Working on VM SKUs" -ForegroundColor Yellow

# VM SKUs: Dynamically retrieve regions from Microsoft.Compute
Write-Host "Retrieving available regions from Microsoft.Compute" -ForegroundColor Green
$ComputeProvider = az provider show --namespace Microsoft.Compute --query "resourceTypes[?resourceType=='virtualMachines'].locations[]" -o tsv
$Regions = $ComputeProvider -split "`n"  # Split regions into an array for processing

# VM SKUs: Track progress variables
$TotalRegions = $Regions.Count
$CurrentRegionIndex = 0

# VM SKUs: Loop through each region and query VM sizes
Write-Host "Adding VM SKUs from consolidated locations" -ForegroundColor Green
$VMResource = @{}
foreach ($Region in $Regions) {
    $CurrentRegionIndex++
    Write-Host ("   Retrieving VM SKUs for region {0:D3} of {1:D3}: {2}" -f $CurrentRegionIndex, $TotalRegions, $Region) -ForegroundColor Blue

    # REST API endpoint for VM SKUs
    $VMUri = "$BaseUri/$SubscriptionId/providers/Microsoft.Compute/locations/$Region/vmSizes?api-version=2021-07-01"

    # Make the REST API call for VM SKUs
    $VMResponse = Invoke-RestMethod -Uri $VMUri -Headers $Headers -Method Get

    # Process the API response
    foreach ($Size in $VMResponse.value) {
        # Check if the VM size already exists in $VMResource
        if (-not $VMResource.ContainsKey($Size.name)) {
            # Add a new entry for this size
            $VMResource[$Size.name] = @{
                Name      = $Size.name
                Locations = @($Region)  # Initialize with the current region
                NumberOfCores = $Size.numberOfCores
                MemoryInMB    = $Size.memoryInMB
            }
        } else {
            # Add the region to the existing size's locations, ensuring no duplicates
            if (-not ($VMResource[$Size.name].Locations -contains $Region)) {
                $VMResource[$Size.name].Locations += $Region
            }
        }
    }
}

# VM SKUs: Convert the hash table to an array
$VMResourceArray = $VMResource.Values

# VM SKUs: Save VM SKUs to a JSON file
Write-Host "Saving VM SKUs to file: Azure_SKUs_VM.json" -ForegroundColor Green
$VMResourceArray | ConvertTo-Json -Depth 10 | Out-File "$(Get-Location)\Azure_SKUs_VM.json"
Write-Host ""

# Storage Account SKUs: Start
Write-Host "Working on storage account SKUs" -ForegroundColor Yellow
Write-Host "Retrieving storage account SKUs" -ForegroundColor Green
$StorageResource = @()

# Storage Account SKUs: REST API Endpoint for Storage SKUs
$StorageUri = "$BaseUri/$SubscriptionId/providers/Microsoft.Storage/skus?api-version=2021-01-01"

# Storage Account SKUs: REST API call
$StorageResponse = Invoke-RestMethod -Uri $StorageUri -Headers $Headers -Method Get

# Storage Account SKUs: Sort $StorageResponse by single Location before Processing
Write-Host "Sorting storage account SKUs by location" -ForegroundColor Green
$StorageResponseSorted = $StorageResponse.value | Sort-Object { $_.locations[0] }

# Storage Account SKUs: Track progress for distinct storage locations
$DistinctLocations = $StorageResponseSorted | ForEach-Object { $_.locations[0] } | Sort-Object | Get-Unique
$TotalStorageLocations = $DistinctLocations.Count
$CurrentLocationIndex = 0

# Storage Account SKUs: Process the sorted Storage API response
Write-Host "Adding storage SKUs from consolidated locations" -ForegroundColor Green
$LastLocation = $null
$StorageResponseSorted | ForEach-Object {
    $CurrentLocation = $_.locations[0]

    # Check if the location changes and update the counter
    if ($CurrentLocation -ne $LastLocation) {
        $CurrentLocationIndex++
        $LastLocation = $CurrentLocation

        Write-Host ("   Retrieving storage SKUs for region {0:D3} of {1:D3}: {2}" -f $CurrentLocationIndex, $TotalStorageLocations, $CurrentLocation) -ForegroundColor Blue
    }

    # Convert Capabilities into individual properties
    $CapabilitiesProperties = @{}
    $_.capabilities | ForEach-Object {
        $Capability = "$($_.name):$($_.value)"
        $NameValuePair = $Capability -split ":"
        if ($NameValuePair.Length -eq 2) {
            $Key = $NameValuePair[0].Trim()
            $Value = $NameValuePair[1].Trim()
            $CapabilitiesProperties[$Key] = $Value
        }
    }

    foreach ($Location in $_.locations) {  # Process each location as its own entry
        $StorageResource += @{
            Name     = $_.name
            Location = $Location  # Single location for storage accounts
            Tier     = $_.tier
            Kind     = $_.kind
        }

        # Flatten the details properties to top-level
        foreach ($Key in $CapabilitiesProperties.Keys) {
            $StorageResource[-1] | Add-Member -MemberType NoteProperty -Name $Key -Value $CapabilitiesProperties[$Key] -Force
        }
    }
}

# Storage Account SKUs: Save Storage SKUs to a JSON file
Write-Host "Saving Storage SKUs to file: Azure_SKUs_Storage.json" -ForegroundColor Green
$StorageResource | ConvertTo-Json -Depth 10 | Out-File "$(Get-Location)\Azure_SKUs_Storage.json"
Write-Host ""

Write-Host "All files have been saved successfully!" -ForegroundColor Green
