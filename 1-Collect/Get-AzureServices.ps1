<#.SYNOPSIS
    Assess Azure resources by querying Resource Graph and extracting specific properties or metadata.

.DESCRIPTION
    This script queries Azure Resource Graph to retrieve information about resources within a specified scope 
    (single subscription, resource group, or multiple subscriptions). It processes the results to extract 
    additional properties or metadata based on predefined configurations and outputs the results to a JSON file.

.PARAMETER scopeType
    Specifies the scope type to run the query against. Valid values are 'singleSubscription', 'resourceGroup', 
    or 'multiSubscription'. Default is 'singleSubscription'.

.PARAMETER subscriptionId
    The subscription ID to run the query against. If not provided, the current Azure context's subscription ID is used.

.PARAMETER resourceGroupName
    The name of the resource group to run the query against. Only applicable when scopeType is 'resourceGroup'.

.PARAMETER workloadFile
    The path to a JSON file containing subscription details. Used for multi-subscription scenarios.

.PARAMETER outputFile
    The name of the output file where the results will be exported. Default is "test.json".

.FUNCTION Get-SingleData
    Queries Azure Resource Graph for resources within a single subscription and retrieves all results, 
    handling pagination if necessary.

.FUNCTION Get-Property
    Extracts a specific property from a given object and assigns it to a global variable.

.FUNCTION Get-rType
    Retrieves resource-specific metadata or properties based on a predefined JSON configuration file.

.FUNCTION Get-Data
    Processes extracted properties or executes commands to retrieve additional data for a resource.

.FUNCTION Get-Method
    Determines the appropriate method to retrieve resource-specific data based on the resource type and flag type.

.EXAMPLE
    PS C:\> .\assess_resources.ps1 -scopeType singleSubscription -subscriptionId "12345678-1234-1234-1234-123456789abc"
    Runs the script for a single subscription with the specified subscription ID and outputs the results to the default file.

.EXAMPLE
    PS C:\> .\assess_resources.ps1 -scopeType resourceGroup -resourceGroupName "MyResourceGroup"
    Runs the script for a specific resource group within the current subscription and outputs the results to the default file.

.EXAMPLE
    PS C:\> .\assess_resources.ps1 -scopeType multiSubscription -workloadFile "subscriptions.json" -outputFile "output.json"
    Runs the script for multiple subscriptions defined in the workload file and outputs the results to "output.json".


.OUTPUTS
    JSON file containing the queried resource data and extracted properties.

.NOTES
    - Requires Azure PowerShell module to be installed and authenticated.
    - Ensure the JSON configuration files (e.g., dataReplication.json, dataSize.json etc) are present in the "modules" directory.
    - Handles pagination for large datasets returned by Azure Resource Graph queries.
#>

param(
    [Parameter(Mandatory = $false)] [ValidateSet('singleSubscription', 'resourceGroup', 'multiSubscription')] [string] $scopeType = 'singleSubscription', # scope type to run the query against
    [Parameter(Mandatory = $false)] [string] $subscriptionId, # Subscription ID to run the query against
    [Parameter(Mandatory = $false)] [string] $resourceGroupName, # resource group to run the query against
    [Parameter(Mandatory = $false)] [string] $workloadFile, # JSON file containing subscriptions
    [Parameter(Mandatory = $false)] [string] $outputFile = "resources.json" # Excel file to export the results to
)

Function Get-SingleData {
    param(
        [Parameter(Mandatory = $true)] [string] $query
    )
    $resultSet = @()
    $response = Search-AzGraph -Query $query -First 1000
    $resultSet += $response
    # If a skip token is returned, there are more results to fetch
    while ($null -ne $response.SkipToken) {
        $response = Search-AzGraph -Query $query -First 1000 -SkipToken $response.SkipToken
        $resultSet += $response
    }
    $Global:baseresult = $resultSet
}

Function Get-MultiLoop {
    param(
        [Parameter(Mandatory = $true)] [string] $workloadFile
    )
    # Open workload file and get subscription IDs
    $workloads = Get-Content -Path $workloadFile -raw | ConvertFrom-Json
    $subscriptionIds = $workloads.Subscriptions
    $tempArray = @()
    foreach ($subscription in $workloads.subscriptions) {
        $basequery = "resources | where subscriptionId == '$subscription'"
        Get-SingleData -query $basequery
        $tempArray += $Global:baseresult
    }
    $Global:baseresult = $tempArray
}

Function Get-Property {
    param(
        [Parameter(Mandatory = $true)] [pscustomobject] $object,
        [Parameter(Mandatory = $true)] [string] $property,
        [Parameter(Mandatory = $true)] [string] $outputVarName
    )
    #Reset variable to avoid conflicts
    Set-Variable -Name $outputVarName -Value $null -Scope Global
    Set-Variable -Name $outputVarName -Value $object -Scope Global
    If ($property -match "\.+") {
        foreach ($part in $property -split '\.') {
            $object = $object.$part
        }
    }
    else {
        $object = $object.$property
    }
    Set-Variable -Name $outputVarName -Value $object -Scope Global
}

Function run-CmdLine {
    param(
        [Parameter(Mandatory = $true)] [string] $cmdLine,
        [Parameter(Mandatory = $true)] [string] $outputVarName
    )
    #Reset variable to avoid conflicts
    Set-Variable -Name $outputVarName -Value $null -Scope Global
    $cmdResult = Invoke-Expression -Command $cmdLine
    # if result is a number linmit to 2 decimal places
    if ($cmdResult -is [int] -or $cmdResult -is [double]) {
        $cmdResult = "{0:N2}" -f $cmdResult
    }
    Set-Variable -Name $outputVarName -Value $cmdResult -Scope Global
}

function Get-rType {
    param (
        [Parameter(Mandatory = $true)] [string] $filePath,
        [Parameter(Mandatory = $true)] [pscustomobject] $object,
        [Parameter(Mandatory = $true)] [string] $outputVarName,
        [Parameter(Mandatory = $true)] [string] $resourceType
    )
    $json = Get-Content -Path $filePath | ConvertFrom-Json -depth 100
    $propertyExists = $json | Where-Object { $psItem.resourceType -eq $resourceType } | Select-Object -ExpandProperty isContainedInOriginalGraphOutput
    if ($propertyExists) {
        #"Property for $outputVarName for $resourceType indicated in $filePath"
        $property = $json | Where-Object { $psItem.resourceType -eq $resourceType } | Select-Object -ExpandProperty property
        Get-Property -object $object -property $property -outputVarName $outputVarName
    }
    elseif ($propertyExists -eq $false) {
        #"Property for $outputVarName for $resourceType not indicated in $filePath, try to get cmdLine"
        $cmdLine = $json | Where-Object { $psItem.resourceType -eq $resourceType } | Select-Object -ExpandProperty cmdLine
        run-CmdLine -cmdLine $cmdLine -outputVarName $outputVarName  
    }
    else {
        #"Neither property nor cmdline for $outputVarName for $resourceType is indicated in $filepath"
        Set-Variable -Name $outputVarName -Value "N/A" -Scope Script
    }

}

Function Get-Method {
    Param(
        [Parameter(Mandatory = $true)] [string] $resourceType,
        [Parameter(Mandatory = $true)][ValidateSet('storageReplication', 'dataSize', "ipConfig", "Sku")] [string] $flagType,
        [Parameter(Mandatory = $true)] [pscustomobject] $object
    )
    switch ($flagType) {
        'storageReplication' { Get-rType -filePath .\modules\dataReplication.json -object $object -outputVarName "storageReplication" -resourceType $resourceType }
        'dataSize' { Get-rType -filePath .\modules\dataSize.json -object $object -outputVarName "dataSize" -resourceType $resourceType }
        'ipConfig' { Get-rType -filePath .\modules\ipConfig.json -object $object -outputVarName "ipAddress" -resourceType $resourceType }
        'Sku' { Get-rType -filePath .\modules\sku.json -object $object -outputVarName "sku" -resourceType $resourceType }
    }
}

# Main script starts here
$outputArray = @()

Switch ($scopeType) {
    'singleSubscription' {
        $baseQuery = "resources"
        if (!$subscriptionId) {
            $subscriptionId = (Get-AzContext).Subscription.id
        }
        $baseQuery = "resources | where subscriptionId == '$subscriptionId'"
        Get-SingleData -query $baseQuery
    }
    'resourceGroup' {
        # KQL Query to get all resources in a specific resource group and subscription
        if (!$subscriptionId) {
            $subscriptionId = (Get-AzContext).Subscription.id
        }
        $baseQuery = "resources | where resourceGroup == '$resourceGroupName' and subscriptionId == '$subscriptionId'"
        Get-SingleData -query $baseQuery
    }
    'multiSubscription' {
        "multiple subscriptions"
        Get-MultiLoop -workloadFile $workloadFile
    }
}
$baseResult | ForEach-Object {
    $resourceType = $PSItem.type
    $resourceName = $PSItem.name
    $resourceLocation = $PSItem.location
    $resourceSubscriptionId = $PSItem.subscriptionId
    $resourceID = $PSItem.id
    $resourceZones = $PSItem.zones
    if ($PSItem.sku -ne $null) {
        $sku = $PSItem.sku
    }
    elseif ($PSItem.properties.sku -ne $null) {
        $sku = $PSItem.properties.sku
    }
    else {
        Get-Method -resourceType $resourceType -flagType "Sku" -object $PSItem
    }
    Get-Method -resourceType $resourceType -flagType "storageReplication" -object $PSItem
    Get-Method -resourceType $resourceType -flagType "dataSize" -object $PSItem
    Get-Method -resourceType $resourceType -flagType "ipConfig" -object $PSItem
    $outObject = [PSCustomObject] @{
        ResourceType           = $resourceType
        ResourceName           = $resourceName
        ResourceLocation       = $resourceLocation
        ResourceSubscriptionId = $resourceSubscriptionId
        ResourceID             = $resourceID
        ResourceSku            = $sku
        ResourceZones          = $resourceZones
        storageReplication     = $storageReplication
        dataSizeGB             = $dataSize
        ipAddress              = $ipAddress
    }
    $outputArray += $outObject
}
$outputArray | ConvertTo-Json -Depth 100 | Out-File -FilePath $outputFile
$groupedResources = $outputArray | Group-Object -Property ResourceType
$summary = @()
foreach ($group in $groupedResources) {                     
    $resourceType = $group.Name
    $uniqueLocations = $group.Group | Select-Object -Property ResourceLocation -Unique | Select-Object -ExpandProperty ResourceLocation
    if ($uniqueLocations -isnot [System.Array]) {
        $uniqueLocations = @($uniqueLocations)
    }
    If ($group.Group.ResourceSku -ne 'N/A') {

        $uniqueSkus = $group.Group.ResourceSku | Select-Object * -Unique
        $summary += [PSCustomObject]@{ResourceCount = $group.Count; ResourceType = $resourceType; ResourceSkus = $uniqueSkus; AzureRegions = $uniqueLocations }
    }
    Else {
        $summary += [PSCustomObject]@{ResourceCount = $group.Count; ResourceType = $resourceType; ResourceSkus = @("N/A"); AzureRegions = $uniqueLocations }
    }
}
$summary | ConvertTo-Json -Depth 100 | Out-File -FilePath "summary.json"