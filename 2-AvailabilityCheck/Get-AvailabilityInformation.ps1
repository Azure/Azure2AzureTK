<#.SYNOPSIS
    This script evaluates the availability of Azure providers and SKUs across multiple regions by querying
    Azure Resource Graph to retrieve specific properties and metadata. The extracted data will then be
    analyzed and compared against the customer's current implementation to identify potential regions suitable
    for migration.

.DESCRIPTION
    This script assesses the availability of Azure services, resources, and SKUs across multiple regions.
    By integrating its output with the data collected from the 1-Collect script, it delivers a comprehensive
    analysis of potential migration destinations, identifying suitable regions and highlighting factors that
    may impact feasibility, such as availability constraints specific to each region. All extracted data,
    including availability details and region-specific insights, will be systematically stored in JSON files
    for further evaluation and decision-making.

.EXAMPLE
    PS C:\> .\Get-AvailabilityInformation.ps1
    Runs the script and outputs the results to the default files.

.OUTPUTS
    Availability_Mapping.json
    Mapping of all currently implemented resources and their SKUs, to Azure regions with availabilities.

.OUTPUTS
    Azure_Providers.json
    All Azure providers and their resource types, including locations.

.OUTPUTS
    Azure_Regions.json
    All Azure regions with their display names, metadata, and availability information.

.OUTPUTS
    Azure_SKUs_SQL_Managed_Instance.json
    All Azure SQL managed instance SKUs with name and sku information.

.OUTPUTS
    Azure_SKUs_SQL_Server_Database.json
    All Azure SQL Server database SKUs with name, tier, family, and capacity information.

.OUTPUTS
    Azure_SKUs_StorageAccount.json
    All Azure storage account SKUs with their locations, tiers, and capabilities.

.OUTPUTS
    Azure_SKUs_VM.json
    All Azure VM SKUs with their locations, number of cores, and memory.

.NOTES
    - Requires Azure PowerShell module to be installed and authenticated.
#>
<#TODO:
    - Add handling for when rest api call fails with legitimate error, i.e. rest api not found for region
    - Investigate https://management.azure.com/subscriptions/f887760f-7b55-41fd-b71c-02ed1b3c475c/providers/Microsoft.Features/providers/Microsoft.Compute/features?api-version=2015-12-01 and 
    https://management.azure.com/subscriptions/f887760f-7b55-41fd-b71c-02ed1b3c475c/providers/Microsoft.Compute/diskEncryptionSets?api-version=2023-04-02 for compute related resources
    - Consider changing collect script to put in implementedregions and implementedskus to avoid renaming here in Import-CurrentEnvironment

#>
function Out-JSONFile {
    param (
        [Parameter(Mandatory = $true)]
        [object]$Data,
        [Parameter(Mandatory = $true)]
        [string]$FileName
    )
    # This function writes the provided data to a JSON file at the specified path.
    Write-Output "  Writing data to file: $FileName" | Out-Host
    $Data | ConvertTo-Json -Depth 100 | Out-File -FilePath "$(Get-Location)\$FileName" -Force
}

function Write-Headline {
    param (
        [Parameter(Mandatory = $true)]
        [object]$Text
    )
    Write-Output "####################################################################################################"
    Write-Output "   $Text"
    Write-Output "####################################################################################################"
    Write-Output ""
}

function Convert-LocationsToRegionCodes {
    param (
        [Parameter(Mandatory)][Object]$Data,
        [Parameter(Mandatory)][hashtable]$RegionMap
    )
    # Build reverse lookup (display name -> key)
    $ReverseMap = @{}
    foreach ($k in $RegionMap.Keys) { $ReverseMap[$RegionMap[$k].ToLower()] = $k }
    foreach ($item in $Data) {
        foreach ($rt in $item.ResourceTypes) {
            if ($rt.Locations) {
                $rt.Locations = @(
                    $rt.Locations | ForEach-Object {
                        $lk = $_.ToLower()
                        if ($ReverseMap.ContainsKey($lk)) { $ReverseMap[$lk] } else { $_ }
                    }
                )
            }
        }
    }
    return $Data
}


function Import-Provider {
    param (
        [Parameter(Mandatory = $true)][string]$uriRoot
    )
    # This function retrieves all available Azure providers and their resource types, including locations.
    Write-Output "Retrieving all available providers" | Out-Host
    $Response = (Invoke-AzRestMethod -Uri "$uriRoot/providers?api-version=2021-04-01" -Method Get).Content | ConvertFrom-Json -depth 100
    
    # Transform the response to the desired structure and remove unwanted properties
    $Providers = foreach ($provider in $Response.value) {
        # Build an array of resource types using plain hashtables
        $rtArray = @()
        foreach ($rt in $provider.resourceTypes) {
            $rtArray += @{
                Type      = $rt.resourceType
                Locations = $rt.locations
            }
        }
        # Return a hashtable for each provider
        @{
            Namespace     = $provider.namespace
            ResourceTypes = $rtArray
        }
    }
    # Convert location display names to region codes using the provided region map
    $Providers = Convert-LocationsToRegionCodes -Data $Providers -RegionMap $Regions_All.Map
    # Save providers to a JSON file
    Out-JSONFile -Data $Providers -fileName "Azure_Providers.json"
    return @{
        Data = $Providers
    }
}

function Import-Region {
    # This function retrieves all Azure regions, sorts them alphabetically, flattens metadata to the top level, and removes PII information.
    Write-Output "  Retrieving regions information" | Out-Host
    $Response = (Invoke-AzRestMethod -Uri "$uriRoot/locations?api-version=2022-12-01" -Method Get).Content | ConvertFrom-Json -depth 100
    # Sort regions alphabetically by displayName
    $Response.value = $Response.value | Sort-Object displayName
    # Flatten metadata to the top level and remove PII information
    $ConsolidatedRegions = @()
    $TotalRegions = $Response.value.Count
    $CurrentRegionIndex = 0
    foreach ($Region in $Response.value | where { $_.metadata.regionType -eq "Physical" }) {
        #Write-Output "$($region.name) is regionType: $($region.metadata.regionType)" | out-host}
        $CurrentRegionIndex++
        Write-Output ("    Removing information for region {0:D03} of {1:D03}: {2}" -f $CurrentRegionIndex, $TotalRegions, $Region.displayName) | Out-Host
        if ($Region.metadata ) {
            $region.metadata.regionType -eq "Physical"
            # Remove subscription ID from pairedRegion and just keep the region name
            if ($Region.metadata.pairedRegion) {
                $Region.metadata.pairedRegion = $Region.metadata.pairedRegion | ForEach-Object { $_.name }
            }
            # Lift all properties from metadata to the top level
            foreach ($key in $Region.metadata.PSObject.Properties.Name) {
                $Region | Add-Member -MemberType NoteProperty -Name $key -Value $Region.metadata.$key -Force
            }
        }
        # Rebuild the object without metadata and id
        $newRegion = $Region | Select-Object * -ExcludeProperty metadata, id
        $ConsolidatedRegions += $newRegion
    }
    $Response.value = $ConsolidatedRegions
    # Create a mapping of region names to display names, this will be used later to replace region names with display names.
    $RegionMap = @{}
    $shortList = @()
    foreach ($Location in $Response.value) {
        $RegionMap[$Location.name] = $Location.displayName
        $shortlist += $location.name
    }
    # Save regions to a JSON file
    #Out-JSONFile -Data $Response -fileName "Azure_Regions.json"
    return @{
        Regions   = $Response
        Map       = $RegionMap
        ShortList = $shortList
    }
}

Function Get-ResourceTypeParameters {
    param (
        [Parameter(Mandatory = $true)][string]$ResourceType
    )
    # This function retrieves the parameters for a given resource type from the property maps.
    $propertyMapJson = Get-Content -path ".\propertymaps\propertyMaps.json" | ConvertFrom-Json
    $propertyExists = $propertyMapJson | Where-Object { $psitem.resourceType -eq $ResourceType }
    if ($propertyExists) {
        set-variable -Name 'resourceProps' -Value $propertyExists -scope script
    }
    else {
        Write-Output "No property map found for resource type $ResourceType"
    }
}

Function Get-Property {
    param(
        [Parameter(Mandatory)][pscustomobject]$object,
        [Parameter(Mandatory)][pscustomobject]$PropertyNames,
        [Parameter(Mandatory)][pscustomobject]$outputObject
    )
    $skuName = $outputObject.skuName
    foreach ($key in $PropertyNames.PSObject.Properties.Name) {
        $sourceProp = $PropertyNames.$key
        $value = $object.$sourceProp
        Write-Output "add _$value to skuName"
        $skuName += "_$value"
        $outputObject[$key] = $value
    }
    $skuName = $skuName.TrimStart('_')
    $outputObject.skuName = $skuName
    return $outputObject
}
Function Expand-NestedCollection {
    param(
        [Parameter(Mandatory)]$InputObjects,
        [Parameter(Mandatory)][pscustomobject]$Schema
    )
    $lSkus = @()
    $InputObjects | ConvertTo-Json -Depth 3
    $InputObjects | ForEach-Object {
        # Navigate down to the parent
        $parentObj = $PSItem
        for ($i = 0; $i -lt $Schema.startPath.Count; $i++) {
            $parentObj = $parentObj.$($Schema.startPath[$i])
        }
        foreach ($o in $parentObj) {
            If (!$Schema.ChildProperties -and $Schema.TopLevelProperties.Count -ge 1) {
                $props = @{"skuName" = ""}
                $props = get-Property -object $o -PropertyNames $Schema.TopLevelProperties -outputObject $props
                # trim leading underscore from skuName
                $props
                $lSkus += $props
            }
            elseif ($Schema.ChildProperties -and $Schema.TopLevelProperties.Count -ge 1) {
                $props = @{"skuName" = ""}
                $props = get-Property -object $o -PropertyNames $Schema.TopLevelProperties -outputObject $props
                $children = $o.$($Schema.ChildProperties.name)
                foreach ($child in $children) {
                    $childProps = $props.Clone()
                    $childProps = get-Property -object $child -PropertyNames $Schema.ChildProperties.props -outputObject $childProps
                    $childProps
                    $lSkus += $childProps
                }
            }
        }
        $script:SKUs = $lSkus
    } 
}

Function Get-ResourceType {
    param (
        [Parameter(Mandatory = $true)][string]$ResourceType,
        [Parameter(Mandatory = $true)][string]$outPutFile,
        [Parameter(Mandatory = $false)][bool]$regionalApiCall = $true
    )
    $resourceObject = New-Object psobject
    Add-Member -InputObject $resourceObject -MemberType NoteProperty -Name "ResourceType" -Value $ResourceType
    Get-ResourceTypeParameters -ResourceType $ResourceType
    $uri01 = $resourceProps.uri
    $propertyFilter = $resourceProps.properties
    $script:SKUs = @()
    $outArray = @()
    If ($regionalApiCall) {
        Foreach ($region in $Regions_All.ShortList) {
            $baseObject = New-Object psobject
            Add-Member -InputObject $baseObject -MemberType NoteProperty -Name "regionCode" -Value $region
            $uri = $uri01 -f $subscriptionId, $region
            "Invoke-AzRestMethod -Uri $uri -Method Get"
            $Response = (Invoke-AzRestMethod -Uri $uri -Method Get).Content | ConvertFrom-Json -depth 100
            If ($response.error.code -ne 'NoRegisteredProviderFound') {
                # Handle cases where the response might be wrapped in a 'Value' property
                if ($Response.PSObject.Properties.Name -contains 'Value') {
                    $Response = $Response.Value
                }
                Expand-NestedCollection -InputObjects $response -Schema $propertyFilter
                Add-Member -InputObject $baseObject -MemberType NoteProperty -Name "skus" -Value $Skus 
            }
            else {
                "No SKUs found for region $region"
                $baseObject | Add-Member -MemberType NoteProperty -Name "skus" -Value @()
            }
            $outArray += $baseObject
        } 
    }
    Else {
        "This api call gets all skus for all regions in one call"
        $uri = $uri01 -f $subscriptionId
        "Invoke-AzRestMethod -Uri $uri -Method Get"
        $Response = (Invoke-AzRestMethod -Uri $uri -Method Get).Content | ConvertFrom-Json -depth 100
        if ($Response.PSObject.Properties.Name -contains 'Value') {
            $Response = $Response.Value
        }
        Foreach ($region in $Regions_All.ShortList) {
            $baseObject = New-Object psobject
            Add-Member -InputObject $baseObject -MemberType NoteProperty -Name "regionCode" -Value $region
            $skusForRegion = $Response | Where-Object { $_.locations -contains $region }
            If ($skusForRegion) {
                Expand-NestedCollection -InputObjects $skusForRegion -Schema $propertyFilter
                Add-Member -InputObject $baseObject -MemberType NoteProperty -Name "skus" -Value $Skus 
            }
            else {
                "No SKUs found for region $region"
                $baseObject | Add-Member -MemberType NoteProperty -Name "skus" -Value @()
            }
            $outArray += $baseObject
        }
    }
    Add-Member -InputObject $resourceObject -MemberType NoteProperty -Name "Availability" -Value $outArray
    $Script:overAllObj += $resourceObject
    Out-JSONFile -Data $resourceObject -fileName $outPutFile
}

function Import-CurrentEnvironment {
    $SummaryFilePath = "$(Get-Location)\..\1-Collect\summary.json"
    # Check if the summary file exists and load it
    if (Test-Path $SummaryFilePath) {
        Write-Output "  Loading summary file: ../1-Collect/summary.json" | Out-Host
        $CurrentEnvironment = Get-Content -Path $SummaryFilePath -raw | ConvertFrom-Json -depth 10
    }
    else {
        Write-Output "File 'summary.json' not found in '../1-Collect/summary.json'."
        exit 1
    }
    # Check for empty SKUs and remove 'ResourceSkus' property if its value is 'N/A' in the current implementation data
    Write-Output "  Cleaning up implementation data" | Out-Host
    # $CurrentEnvironment = $CurrentEnvironment | ForEach-Object {
    #     if (((($_.ResourceSkus -is [array]) -and ($_.ResourceSkus.Count -eq 1) -and ($_.ResourceSkus[0] -eq "N/A"))) -or ($_.ResourceSkus -eq "N/A")) {
    #         $_ | Select-Object * -ExcludeProperty ResourceSkus
    #     }
    #     else { $_ }
    # }
    return @{
        Data = $CurrentEnvironment
    }
}


function Expand-CurrentToGlobal {
    # include a return statement to the function
    # This function expands the currently implemented resources to show their availability across all Azure regions,
    # without considering specific SKUs. It adds the AllRegions property to each resource in the AvailabilityMapping.
    Write-Output "Working on general availability mapping without SKU consideration"
    Write-Output "  Adding Azure regions with resource availability information"
    $Resources_TotalImplementations = $AvailabilityMapping.Count
    $Resources_CurrentImplementationIndex = 0
    foreach ($resource in $AvailabilityMapping) {
        $Resources_CurrentImplementationIndex++
        Write-Output ("    Processing resource type {0:D03} of {1:D03}: {2}" -f $Resources_CurrentImplementationIndex, $Resources_TotalImplementations, $resource.ResourceType)
        # Split the resource type string into namespace and type (keeping everything after the first "/" as the type)
        $splitParts = $resource.ResourceType -split "/", 2
        $ns = $splitParts[0]
        $rt = $splitParts[1]
        # Find the namespace object in Resources_All
        $nsObject = $Resources_All | Where-Object { $_.Namespace -ieq $ns }
        # Locate the corresponding resource type under that namespace
        $resourceTypeObject = $nsObject.ResourceTypes | Where-Object { $_.Type -ieq $rt }
        $MappedRegions = @()
        foreach ($Region in $Regions_All.Regions.value) {
            # Check if the region is available for the resource type or if it's global available
            $availability = if ($resourceTypeObject.Locations -contains $Region.name -or $resourceTypeObject.Locations -contains "Global") { "true" } else { "false" }
            $MappedRegions += New-Object -TypeName PSObject -Property @{
                region    = $Region.name
                available = $availability
            }
        }
        # Add or replace the AllRegions property with the mapped availability array
        $resource | Add-Member -Force -MemberType NoteProperty -Name AllRegions -Value $MappedRegions
    }
}

function Initialize-SKU2Region {
    # This function initializes the mapping of SKUs to regions for resource types that have implemented SKUs,
    # ensuring that the SKUs are added to the regions where the resource type is available.
    Write-Output "Working on availability SKU mapping"
    Write-Output "  Adding implemented SKUs to Azure regions with general availability"
    foreach ($resource in $AvailabilityMapping) {
        if ($resource.ImplementedSkus -and ($resource.ImplementedSkus[0] -ne "N/A")) {
            "implemented skus found for resource type $($resource.ResourceType) is not N/A"
            foreach ($Region in $resource.AllRegions) {
                if ($Region.available -eq "true") {
                    #$Region.region
                    # Add the SKUs property containing the array from the current resource object.
                    $Region | Add-Member -MemberType NoteProperty -Name SKUs -Value $resource.ImplementedSkus -Force
                }
            }
        }
    }
}
function Update-SKUProperties {
    param (
        [Parameter(Mandatory)] [string]$RegionName,
        [Parameter(Mandatory)] [pscustomobject]$Object,
        [Parameter(Mandatory)] [string]$availabilityStatus,
        [Parameter(Mandatory)] [string]$skuName
    )

    $region = $Object.AllRegions | Where-Object { $_.region -eq $RegionName }
    if (-not $region) {
        Write-Warning "Region '$RegionName' not found."
        return
    }

    Write-Host "Updating SKUs in region '$RegionName'..."
    $region.SKUs
    foreach ($sku in $region.SKUs) {
        #"$sku.skuName -eq $skuName"
        "Comparing SKU '$($sku.skuName)' with target SKU '$skuName'"
        $sku.skuName -eq $skuName | out-host
        if ($sku.skuName -eq $skuName ) {
            Write-Host "Setting availability of '$skuName' to '$availabilityStatus' in region '$RegionName'"
            Add-Member -InputObject $sku -MemberType NoteProperty -Name "available" -Value $availabilityStatus -Force
        }
    }
}


# Write-Headline "AVAILABILITY MAPPING TO CURRENT IMPLEMENTATION"
# # # Import current environment data from the summary file of script 1-Collect
# $AvailabilityMapping = (Import-CurrentEnvironment).Data
# # # Expand the current implementation to show availability across all Azure regions 
# Expand-CurrentToGlobal
# # # Initialize SKU to region mapping for resources that have implemented SKUs
# Initialize-SKU2Region
#  $AvailabilityMapping = $AvailabilityMapping | ForEach-Object { $PSItem | ConvertTo-Json -depth 10 | convertfrom-json }


# $resourcetype = "microsoft.compute/virtualMachines"
# $sku = "Standard_HB176rs_v4"
# # From $overAllobj get the resourceType
# $search = $overAllObj | Where-Object { $psitem.resourceType -eq $resourceType }
# $availScope = $availabilityMapping | where { $psitem.ResourceType -eq $resourcetype }
# $availScope | convertto-json -depth 5 | out-file 0.json
# Update-SKUProperties -RegionName "australiaeast" -Object $availScope -availabilityStatus true -skuName $SKU
# $availScope | convertto-json -depth 5 | out-file 1.json



# Turn the below into a function that takes resource types as parameters
# 1. check for implementedSKUs not -eq N/A in the availability mapping
# Create a function that takes resource type, overallObj and sku array as parameters (fix sku array from collect script first)


# Get this from availability mapping
# $resourcetype = "microsoft.compute/virtualMachines"
# $sku = "Standard_HB176rs_v4"
# Foreach ($cResource in $overAllObj) {
#     $availScope = $availabilityMapping | Where-Object { $psitem.ResourceType -eq $cResource.ResourceType }
#     $cResource.ResourceType
#     #fIXME consider if multiple skus are needed here
#     $sku = $cResource.ImplementedSkus[0]        
#     Foreach ($region in $cResource.Availability) { 
#         $regionCode = $region.RegionCode; 
#         $regionCode; 
#         If ($region.skus.count -ne 0) {
#             $skuFound = $region.skus | where-object { $Psitem.name -eq $sku }
#             If ($skuFound -ne $null) { 
#                 "SUCCESS: SKU $sku found in region $regionCode";
#                 Update-SKUProperties -RegionName $regionCode -Object $availScope -availabilityStatus true -skuName $sku
       
#             } 
#             else { 
#                 "SKU not found in region $regionCode"; 
#                 Update-SKUProperties -RegionName $regionCode -Object $availScope -availabilityStatus false -skuName $sku
#             }
#         }
#         else {
#             "No SKUs found for region $regionCode";
#             #if not already done nuke entire sku availability mapping for this region/resource type
#         }
#     }
#         $cResource.ResourceType
#     start-sleep 10
#  }

# # From $overAllobj get the resourceType
# $search = $overAllObj | Where-Object { $psitem.resourceType -eq $resourceType }
# $availScope = $availabilityMapping | where { $psitem.ResourceType -eq $resourcetype }
# Foreach ($region in $search.Availability) { 
#     $regionCode = $region.RegionCode; 
#     $regionCode; 
#     If ($region.skus.count -ne 0) {
#         $skuFound = $region.skus | where-object { $Psitem.name -eq $sku }
#         If ($skuFound -ne $null) { 
#             "SUCCESS: SKU $sku found in region $regionCode";
#             Update-SKUProperties -RegionName $regionCode -Object $availScope -availabilityStatus true -skuName $sku
       
#         } 
#         else { 
#             "SKU not found in region $regionCode"; 
#             Update-SKUProperties -RegionName $regionCode -Object $availScope -availabilityStatus false -skuName $sku
#         }
#     }
#     else {
#         "No SKUs found for region $regionCode";
#         #if not already done nuke entire sku availability mapping for this region/resource type
#     }
# }


# function Join-SKU2Region {
#     param (
#         [Parameter(Mandatory = $true)]
#         [object]$ResourceType
#     )
#     #Fixme consider doing this one as a loop based on resources in collect file
#     # This function processes the SKUs for a given resource type and joins them with the regions where they are available.
#     Write-Output "  Processing SKUs for resource type: $ResourceType"
#     foreach ($resource in $AvailabilityMapping) {
#         if ($resource.ResourceType -ieq $ResourceType) {
#             # Filter regions to those available and having a SKUs property
#             $Location_ValidRegions = $resource.AllRegions | Where-Object { $_.available -eq "true" -and $_.SKUs }
#             $TotalRegions = $Location_ValidRegions.Count
#             $CurrentRegionIndex = 0
#             foreach ($Region in $Location_ValidRegions) {
#                 $CurrentRegionIndex++
#                 Write-Output ("    Processing region {0:D3} of {1:D3}: {2}" -f $CurrentRegionIndex, $TotalRegions, $Region.region)
#                 $newSKUs = @()
#                 switch ($ResourceType) {
#                     { ($_ -eq "microsoft.compute/disks") -or ($_ -eq "microsoft.storage/storageaccounts") } {
#                         # Process SKUs for compute disks or storage accounts
#                         # # Check for compute disks is against storage account SKUs because because compute disks will be reported back in storage account SKU format
#                         foreach ($sku in $Region.SKUs) {
#                             $isAvailable = "false"
#                             foreach ($store in $StorageAccount_SKU) {
#                                 # Check if the SKU locations information contains the region and a matching SKU
#                                 if (($store.Location -ieq $Region.region) -and ($store.Name -eq $sku.name) -and ($store.Tier -eq $sku.tier)) {
#                                     $isAvailable = "true"
#                                     break  # Found a matching SKU; stop looping
#                                 }
#                             }
#                             # Create a new object for the SKU
#                             $newObj = New-Object PSObject -Property @{
#                                 name      = $sku.name
#                                 tier      = $sku.tier
#                                 available = $isAvailable
#                             }
#                             $newSKUs += $newObj
#                         }
#                     }
#                     "microsoft.compute/virtualMachines" {
#                         # Process SKUs for virtual machines
#                         foreach ($sku in $Region.SKUs) {
#                             # Convert SKU to string and extract the value using a regex
#                             $skuStr = [string]$sku
#                             if ($skuStr -match 'vmSize=(.+?)}') {
#                                 $skuName = $matches[1]
#                             }
#                             $isAvailable = "false"
#                             foreach ($vmSku in $VM_SKU) {
#                                 # Check if the SKU locations information contains the region and a matching SKU
#                                 if (($vmSku.Locations -contains $Region.region) -and ($vmSku.Name -eq $skuName)) {
#                                     $isAvailable = "true"
#                                     break  # Found a matching SKU; stop looping
#                                 }
#                             }
#                             # Create a new object for the SKU
#                             $newObj = New-Object PSObject -Property @{
#                                 name      = $skuName
#                                 available = $isAvailable
#                             }
#                             $newSKUs += $newObj
#                         }
#                     }
#                     "microsoft.sql/managedinstances" {
#                         # Process SKUs for SQL managed instances.
#                         $implSku = $resource.ImplementedSkus
#                         if ($implSku -and -not ($implSku -is [array])) {
#                             $implSku = @($implSku)
#                         }
#                         # Retrieve SQL managed instance SKU availability for the current region.
#                         $sqlRegionData = $SQL_ManagedInstance_SKU | Where-Object {
#                             ($_.Region -ieq $Region.region) -or ($_.RegionCode -ieq $Region.region)
#                         }
#                         foreach ($sku in $implSku) {
#                             $isAvailable = "false"
#                             if ($sqlRegionData) {
#                                 foreach ($dbSku in $sqlRegionData.skus) {
#                                     $matchName = ($dbSku.name -ieq $sku.name)
#                                     $matchTier = ($dbSku.tier -ieq $sku.tier)
#                                     $matchFamily = ($dbSku.family -ieq $sku.family)
#                                     # Capacity property can be ignored for managed instances because if all other properties match, it can be considered available.
#                                     if ($matchName -and $matchTier -and $matchFamily) {
#                                         $isAvailable = "true"
#                                         break  # Found a matching SKU; stop looping.
#                                     }
#                                 }
#                             }
#                             # Create a new object for the SKU.
#                             $newObj = New-Object PSObject -Property @{
#                                 name      = $sku.name
#                                 tier      = $sku.tier
#                                 family    = $sku.family
#                                 available = $isAvailable
#                             }
#                             $newSKUs += $newObj
#                         }
#                     }
#                     "microsoft.sql/servers/databases" {
#                         # Process SKUs for SQL Server databases
#                         $sqlRegionData = $SQL_Server_Database_SKU | Where-Object { $_.Region -ieq $Region.region }
#                         foreach ($sku in $Region.SKUs) {
#                             $isAvailable = "false"
#                             if ($sqlRegionData) {
#                                 foreach ($dbSku in $sqlRegionData.skus) {
#                                     $matchName = ($dbSku.name -eq $sku.name)
#                                     $matchTier = ($dbSku.tier -eq $sku.tier)
#                                     $matchCapacity = ($dbSku.capacity -eq $sku.capacity)
#                                     # Check for family property if it exists on either side.
#                                     $matchFamily = $true
#                                     if ($sku.PSObject.Properties["family"] -or $dbSku.PSObject.Properties["family"]) {
#                                         $matchFamily = ($dbSku.family -eq $sku.family)
#                                     }
#                                     if ($matchName -and $matchTier -and $matchCapacity -and $matchFamily) {
#                                         $isAvailable = "true"
#                                         break  # Found a matching SKU; stop looping.
#                                     }
#                                 }
#                             }
#                             # Create a new object for the SKU.
#                             $newObjProps = @{
#                                 name      = $sku.name
#                                 tier      = $sku.tier
#                                 capacity  = $sku.capacity
#                                 available = $isAvailable
#                             }
#                             # Family is not always present, so check if it exists before adding
#                             if ($sku.PSObject.Properties["family"]) {
#                                 $newObjProps.Add("family", $sku.family)
#                             }
#                             $newObj = New-Object PSObject -Property $newObjProps
#                             $newSKUs += $newObj
#                         }
#                     }
#                     default {
#                         Write-Output "    No SKUs found for this resource type."
#                     }
#                 }
#                 # Replace the original SKUs array with the updated one
#                 $Region.SKUs = $newSKUs
#             }
#         }
#     }
# }

# Main script starts here
clear-host
# Start of resource and SKU availability retrieval
$starttime = Get-Date
Write-Headline "RETRIEVING ALL AVAILABILITIES IN THIS SUBSCRIPTION $starttime"
# Initialize the REST API connection
$subscriptionId = (Get-AzContext).Subscription.Id
$uriRoot = "https://management.azure.com/subscriptions/$subscriptionId"
$Regions_All = Import-Region
$Resources_All = (Import-Provider -uriRoot $uriRoot).Data
# Import all Azure regions


# fIXME loop to get only collected resources
# # Import VM SKUs
$script:overAllObj = @()
Get-ResourceType -ResourceType "microsoft.compute/virtualmachines" -outPutFile "VM_SKUsnew.json"
Get-ResourceType -ResourceType "microsoft.sql/servers/databases" -outPutFile "SQL_Server_Database_SKUsnew.json"
# #Get-ResourceType -ResourceType "microsoft.sql/managedinstances" -outPutFile "SQL_Managed_Instance_SKUsnew.json"
# Get-ResourceType -ResourceType "microsoft.storage/storageaccounts" -outPutFile "Storage_Account_SKUs.json" -regionalApiCall $false
# Out-JSONFile -Data $script:overAllObj -fileName "All_Resource_SKUs.json"
# #Get-ResourceType -ResourceType "microsoft.compute/disks" -outPutFile "Disk_SKUs.json"
# #Fixme consider if [System.GC]::Collect() is needed here to free memorylogo
# # # Start of availability mapping to current implementation
Write-Headline "AVAILABILITY MAPPING TO CURRENT IMPLEMENTATION"
# # Import current environment data from the summary file of script 1-Collect
$AvailabilityMapping = (Import-CurrentEnvironment).Data
# # Expand the current implementation to show availability across all Azure regions 
Expand-CurrentToGlobal
# # Initialize SKU to region mapping for resources that have implemented SKUs
Initialize-SKU2Region
$AvailabilityMapping = $AvailabilityMapping | ForEach-Object { $PSItem | ConvertTo-Json -depth 10 | convertfrom-json }
Foreach ($cResource in $overAllObj) {
    $availScope = $availabilityMapping | Where-Object { $psitem.ResourceType -eq $cResource.ResourceType }
    $cResource.ResourceType
    #fIXME consider if multiple skus are needed here
    $sku = $availScope.ImplementedSkus[0]
    Foreach ($region in $cResource.Availability) { 
        $regionCode = $region.RegionCode; 
        $regionCode; 
        If ($region.skus.count -ne 0) {
            # fixme need to modify generation of the $overAllObj to include the skuName property for all resource types (and change the below accordingly)
            $sku.skuName
            $skuFound = $region.skus | where-object { $Psitem.skuName -eq $sku.skuName}
            If ($skuFound -ne $null) { 
                "SUCCESS: SKU $sku found in region $regionCode";
                Update-SKUProperties -RegionName $regionCode -Object $availScope -availabilityStatus true -skuName $sku.skuName
       
            } 
            else { 
                "SKU not found in region $regionCode"; 
                Update-SKUProperties -RegionName $regionCode -Object $availScope -availabilityStatus false -skuName $sku.skuName
            }
        }
        else {
            "No SKUs found for region $regionCode";
            #if not already done nuke entire sku availability mapping for this region/resource type
        }
    }
    $cResource.ResourceType
    #start-sleep 10
}
Out-JSONFile -Data $AvailabilityMapping -fileName "Availability_Mapping_Final.json"

# fixme
# change the join sku function to use the $overAllobj to set in specific sku availability per resource/region
# # Availability SKU mappings
# Join-SKU2Region -ResourceType "microsoft.compute/disks"
#Join-SKU2Region -ResourceType "microsoft.compute/virtualMachines"


# Join-SKU2Region -ResourceType "microsoft.sql/managedinstances"
# Join-SKU2Region -ResourceType "microsoft.sql/servers/databases"
# Join-SKU2Region -ResourceType "microsoft.storage/storageaccounts"
# # Save the availability mapping to a JSON file
# Out-JSONFile -Data $AvailabilityMapping -fileName "Availability_Mapping.json"
$endtime = Get-Date
$minutes = (New-TimeSpan -Start $starttime -End $endtime).TotalMinutes
Write-Headline "Ending script $endtime after $minutes minutes"