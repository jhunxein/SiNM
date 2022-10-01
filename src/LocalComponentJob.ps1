function GetPrinters {
  $printerList = Get-CimInstance -Class Win32_Printer | 
  Where-Object { $_.Shared } | 
  Select-Object -Property SystemName, Default, ShareName

  return ToTemplate -Data $printerList -Type "Print"
}

function GetMappedDrives {
  $driverList = Get-SmbMapping | Select-Object -Property LocalPath, RemotePath

  return ToTemplate -Data $driverList -Type "Disk"
}

function ToTemplate {
  Param(
    [System.Object[]]$Data,
    [System.String]$Type
  )

  $placeholder = [System.Collections.ArrayList]::new()
  $AdditionalInfo = $null
  $SourceIPAddress = $null
  $DisplayName = $null

  foreach ($row in $Data) {

    if ($Type -eq 'print') {
      $DisplayName = $row.ShareName
      $SourceIPAddress = $row.SystemName -replace "\\", ""
      $AdditionalInfo = if ($row.Default) { "Default" } else { "" }
    }
    else {
      $splitRow = $row.RemotePath.Replace('\\', '').Split('\')

      $DisplayName = $splitRow[1]
      $SourceIPAddress = $splitRow[0]
      $AdditionalInfo = $row.LocalPath.Remove(1) # remove semicolon
    }

    $ComputerHost = (Resolve-DnsName $SourceIPAddress -ErrorAction SilentlyContinue).NameHost

    $placeholder += Invoke-ProcessToTemplate `
      -DisplayName $DisplayName `
      -Type $Type `
      -SourceIPAddress $SourceIPAddress `
      -ConnectionOwner $ComputerHost `
      -Info $AdditionalInfo
  }

  return $placeholder
}

$result = [System.Collections.ArrayList]::new()

$result += GetPrinters
$result += GetMappedDrives

return $result