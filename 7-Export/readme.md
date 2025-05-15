## Export Script

This script generates a formatted Excel or CSV report based on the output from the previous check script. The report includes detailed information for each service, such as:
* Resource name and type
* SKU (if available)
* Origin and target regions
* Availability status in the target region
This allows for easy analysis of service compatibility across regions.

To use the script do the following from a powershell command line:
Navigate to the 7-Export folder and run the script using `.\Get-Report.ps1 -InputPath ".\input.json" -OutputPath ".\Report" -ExportExcel`. The script will generate a xlsx file in the 7-Export folder with the name you specific.
