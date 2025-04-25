## Availability check script

This script evaluates the availability of Azure services, resources, and SKUs across different regions. When combined with the output from the 1-Collect script, it provides a comprehensive overview of potential migration destinations, identifying feasible regions and the reasons for their suitability or limitations, such as availability constraints per region.

To use the script do the following from a powershell command line:
1. Log on to Azure using `Connect-AzAccount` and select the appropriate subscription using `Select-AzSubscription`.
2. Run `.\Get-AzureServices.ps1` from `1-Collect` folder.
3. Get sure that the output files are successful generated in the `1-Collect` folder with the name `resources.json` as well as `summary.json`.
4. Navigate to the 2-AvailabilityCheck folder and run the script using `.\Get-AvailabilityInformation.ps1`. The script will generate a report in the `2-AvailabilityCheck` folder with **TBD**