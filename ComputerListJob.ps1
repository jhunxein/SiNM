$IPList = Get-NetNeighbor -State Reachable, Stale | 
Where-Object { $_.AddressFamily -eq 'IPv4' } | 
Select-Object -Property IPAddress

$IPList += ( Get-NetIPAddress |
  Where-Object { 
    $_.AddressFamily -eq 'IPv4' -and $_.InterfaceAlias -eq 'Ethernet'
  } | 
  Select-Object IPAddress)

if (-not $IPList.Count) {
  return @()
}

$sources = @()

foreach ($list in $IPList) {
      
  $dnsResult = (Resolve-DnsName $list.IPAddress -ErrorAction SilentlyContinue).NameHost

  if (-not $dnsResult) { continue }

  $sources += [PSCustomObject]@{
    ComputerName = "$dnsResult"
    IPAddress    = "$($list.IPAddress)"
  } 

}

return $sources