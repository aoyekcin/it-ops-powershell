<#
.SYNOPSIS
    Creates Active Directory user accounts from a CSV file (onboarding).

.DESCRIPTION
    Reads new hires from a CSV file and, for each row:
      - creates the user in the given OU (skips users that already exist)
      - sets a temporary password that must be changed at first logon
      - adds the user to the listed groups
    Writes a result report (CSV) with the outcome of every row.

    Supports -WhatIf and -Confirm, so you can preview every change first.

.PARAMETER CsvPath
    Path to the input CSV. Required columns:
    GivenName, Surname, SamAccountName, Department, Title, OU, Groups
    "Groups" is a semicolon-separated list of group names (can be empty).
    See samples/new-users.sample.csv.

.PARAMETER UpnSuffix
    UPN domain suffix, for example "contoso.com".

.PARAMETER ReportPath
    Where to write the result report. Defaults to the current folder.

.EXAMPLE
    .\New-ADUserFromCsv.ps1 -CsvPath .\new-users.csv -UpnSuffix contoso.com -WhatIf
    Shows what would be created, without changing anything.

.EXAMPLE
    .\New-ADUserFromCsv.ps1 -CsvPath .\new-users.csv -UpnSuffix contoso.com
    Prompts once for a temporary password and creates the accounts.

.NOTES
    Requires: ActiveDirectory module (RSAT) and rights to create users in the target OUs.
    The temporary password is read as a SecureString and is never written to disk or to the report.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
    [string]$CsvPath,

    [Parameter(Mandatory)]
    [ValidatePattern('^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')]
    [string]$UpnSuffix,

    [string]$ReportPath = (Join-Path -Path (Get-Location) -ChildPath ("onboarding-report-{0:yyyyMMdd-HHmm}.csv" -f (Get-Date)))
)

Import-Module ActiveDirectory -ErrorAction Stop

$requiredColumns = 'GivenName', 'Surname', 'SamAccountName', 'Department', 'Title', 'OU', 'Groups'
$rows = Import-Csv -Path $CsvPath

if (-not $rows) {
    throw "The CSV file '$CsvPath' is empty."
}

$missing = $requiredColumns | Where-Object { $_ -notin $rows[0].PSObject.Properties.Name }
if ($missing) {
    throw "The CSV file is missing required columns: $($missing -join ', ')"
}

$tempPassword = Read-Host -Prompt 'Temporary password for the new accounts (must meet the domain password policy)' -AsSecureString

$results = foreach ($row in $rows) {
    $sam = $row.SamAccountName.Trim()
    $upn = "$sam@$UpnSuffix"
    $displayName = "$($row.GivenName.Trim()) $($row.Surname.Trim())"
    $status = $null
    $detail = $null

    try {
        $existing = Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction Stop
        if ($existing) {
            $status = 'Skipped'
            $detail = 'User already exists'
        }
        elseif ($PSCmdlet.ShouldProcess($upn, "Create AD user in '$($row.OU)'")) {
            $newUser = @{
                Name                  = $displayName
                DisplayName           = $displayName
                GivenName             = $row.GivenName.Trim()
                Surname               = $row.Surname.Trim()
                SamAccountName        = $sam
                UserPrincipalName     = $upn
                Department            = $row.Department
                Title                 = $row.Title
                Path                  = $row.OU
                AccountPassword       = $tempPassword
                ChangePasswordAtLogon = $true
                Enabled               = $true
                ErrorAction           = 'Stop'
            }
            New-ADUser @newUser

            $groups = $row.Groups -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
            foreach ($group in $groups) {
                Add-ADGroupMember -Identity $group -Members $sam -ErrorAction Stop
            }

            $status = 'Created'
            $detail = if ($groups) { "Groups: $($groups -join ', ')" } else { 'No groups' }
        }
        else {
            $status = 'WhatIf'
            $detail = 'Not created (preview mode)'
        }
    }
    catch {
        $status = 'Failed'
        $detail = $_.Exception.Message
        Write-Warning "$($sam): $detail"
    }

    [PSCustomObject]@{
        SamAccountName    = $sam
        UserPrincipalName = $upn
        DisplayName       = $displayName
        Status            = $status
        Detail            = $detail
    }
}

$results | Export-Csv -Path $ReportPath -NoTypeInformation -Encoding UTF8
$results | Group-Object -Property Status | Select-Object -Property Name, Count | Format-Table -AutoSize
Write-Output "Report written to $ReportPath"
