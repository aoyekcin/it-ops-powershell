<#
.SYNOPSIS
    Lists Intune-managed devices that are non-compliant or have not synced recently.

.DESCRIPTION
    Uses Microsoft Graph PowerShell to export a CSV of managed devices that need attention:
      - compliance state is not "compliant", or
      - the last check-in (sync) is older than -StaleSyncDays
    Useful as a weekly hygiene report for endpoint and security teams.

.PARAMETER StaleSyncDays
    Devices that have not synced for this many days are flagged. Default: 14.

.PARAMETER OperatingSystem
    Optional filter, e.g. "Windows", "iOS", "Android", "macOS".

.PARAMETER OutputFolder
    Folder for the CSV report. Defaults to the current folder.

.EXAMPLE
    .\Get-IntuneNoncompliantDevice.ps1 -OperatingSystem Windows -StaleSyncDays 30

.NOTES
    Requires: Microsoft.Graph.Authentication and Microsoft.Graph.DeviceManagement modules,
    and the DeviceManagementManagedDevices.Read.All permission. Read-only.
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 365)]
    [int]$StaleSyncDays = 14,

    [ValidateSet('Windows', 'iOS', 'Android', 'macOS')]
    [string]$OperatingSystem,

    [ValidateScript({ Test-Path -Path $_ -PathType Container })]
    [string]$OutputFolder = (Get-Location).Path
)

Connect-MgGraph -Scopes 'DeviceManagementManagedDevices.Read.All' -NoWelcome -ErrorAction Stop

$devices = Get-MgDeviceManagementManagedDevice -All -ErrorAction Stop
if ($OperatingSystem) {
    $devices = $devices | Where-Object { $_.OperatingSystem -eq $OperatingSystem }
}

$cutoff = (Get-Date).AddDays(-$StaleSyncDays)
$attention = foreach ($device in $devices) {
    $issues = @()
    if ($device.ComplianceState -ne 'compliant') { $issues += "Compliance: $($device.ComplianceState)" }
    if ($device.LastSyncDateTime -lt $cutoff) { $issues += "No sync for $StaleSyncDays+ days" }

    if ($issues) {
        [PSCustomObject]@{
            DeviceName        = $device.DeviceName
            UserPrincipalName = $device.UserPrincipalName
            OperatingSystem   = $device.OperatingSystem
            OsVersion         = $device.OsVersion
            ComplianceState   = $device.ComplianceState
            LastSync          = $device.LastSyncDateTime
            Ownership         = $device.ManagedDeviceOwnerType
            Issues            = $issues -join '; '
        }
    }
}

$reportPath = Join-Path -Path $OutputFolder -ChildPath ("intune-attention-{0:yyyyMMdd}.csv" -f (Get-Date))
$attention | Sort-Object -Property LastSync | Export-Csv -Path $reportPath -NoTypeInformation -Encoding UTF8

$attention | Group-Object -Property ComplianceState | Select-Object -Property Name, Count | Format-Table -AutoSize
Write-Output "Devices checked: $(@($devices).Count). Needing attention: $(@($attention).Count). Report: $reportPath"
