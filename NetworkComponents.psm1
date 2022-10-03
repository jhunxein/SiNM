Import-Module .\ProcessToObject.psm1

class Cache {

  [System.String] $_CachePath
  [System.String] hidden $_TIME_FORMAT = 'yyyyMMddHHmmss'
  [System.Int64] $_TIME_STAMP

  [System.Int32] $_24_HOURS_IN_SECONDS = 60 * 60 * 24

  Cache() {
    $this._CachePath = Join-Path -Path $global:Home -ChildPath "mapper_cache.json"
  }

  [System.Int64] GetTimeStamp() {
    return Get-Date -F $this._TIME_FORMAT
  }

  [System.Object] GetCache() {

    [System.Object]$Cache = [pscustomobject] @{
      Host       = [pscustomobject] @{}
      Components = [pscustomobject] @{}
    }

    if (-not (Test-Path $this._CachePath)) {
      # if file is not created, create a new one
      $JSON = $Cache | ConvertTo-Json
      New-Item `
        -Path $this._CachePath `
        -Value $JSON `
        -ItemType 'File' `
        -Force | Out-Null
    }
    else {
      $Cache = Get-Content `
        -Path $this._CachePath | ConvertFrom-Json

      $this._TIME_STAMP = $Cache.TimeStamp
    }

    return $Cache
  }

  [System.Object] WriteCache([System.Object[]]$ComputerHost, [System.Object[]]$Components) {

    $tmpStamp = $this.GetTimeStamp()

    $Cache = @{
      TimeStamp  = $tmpStamp
      Host       = $ComputerHost | Select-Object ComputerName, IPAddress
      Components = $Components | Select-Object DisplayName, Type, ConnectionOwner, SourcePath, SourceIPAddress, AdditionalInfo | Sort-Object -Property DisplayName
    }

    try {
      
      $Cache |
      ConvertTo-Json | 
      Out-File $this._CachePath -Encoding utf8 -ErrorAction Stop

      $this._TIME_STAMP = $tmpStamp

      return Invoke-OperationStatus `
        -Status Success `
        -Message "Scanned network is saved."
    }
    catch {

      return Invoke-OperationStatus `
        -Status Error `
        -Message $_.Exception.Message `
    
    }
  }

}

class NetworkComponents : Cache {
  
  [System.Object[]] hidden $_Components
  [System.Object[]] hidden $_ComputerList # sources

  # scanning host and shared components in the background
  hidden $_HostJob
  hidden $_HostEvent

  hidden $_ComponentJob
  hidden $_ComponentEvent

  [System.Object] hidden $_ScanProperties

  NetworkComponents() {
    $Cache = $this.GetCache()

    $this._ComputerList = $Cache.Host
    $this._Components = $Cache.Components

    $this._ScanProperties = [pscustomobject] @{
      Status  = $null
      Message = $null
    }
  }

  [System.Boolean] IsCacheExpired() {
    if (($this.GetTimeStamp() - $this._TIME_STAMP) -lt $this._24_HOURS_IN_SECONDS) { return $false } else { return $true }
  }

  [System.Void] PerformScan() {
    $this._StartComputerHostScan()
  }

  [System.Object] ScanStatus() {
    return $this._ScanProperties
  }

  [System.Void] hidden _PerformWriteCache() {
    $SaveResult = $this.WriteCache($this._ComputerList, $this._Components)
    $this._ScanProperties.Status = $SaveResult.Status
    $this._ScanProperties.Message = $SaveResult.Message
  }

  # run this first
  [System.Void] hidden _StartComputerHostScan () {
    $this._ScanProperties.Status = "start"
    $this._ScanProperties.Message = "Preparing to scan for possible host."

    $this._HostJob = Start-Job -Name HostScan `
      -FilePath .\ComputerListJob.ps1

    $this._HostEvent = Register-ObjectEvent `
      $this._HostJob StateChanged `
      -MessageData $this `
      -Action {
      try {
          
        $ComputerHosts = Receive-Job -Id $sender.Id -Keep
        $Event.MessageData._ComputerList = $ComputerHosts

        $Event.MessageData._ScanProperties.Message = "Host are scanned. Preparing to scan host for possible shared components."

        $Event.MessageData._StartSharedComponentScan($ComputerHosts)
      }
      catch {
        $Event.MessageData._ScanProperties.Message = $_.Exception.Message
        $Event.MessageData._ScanProperties.Status = "error"
      }
      finally {
        Remove-Job -Id $sender.Id # remove Job
        Get-EventSubscriber -SubscriptionId $eventSubscriber.SubscriptionId | Unregister-Event -Force # remove event
      }
    }
  }
  
  # after the host is scanned, scan each host
  [System.Void] hidden _StartSharedComponentScan ([System.Object[]]$list) {
    $this._ScanProperties.Message = "Preparing to scan host for possible shared components."

    $this._ComponentJob = Start-Job -Name SharedScan `
      -InitializationScript { Import-Module .\ProcessToObject.psm1 } `
      -FilePath .\ScanComputerJob.ps1 -ArgumentList (, $list)
  
    $this._ComponentEvent = Register-ObjectEvent `
      $this._ComponentJob StateChanged `
      -MessageData $this `
      -Action {
      try {
        $SharedComponents = Receive-Job -Id $sender.Id -Keep
        $Event.MessageData._Components = $SharedComponents

        $Event.MessageData._ScanProperties.Status = "success"
        $Event.MessageData._ScanProperties.Message = "Host are scanned for shared components."

        $Event.MessageData._PerformWriteCache() 
      }
      catch {
        $Event.MessageData._ScanProperties.Status = "error"
        $Event.MessageData._ScanProperties.Message = $_.Exception.Message
      }
      finally {
        Remove-Job -Id $sender.Id # remove Job
        Get-EventSubscriber -SubscriptionId $eventSubscriber.SubscriptionId | Unregister-Event -Force # remove event
      }
    }
  }

  [System.Void] SetComputerHost([System.Object[]]$ComputerHost) {
    $this._ComputerList = $ComputerHost
  }

  [System.Void] SetSharedComponent([System.Object[]]$Components) {
    $this._Components = $Components
  }

  [System.Object[]] Get([System.String]$Type) {

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