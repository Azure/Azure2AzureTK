<#
.SYNOPSIS
    Exports Azure resource availability comparison between regions to Excel or CSV.

.DESCRIPTION
    Reads the output from Get-AvailabilityInformation.ps1, structures it, and
    exports to an Excel or CSV file, including SKU details.

.PARAMETER InputPath
    Path to the JSON or CSV file containing availability information.

.PARAMETER OutputPath
    Path where the report should be saved (without extension).

.PARAMETER ExportExcel
    If specified, exports to .xlsx (requires ImportExcel module), otherwise .csv.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [switch]$ExportExcel
)

# Import data
try {
    if ($InputPath.EndsWith(".json")) {
        $data = Get-Content $InputPath | ConvertFrom-Json
    } elseif ($InputPath.EndsWith(".csv")) {
        $data = Import-Csv $InputPath
    } else {
        throw "Unsupported input format. Please provide a JSON or CSV file."
    }
} catch {
    Write-Error "Failed to read input data: $_"
    exit 1
}

# Format data for export (include SKU if it exists)
$formattedData = $data | Select-Object `
    ResourceName, `
    ResourceType, `
    Sku, `
    OriginRegion, `
    TargetRegion, `
    IsAvailableInTargetRegion

# Export to Excel or CSV
if ($ExportExcel) {
    if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
        Write-Warning "ImportExcel module is not installed. Falling back to CSV."
        $formattedData | Export-Csv -Path "$OutputPath.csv" -NoTypeInformation
    } else {
        Import-Module ImportExcel
        $formattedData | Export-Excel -Path "$OutputPath.xlsx" -AutoSize -TableName "AvailabilityReport"
    }
} else {
    $formattedData | Export-Csv -Path "$OutputPath.csv" -NoTypeInformation
}

Write-Host "Report exported to: $OutputPath"