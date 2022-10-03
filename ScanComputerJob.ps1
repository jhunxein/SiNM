Param (
  [Parameter(Mandatory, Position = 1)]
  [System.Object[]]$Sources
)

$sharedList = @()

foreach ($Source in $Sources) {

  try {
      
    $scan = (net.exe view $Source.ComputerName | 
      Where-Object { 
        $_ -match '\sPrint|Disk\s' 
      }).trim() -replace '\s\s+', ',' 

  }
  catch {
    continue
  }

  if (-not $scan -or $scan[0] -eq 'Users,Disk') {
    continue
  }

  # inner loop for getting shared components
  foreach ($shared in $scan) {
        
    # shared item index result
    # [0] - name
    # [1] - type
    # [2] - info
    $sharedItems = $shared.Split(',')

    if ($sharedItems[0] -eq 'Users') { continue }

    $sharedList += Invoke-ProcessToTemplate `
      -DisplayName $sharedItems[0] `
      -Type $sharedItems[1] `
      -ConnectionOwner $Source.ComputerName `
      -SourceIPAddress $Source.IPAddress

    $sharedItems = @()
  }

}

return $sharedList