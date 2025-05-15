<#
.SYNOPSIS
    Exports Azure resource availability comparison between regions to Excel or CSV.

.DESCRIPTION
    This script reads the output from Get-AvailabilityInformation.ps1,
    structures it, and exports to an Excel or CSV file for review.

.PARAMETER InputPath
    Path to the JSON or CSV file containing availability information.

.PARAMETER OutputPath
    Path where the report should be saved.

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

# Optional: Format or validate data
$formattedData = $data | Select-Object `
    ResourceName, `
    ResourceType, `
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