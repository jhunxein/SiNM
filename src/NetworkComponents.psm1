Import-Module .\ProcessToObject.psm1

class NetworkComponents {
  
  [System.Object[]] hidden $_Components
  [System.Object[]] hidden $_ComputerList # sources

  # job id's
  [System.Int16] hidden $_ScanComputersID
  [System.Int16] hidden $_ScanSharesID

  [System.Boolean] hidden $_IsScanned

  [System.Void] SetComputerHost([System.Object[]]$ComputerHost) {
    $this._ComputerList = $ComputerHost
  }

  [System.Void] SetSharedComponent([System.Object[]]$Components) {
    $this._Components = $Components
  }

  [System.Void] Init() {
    $this._StartComputerScan() # search for active computers in the network
  }

  [System.Void] hidden _StartComputerScan() {
    $this._ScanComputersID = (Start-Job -FilePath .\ComputerListJob.ps1 -Name NetworkScan).Id
  }

  [System.Void] hidden _StartSharesScan([System.Object[]]$list) {
    $this._ScanSharesID = (Start-Job -InitializationScript { Import-Module .\ProcessToObject.psm1 } -FilePath .\ScanComputerJob.ps1 -ArgumentList (, $list) ).Id
  }

  [System.Object[]] Get([System.String]$Type) {

    if (-not $this._Components.Count) {

      if (-not $this._ComputerList.Count) {
        $computerListResult = $this._GetComputerList()

        if ($computerListResult[0].Status -eq 'Error') { return $computerListResult }

        if (-not $computerListResult.Count) {
          return Invoke-OperationStatus `
            -Status Error `
            -Message "There are no components found in the network." `
            -Code -1
        }

        $this._ComputerList = $computerListResult

        Remove-Variable computerListResult -ErrorAction SilentlyContinue
      }

      if (-not $this._ComputerList.Count) {
        return Invoke-OperationStatus `
          -Status Error `
          -Message "There are no computers that discovered in the network. Please check network connection first and try again." `
          -Code -1
      }

      if (-not $this._IsScanned) {
        $this._IsScanned = $true
        $this._StartSharesScan($this._ComputerList)
        return Invoke-OperationStatus `
          -Status Error `
          -Message "Starting to scan network for shared components. Please wait." `
          -Code 1
      }

      if ($this._ScanSharesID) {
        # scanning
        $sharedResult = $this._GetSharedList()

        if ($sharedResult[0].Status -eq 'Error') { return $sharedResult }

        if (-not $sharedResult.Count) {
          return Invoke-OperationStatus `
            -Status Error `
            -Message "There are no components found in the network." `
            -Code -1
        }

        $this._Components = $sharedResult | Select-Object -Property DisplayName, Type, ConnectionOwner, SourcePath, SourceIPAddress, AdditionalInfo | Sort-Object -Property DisplayName

        Remove-Variable sharedResult -ErrorAction SilentlyContinue

      }

    }

    # check if job is complete
    [System.Object[]] $ReturnObject = @()

    if ($Type -eq 'all') {
      $ReturnObject = $this._Components
    }
    elseif ($Type -eq 'Print') {
      $ReturnObject = $this._Components | Where-Object { $_.Type -eq 'Print' }
    }
    elseif ($Type -eq 'Disk') {
      $ReturnObject = $this._Components | Where-Object { $_.Type -like 'Dis*' }
    }

    return $ReturnObject
  }

  [System.Object] Connect([System.Object]$Component) {

    [System.Object] $result = [pscustomobject]@{}

    if ($Component.Type -eq 'Print') {
      $result = $this._SetPrinter($Component)
    }
    elseif ($Component.Type -eq 'Disk') {
      $result = $this._SetDrive($Component)
    }

    return $result
  }

  [System.Object] hidden _SetPrinter([System.Object]$PrinterObject) {

    try {
      Add-Printer -ConnectionName $PrinterObject.SourcePath -ErrorAction Stop

      return Invoke-OperationStatus `
        -Status Success `
        -Message "Connected"
      
    }
    catch {
      return Invoke-OperationStatus `
        -Status "Error" `
        -Message $_.Exception.Message `
        -Code $_.Exception.HResult
    }

  }

  [System.Object] hidden _SetDrive([System.Object]$MapObject) {

    try {

      New-PSDrive -Name $MapObject.AdditionalInfo `
        -Root $MapObject.SourcePath `
        -PSProvider FileSystem `
        -Scope Global `
        -ErrorAction Stop `
        -Persist | Out-Null

      return Invoke-OperationStatus `
        -Status Success `
        -Message "Connected"

    }
    catch {
      return Invoke-OperationStatus `
        -Status "Error" `
        -Message $_.Exception.Message `
        -Code $_.Exception.HResult
    }

  }
  
  [System.Object[]] hidden _GetComputerList() {

    $result = @()

    if (-not $this._ScanComputersID) {
      return $result
    }

    $networkJob = Get-Job -Id $this._ScanComputersID

    if ($networkJob.State -eq 'Running') { return Invoke-OperationStatus -Status Error -Message "Scanning network for potential source. Please wait." -Code 1 }

    if ($networkJob.State -eq 'Completed') {
      $result = Receive-Job -Id $this._ScanComputersID -Keep 
      
      Remove-Job -Id $this._ScanComputersID

      $this._ScanComputersID = $null
    }

    return $result

  }

  [System.Object[]] hidden _GetSharedList() {

    $result = @()

    if (-not $this._ScanSharesID) {
      return $result
    }

    $networkJob = Get-Job -Id $this._ScanSharesID

    if ($networkJob.State -eq 'Running') { return Invoke-OperationStatus -Status Error -Message "Scanning network for potential shared components. Please wait." -Code 1 }

    if ($networkJob.State -eq 'Completed') {
      $result = Receive-Job -Id $this._ScanSharesID -Keep
      
      Remove-Job -Id $this._ScanSharesID

      $this._ScanSharesID = $null
    }

    return $result
    
  }

  # will be called in local components
  [System.Object] GetComputerHost([System.String]$IPAddress) {
    return $this._ComputerList | Where-Object { $_.IPAddress -eq $IPAddress }
  }

}

function Invoke-NetworkComponents() {
  [NetworkComponents]::new()
}

Export-ModuleMember -Function Invoke-NetworkComponents