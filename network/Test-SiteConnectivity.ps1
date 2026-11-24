<#
.SYNOPSIS
    Checks reachability of many sites (stores, branches) and their key services in one run.

.DESCRIPTION
    Reads a list of sites and hosts from a CSV and, for each host:
      - pings it (ICMP), and
      - tests a TCP port (e.g. 443 for a POS backend, 3389 for remote support)
    Prints a summary per site and exports the full result to CSV.

    Useful at store opening time or during a suspected multi-site outage
    to see quickly whether the problem is one site, one service, or everything.

    Works on Windows PowerShell 5.1 and PowerShell 7+.

.PARAMETER CsvPath
    Input CSV with columns: Site, Host, Port, Role
    See samples/sites.sample.csv.

.PARAMETER TimeoutMs
    TCP connect timeout in milliseconds. Default: 2000.

.PARAMETER ReportPath
    Where to write the CSV report.

.EXAMPLE
    .\Test-SiteConnectivity.ps1 -CsvPath .\sites.csv

.EXAMPLE
    .\Test-SiteConnectivity.ps1 -CsvPath .\sites.csv | Where-Object Status -ne 'OK'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
    [string]$CsvPath,

    [ValidateRange(200, 30000)]
    [int]$TimeoutMs = 2000,

    [string]$ReportPath = (Join-Path -Path (Get-Location) -ChildPath ("site-connectivity-{0:yyyyMMdd-HHmm}.csv" -f (Get-Date)))
)

function Test-TcpPort {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][int]$Port,
        [int]$Timeout = 2000
    )

    $client = New-Object -TypeName System.Net.Sockets.TcpClient
    try {
        $connect = $client.BeginConnect($ComputerName, $Port, $null, $null)
        if ($connect.AsyncWaitHandle.WaitOne($Timeout, $false) -and $client.Connected) {
            $client.EndConnect($connect)
            return $true
        }
        return $false
    }
    catch {
        return $false
    }
    finally {
        $client.Close()
    }
}

$targets = Import-Csv -Path $CsvPath

$results = foreach ($target in $targets) {
    $ping = Test-Connection -ComputerName $target.Host -Count 1 -Quiet -ErrorAction SilentlyContinue
    $port = if ($target.Port) { [int]$target.Port } else { $null }
    $tcp = if ($port) { Test-TcpPort -ComputerName $target.Host -Port $port -Timeout $TimeoutMs } else { $null }

    $status = if ($null -eq $tcp) {
            if ($ping) { 'OK' } else { 'Unreachable' }
        }
        elseif ($tcp) {
            if ($ping) { 'OK' } else { 'OK (ICMP blocked)' }
        }
        elseif ($ping) { 'Service down' }
        else { 'Unreachable' }

    [PSCustomObject]@{
        Time   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Site   = $target.Site
        Role   = $target.Role
        Host   = $target.Host
        Port   = $port
        Ping    = $ping
        TcpOpen = $tcp
        Status  = $status
    }
}

$results | Export-Csv -Path $ReportPath -NoTypeInformation -Encoding UTF8

# Per-site summary: a site is "Down" when every host is unreachable
$results | Group-Object -Property Site | ForEach-Object {
    $problems = @($_.Group | Where-Object { $_.Status -notlike 'OK*' })
    [PSCustomObject]@{
        Site     = $_.Name
        Hosts    = $_.Count
        Problems = $problems.Count
        State    = if ($problems.Count -eq 0) { 'Healthy' } elseif ($problems.Count -eq $_.Count) { 'Down' } else { 'Degraded' }
    }
} | Sort-Object -Property State, Site | Format-Table -AutoSize

Write-Output "Full report: $ReportPath"
$results
