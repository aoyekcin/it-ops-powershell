<#
.SYNOPSIS
    Microsoft 365 license usage report: purchased vs. assigned licenses, and licensed users who look unused.

.DESCRIPTION
    Uses Microsoft Graph PowerShell to produce two CSV reports:
      1. license-summary: every subscribed SKU with purchased, assigned and available units
      2. license-review:  licensed users that are disabled, or have not signed in for -InactiveDays
         (candidates for license reclaim)

    Sign-in activity requires Microsoft Entra ID P1/P2 and the AuditLog.Read.All permission.
    Without it, the script still produces the summary and the disabled-user review.

.PARAMETER InactiveDays
    Users without a sign-in for this many days are flagged. Default: 60.

.PARAMETER OutputFolder
    Folder for the CSV reports. Defaults to the current folder.

.EXAMPLE
    .\Get-M365LicenseReport.ps1 -InactiveDays 90

.NOTES
    Requires: Microsoft.Graph.Authentication, Microsoft.Graph.Users and
    Microsoft.Graph.Identity.DirectoryManagement modules.
    Install-Module Microsoft.Graph -Scope CurrentUser
    Read-only: this script does not change any license assignment.
#>
[CmdletBinding()]
param(
    [ValidateRange(14, 365)]
    [int]$InactiveDays = 60,

    [ValidateScript({ Test-Path -Path $_ -PathType Container })]
    [string]$OutputFolder = (Get-Location).Path
)

$scopes = 'User.Read.All', 'Organization.Read.All', 'AuditLog.Read.All'
Connect-MgGraph -Scopes $scopes -NoWelcome -ErrorAction Stop

$stamp = Get-Date -Format 'yyyyMMdd'

# 1. SKU summary
$skus = Get-MgSubscribedSku -All -ErrorAction Stop
$skuNames = @{}
$summary = foreach ($sku in $skus) {
    $skuNames[$sku.SkuId] = $sku.SkuPartNumber
    [PSCustomObject]@{
        Sku       = $sku.SkuPartNumber
        Purchased = $sku.PrepaidUnits.Enabled
        Assigned  = $sku.ConsumedUnits
        Available = $sku.PrepaidUnits.Enabled - $sku.ConsumedUnits
        Suspended = $sku.PrepaidUnits.Suspended
        Warning   = $sku.PrepaidUnits.Warning
    }
}
$summaryPath = Join-Path -Path $OutputFolder -ChildPath "license-summary-$stamp.csv"
$summary | Sort-Object -Property Sku | Export-Csv -Path $summaryPath -NoTypeInformation -Encoding UTF8

# 2. Licensed users to review
$properties = 'DisplayName', 'UserPrincipalName', 'AccountEnabled', 'AssignedLicenses', 'Department', 'SignInActivity'
try {
    $users = Get-MgUser -All -Filter 'assignedLicenses/$count ne 0' -ConsistencyLevel eventual -CountVariable licensedCount -Property $properties -ErrorAction Stop
}
catch {
    Write-Warning "Could not read sign-in activity (needs Entra ID P1/P2 and AuditLog.Read.All). Continuing without it."
    $properties = $properties | Where-Object { $_ -ne 'SignInActivity' }
    $users = Get-MgUser -All -Filter 'assignedLicenses/$count ne 0' -ConsistencyLevel eventual -CountVariable licensedCount -Property $properties -ErrorAction Stop
}

$cutoff = (Get-Date).AddDays(-$InactiveDays)
$review = foreach ($user in $users) {
    $lastSignIn = $user.SignInActivity.LastSignInDateTime
    $reason = @()
    if (-not $user.AccountEnabled) { $reason += 'Account disabled' }
    if ($properties -contains 'SignInActivity') {
        if (-not $lastSignIn) { $reason += 'Never signed in' }
        elseif ($lastSignIn -lt $cutoff) { $reason += "No sign-in for $InactiveDays+ days" }
    }

    if ($reason) {
        [PSCustomObject]@{
            DisplayName       = $user.DisplayName
            UserPrincipalName = $user.UserPrincipalName
            Department        = $user.Department
            AccountEnabled    = $user.AccountEnabled
            LastSignIn        = $lastSignIn
            Licenses          = ($user.AssignedLicenses | ForEach-Object { $skuNames[$_.SkuId] }) -join '; '
            Reason            = $reason -join '; '
        }
    }
}
$reviewPath = Join-Path -Path $OutputFolder -ChildPath "license-review-$stamp.csv"
$review | Sort-Object -Property LastSignIn | Export-Csv -Path $reviewPath -NoTypeInformation -Encoding UTF8

$summary | Sort-Object -Property Sku | Format-Table -AutoSize
Write-Output "Licensed users: $licensedCount. Flagged for review: $(@($review).Count)."
Write-Output "Reports: $summaryPath, $reviewPath"
