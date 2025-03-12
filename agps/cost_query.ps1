<#
.SYNOPSIS
    Take a collection of given subscription IDs and return the cost incurred during previous months,
    grouped as needed. For this we use the Microsoft.CostManagement provider of each subscription.
    Requires Az.CostManagement module
    PS1> Install-Module -Name Az.CostManagement

.PARAMETER ParameterName
    $startDate    (optional)  : The start date of the period to be examined (default is the first day of the month, 6 months ago)
    $endDate      (optional)  : The end date of the period to be examined (default is the last day of the previous month)
    $workloadFile (optional)  : A JSON file containing a list subscriptions grouped by workload
    $outputFile   (optional)  : The Excel file to export the results to, otherwise displayed in the console
      Important: The output file must not be encrypted (sensitivity label applied), otherwise the Export-Excel cmdlet will fail

.INPUTS
    None

.OUTPUTS
    An Excel file or table showing the cost history of the given subscriptions over the requested period

.EXAMPLE
    .\cost_query.ps1
    .\cost_query.ps1 -startDate "2023-01-01" -endDate "2023-06-30" -workloadFile "subscriptions.json" -outputFile "CostManagementQuery.xlsx"

.NOTES
    Documentation links:
    https://learn.microsoft.com/en-us/rest/api/cost-management/query/usage
    https://learn.microsoft.com/en-us/powershell/module/az.costmanagement/invoke-azcostmanagementquery

    Sample JSON input file:

[
    {
        "Workload": "SAP",
        "Subscriptions": [
            "<Guid>",
            "<Guid>"
        ]
    },
    {
        "Workload": "Citrix",
        "Subscriptions": [
            "<Guid>",
            "<Guid>"
        ]
    },
    {
        "Workload": "PLM",
        "Subscriptions": [
            "<Guid>"
        ]
    }
]

#>

param (
    [string]$startDate = (Get-Date).AddMonths(-1).ToString("yyyy-MM-01"),               # the first day of the previous month
    [string]$endDate = (Get-Date).AddDays(-1 * (Get-Date).Day).ToString("yyyy-MM-dd"),  # the last day of the previous month
    [string]$workloadFile = "subscriptions.json",                                       # JSON file containing subscriptions
    [string]$outputFile                                                                 # file to export to, if any
)

# Label used as the tab name and table name in Excel
$label = "CostHistoryDetailed"

# Timeframe
# Supported types are BillingMonthToDate, Custom, MonthToDate, TheLastBillingMonth, TheLastMonth, WeekToDate
$timeframe = "Custom"

# Granularity
# Supported types are Daily and Monthly so far. Omit just to get the total cost.
$granularity = "Monthly"

# Type
# Supported types are Usage (deprecated), ActualCost, and AmortizedCost
# https://stackoverflow.com/questions/68223909/in-the-azure-consumption-usage-details-api-what-is-the-difference-between-the-m
$type = "AmortizedCost"          

# Scope
<# Scope can be:
https://learn.microsoft.com/en-us/powershell/module/az.costmanagement/invoke-azcostmanagementquery?view=azps-10.1.0#-scope

Subscription scope       : /subscriptions/{subscriptionId}
Resource group scope     : /subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}
Billing account scope    : /providers/Microsoft.Billing/billingAccounts/{billingAccountId}
Department scope         : /providers/Microsoft.Billing/billingAccounts/{billingAccountId}/departments/{departmentId}
Enrollment account scope : /providers/Microsoft.Billing/billingAccounts/{billingAccountId}/enrollmentAccounts/{enrollmentAccountId}
Management group scope   : /providers/Microsoft.Management/managementGroups/{managementGroupId}
Billing profile scope    : /providers/Microsoft.Billing/billingAccounts/{billingAccountId}/billingProfiles/{billingProfileId}
Invoice section scope    : /providers/Microsoft.Billing/billingAccounts/{billingAccountId}/billingProfiles/{billingProfileId}/invoiceSections/{invoiceSectionId}
Partner scope            : /providers/Microsoft.Billing/billingAccounts/{billingAccountId}/customers/{customerId}

For a customer with a Microsoft Enterprise Agreement or Microsoft Customer Agreement, billing account scope is recommended. #>
#$scope = "/subscriptions/2228b515-e1c7-4457-83ba-87888ec1efce"

$workloads = @()

# Read the content of the workloads file
$jsonContent = Get-Content -Path $workloadFile -Raw

# Convert the JSON content to a PowerShell object
$workloads = $jsonContent | ConvertFrom-Json
$subscriptionIds = $workloads.Subscriptions

# Grouping
<# Dimensions for grouping the output. Valid dimensions for grouping are:

AccountName
BenefitId
BenefitName
BillingAccountId
BillingMonth
BillingPeriod
ChargeType
ConsumedService
CostAllocationRuleName
DepartmentName
EnrollmentAccountName
Frequency
InvoiceNumber
MarkupRuleName
Meter
MeterCategory
MeterId
MeterSubcategory
PartNumber
PricingModel
PublisherType
ReservationId
ReservationName
ResourceGroup
ResourceGroupName
ResourceGuid
ResourceId
ResourceLocation
ResourceType
ServiceName
ServiceTier
SubscriptionId
SubscriptionName
#>
$grouping = @(
    @{
        type = "Dimension"
        name = "BillingMonth"
    },
    @{
        type = "Dimension"
        name = "SubscriptionId"
    },
    @{
        type = "Dimension"
        name = "MeterCategory"
    },
    @{
        type = "Dimension"
        name = "MeterSubcategory"
    },
    @{
        type = "Dimension"
        name = "Meter"
    }
)

# Aggregation
# Supported types are Sum, Average, Minimum, Maximum, Count, and Total.
$aggregation = @{
    PreTaxCost = @{
        type = "Sum"
        name = "PreTaxCost"
    }
}

$table = @()

# Loop through subscription IDs
for ($subIndex = 0; $subIndex -lt $subscriptionIds.Count; $subIndex++) {
    $scope = "/subscriptions/$($subscriptionIds[$subIndex])"
    Write-Output "Querying subscription $(${subIndex}+1) of $($subscriptionIds.Count): $($subscriptionIds[$subIndex])"

    # We can filter if needed, but it's not necessary for this query
    # In this script we use subscription ID as a filter, even though presumably subscription A's data is
    # not available to the Microsoft.CostManagement provider of any other subscription.
    #$dimensions = New-AzCostManagementQueryComparisonExpressionObject -Name 'SubscriptionId' -Value $subscriptionIds[$subIndex] -Operator 'In'
    #$filter = New-AzCostManagementQueryFilterObject -Dimensions $dimensions

    $queryResult = Invoke-AzCostManagementQuery `
        -Scope $scope `
        -Timeframe $timeframe `
        -Type $type `
        -TimePeriodFrom $startDate `
        -TimePeriodTo $endDate `
        -DatasetGrouping $grouping `
        -DatasetAggregation $aggregation
        #-DatasetFilter $filter `
    # Convert the query result into a table
    for ($i = 0; $i -lt $queryResult.Row.Count; $i++) {
        $row = [PSCustomObject]@{}
        for ($j = 0; $j -lt $queryResult.Column.Count; $j++) {
            $row | Add-Member -MemberType NoteProperty -Name $queryResult.Column.Name[$j] -Value $queryResult.Row[$i][$j]
        }
        $table += $row
    }
    # For testing - limit to one subscription
    # $subIndex = $subscriptionIds.Count
}

# If an output file is specified, export the table to Excel, otherwise display it
if ($PSBoundParameters.ContainsKey('outputFile')) {
    #$table | Export-Csv -Path .\$outputFile #-NoTypeInformation
    $table | Export-Excel -WorksheetName $label -TableName $label -Path .\$outputFile
    Write-Output "$($table.Count) rows written to $outputFile"
} else {
    $table | Format-Table -AutoSize
}
