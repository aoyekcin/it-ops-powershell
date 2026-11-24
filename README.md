# IT Operations PowerShell Toolkit

[![PowerShell lint](https://github.com/aoyekcin/it-ops-powershell/actions/workflows/lint.yml/badge.svg)](https://github.com/aoyekcin/it-ops-powershell/actions/workflows/lint.yml)

PowerShell scripts for everyday **IT operations** work in Microsoft environments: user onboarding and offboarding, Active Directory hygiene, Microsoft 365 license reviews, Intune device compliance, and multi-site connectivity checks.

Each script is built for safe, repeatable use:

- **Preview first:** scripts that change anything support `-WhatIf` and `-Confirm`
- **Audit trail:** every run writes a CSV report; offboarding backs up group memberships before removing them
- **No secrets in code:** passwords are read as `SecureString` and never written to disk
- **Read-only by default:** reporting scripts do not change anything

> Domains, names and hosts in the examples are placeholders (`contoso.com`, `example.local`). Test in a lab or with `-WhatIf` before running against production.

## Scripts

| Area | Script | What it does | Changes anything? |
|---|---|---|---|
| Active Directory | [New-ADUserFromCsv.ps1](active-directory/New-ADUserFromCsv.ps1) | Creates users from a CSV, sets a temporary password, adds groups, writes a result report | Yes (`-WhatIf` supported) |
| Active Directory | [Disable-ADUserOffboarding.ps1](active-directory/Disable-ADUserOffboarding.ps1) | Backs up groups, disables the account, removes groups, stamps the ticket ID, moves to the disabled OU | Yes (`-WhatIf` supported) |
| Active Directory | [Get-StaleADComputer.ps1](active-directory/Get-StaleADComputer.ps1) | Reports computers inactive for N days; can disable them | Only with `-Disable` |
| Microsoft 365 | [Get-M365LicenseReport.ps1](microsoft-365/Get-M365LicenseReport.ps1) | Purchased vs. assigned licenses per SKU, plus licensed users that are disabled or inactive | No |
| Intune | [Get-IntuneNoncompliantDevice.ps1](intune/Get-IntuneNoncompliantDevice.ps1) | Devices that are non-compliant or have not synced recently | No |
| Network | [Test-SiteConnectivity.ps1](network/Test-SiteConnectivity.ps1) | Pings hosts and tests service ports across many sites; summary per site (Healthy / Degraded / Down) | No |

## Requirements

| Scripts | Requirement |
|---|---|
| Active Directory | Windows with RSAT `ActiveDirectory` module and the right delegated permissions |
| Microsoft 365 / Intune | [Microsoft Graph PowerShell SDK](https://learn.microsoft.com/powershell/microsoftgraph/installation): `Install-Module Microsoft.Graph -Scope CurrentUser` |
| Network | Windows PowerShell 5.1 or PowerShell 7+ (no extra modules) |

Every script has full help: `Get-Help .\active-directory\New-ADUserFromCsv.ps1 -Full`

## Quick start

```powershell
# Preview onboarding without creating anything
.\active-directory\New-ADUserFromCsv.ps1 -CsvPath .\samples\new-users.sample.csv -UpnSuffix contoso.com -WhatIf

# Offboard a leaver, with a confirmation prompt
.\active-directory\Disable-ADUserOffboarding.ps1 -SamAccountName jdoe `
    -DisabledOU "OU=Disabled Users,DC=contoso,DC=com" -TicketId REQ-1042

# Weekly license review
.\microsoft-365\Get-M365LicenseReport.ps1 -InactiveDays 90

# Store-opening connectivity check, showing only problems
.\network\Test-SiteConnectivity.ps1 -CsvPath .\samples\sites.sample.csv | Where-Object Status -ne 'OK'
```

## Quality checks

A GitHub Actions workflow parses every script and runs [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer) on each push.

## Related

- [IT Operations Runbooks](https://github.com/aoyekcin/it-ops-runbooks): the processes these scripts support (incident, change and problem management)

## Author

**Aykut Öyekcin** — IT Operations & Platform Support Specialist
[LinkedIn](https://www.linkedin.com/in/aykutoyekcin) · [GitHub](https://github.com/aoyekcin)

## License

[MIT](LICENSE)
