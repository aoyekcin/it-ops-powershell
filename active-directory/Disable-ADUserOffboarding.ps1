<#
.SYNOPSIS
    Offboards Active Directory users in a consistent, auditable way.

.DESCRIPTION
    For each given user:
      1. exports the current group memberships to a CSV (so access can be restored if needed)
      2. disables the account
      3. removes the user from all groups except the primary group (usually Domain Users)
      4. writes the offboarding date and ticket number into the description
      5. moves the account to the disabled-users OU

    Supports -WhatIf and -Confirm.

.PARAMETER SamAccountName
    One or more user logon names. Accepts pipeline input.

.PARAMETER DisabledOU
    Distinguished name of the OU for disabled accounts.

.PARAMETER TicketId
    Ticket or request number, written into the account description for traceability.

.PARAMETER BackupFolder
    Folder for the group membership backups. Defaults to the current folder.

.EXAMPLE
    .\Disable-ADUserOffboarding.ps1 -SamAccountName jdoe -DisabledOU "OU=Disabled Users,DC=contoso,DC=com" -TicketId REQ-1042 -WhatIf

.EXAMPLE
    Get-Content .\leavers.txt | .\Disable-ADUserOffboarding.ps1 -DisabledOU "OU=Disabled Users,DC=contoso,DC=com" -TicketId REQ-1042

.NOTES
    Requires: ActiveDirectory module (RSAT) and rights to modify users and groups.
    Mailbox, license and device steps are handled by the Microsoft 365 / Intune process.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory, ValueFromPipeline)]
    [ValidateNotNullOrEmpty()]
    [string[]]$SamAccountName,

    [Parameter(Mandatory)]
    [string]$DisabledOU,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TicketId,

    [ValidateScript({ Test-Path -Path $_ -PathType Container })]
    [string]$BackupFolder = (Get-Location).Path
)

begin {
    Import-Module ActiveDirectory -ErrorAction Stop
    $today = Get-Date -Format 'yyyy-MM-dd'
}

process {
    foreach ($sam in $SamAccountName) {
        try {
            $user = Get-ADUser -Identity $sam -Properties MemberOf, PrimaryGroup, Description -ErrorAction Stop
        }
        catch {
            Write-Warning "$($sam): user not found. $($_.Exception.Message)"
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($user.UserPrincipalName, 'Offboard user (disable, remove groups, move OU)')) {
            continue
        }

        try {
            # 1. Back up group memberships
            $groups = Get-ADPrincipalGroupMembership -Identity $user -ErrorAction Stop |
                Where-Object { $_.DistinguishedName -ne $user.PrimaryGroup }
            $backupPath = Join-Path -Path $BackupFolder -ChildPath "$sam-groups-$today.csv"
            $groups | Select-Object -Property Name, DistinguishedName, GroupScope, GroupCategory |
                Export-Csv -Path $backupPath -NoTypeInformation -Encoding UTF8

            # 2. Disable the account
            Disable-ADAccount -Identity $user -ErrorAction Stop

            # 3. Remove group memberships (primary group stays)
            foreach ($group in $groups) {
                Remove-ADGroupMember -Identity $group -Members $user -Confirm:$false -ErrorAction Stop
            }

            # 4. Record who/when/why in the description
            Set-ADUser -Identity $user -Description "Disabled $today - $TicketId" -ErrorAction Stop

            # 5. Move to the disabled-users OU
            Move-ADObject -Identity $user.DistinguishedName -TargetPath $DisabledOU -ErrorAction Stop

            [PSCustomObject]@{
                SamAccountName = $sam
                Status         = 'Offboarded'
                GroupsRemoved  = @($groups).Count
                GroupBackup    = $backupPath
            }
        }
        catch {
            Write-Warning "$($sam): offboarding stopped. $($_.Exception.Message)"
            [PSCustomObject]@{
                SamAccountName = $sam
                Status         = 'Failed'
                GroupsRemoved  = $null
                GroupBackup    = $null
            }
        }
    }
}
