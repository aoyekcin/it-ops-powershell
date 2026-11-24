<#
.SYNOPSIS
    Reports (and optionally disables) computer accounts that have not logged on for a given number of days.

.DESCRIPTION
    Stale computer accounts clutter AD, inflate license and security reports, and are a security risk.
    This script lists enabled computer accounts that have been inactive for longer than -InactiveDays,
    exports them to CSV, and can disable them when -Disable is used (with -WhatIf / -Confirm support).

    Note: LastLogonDate is replicated with a delay of up to ~14 days by design,
    so use a generous threshold (90 days or more).

.PARAMETER InactiveDays
    Number of days without logon after which a computer counts as stale. Default: 90.

.PARAMETER SearchBase
    Optional OU to limit the search, e.g. "OU=Stores,DC=contoso,DC=com".

.PARAMETER Disable
    Disable the stale computer accounts after reporting them.

.PARAMETER ReportPath
    Where to write the CSV report.

.EXAMPLE
    .\Get-StaleADComputer.ps1 -InactiveDays 120 -SearchBase "OU=Stores,DC=contoso,DC=com"

.EXAMPLE
    .\Get-StaleADComputer.ps1 -InactiveDays 120 -Disable -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateRange(30, 3650)]
    [int]$InactiveDays = 90,

    [string]$SearchBase,

    [switch]$Disable,

    [string]$ReportPath = (Join-Path -Path (Get-Location) -ChildPath ("stale-computers-{0:yyyyMMdd}.csv" -f (Get-Date)))
)

Import-Module ActiveDirectory -ErrorAction Stop

$search = @{
    AccountInactive = $true
    ComputersOnly   = $true
    TimeSpan        = New-TimeSpan -Days $InactiveDays
    ErrorAction     = 'Stop'
}
if ($SearchBase) {
    $search.SearchBase = $SearchBase
}

$stale = Search-ADAccount @search |
    Where-Object { $_.Enabled } |
    ForEach-Object {
        Get-ADComputer -Identity $_.DistinguishedName -Properties LastLogonDate, OperatingSystem, Description
    } |
    Select-Object -Property Name, OperatingSystem, LastLogonDate,
        @{ Name = 'DaysInactive'; Expression = { if ($_.LastLogonDate) { [int]((Get-Date) - $_.LastLogonDate).TotalDays } else { $null } } },
        Description, DistinguishedName |
    Sort-Object -Property LastLogonDate

$stale | Export-Csv -Path $ReportPath -NoTypeInformation -Encoding UTF8
Write-Output "Found $(@($stale).Count) stale computer account(s). Report: $ReportPath"

if ($Disable) {
    foreach ($computer in $stale) {
        if ($PSCmdlet.ShouldProcess($computer.Name, "Disable computer account (inactive $($computer.DaysInactive) days)")) {
            try {
                Disable-ADAccount -Identity $computer.DistinguishedName -ErrorAction Stop
                Set-ADComputer -Identity $computer.DistinguishedName -Description ("Disabled {0:yyyy-MM-dd} - inactive {1} days" -f (Get-Date), $computer.DaysInactive) -ErrorAction Stop
            }
            catch {
                Write-Warning "$($computer.Name): $($_.Exception.Message)"
            }
        }
    }
}
