## Export Script

This script generates a formatted Excel or CSV report based on the output from the previous check script. The report includes detailed information for each service, such as:
- Resource name and type
- SKU (if available)
- Origin and target regions
- Availability status in the target region
This allows for easy analysis of service compatibility across regions.

To use the script do the following from a powershell command line:
Navigate to the 7-Export folder and run the script using `.\Get-Report.ps1 -InputPath ".\input.json" -OutputPath ".\Report" -ExportExcel`. The script will generate a xlsx file in the 7-Export folder with the name you specific.

Parameters:
- -InputPath (Required): Path to the JSON or CSV file with availability results.
- -OutputPath (Required): Desired path (without extension) for the exported file.
- -ExportExcel (Optional): Use this flag to export as .xlsx instead of .csv. Requires the ImportExcel PowerShell module.

Dependencies:
- PowerShell 5.1+ or PowerShell Core
- Azure Az Module (Install-Module Az)
- ImportExcel Module (for Excel export)

Example Workflow:
- Step 1: Collect deployed resource data
`.\Get-AzureServices.ps1 -scopeType singleSubscription -subscriptionId "<SUBSCRIPTION_ID>"`
- Step 2: Check availability in target region
`.\Get-AvailabilityInformation.ps1`
- Step 3: Export final report
`.\Get-Report.ps1 -InputPath .\availabilityData.json -OutputPath .\Report -ExportExcel`
