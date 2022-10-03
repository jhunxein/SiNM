Import-Module .\ProcessToObject.psm1

class LocalComponents {
  hidden $_Components

  hidden $_Event
  hidden $_Job
  hidden $_Status

  LocalComponents() {
    $this._InvokeScan()
  }

  [System.Void] hidden _InvokeScan () {
    $this._Job = Start-Job -Name LocalScan `
      -FilePath .\LocalComponentJob.ps1 `
      -InitializationScript { Import-Module .\ProcessToObject.psm1 }

    $this._Event = Register-ObjectEvent `
      $this._Job StateChanged `
      -MessageData $this `
      -Action {
        
      $_LocalComponents = Receive-Job -Id $sender.Id -Keep 
      $Event.MessageData.Set.Invoke(@(, $_LocalComponents))

      Remove-Job -Id $sender.Id # remove Job
      Get-EventSubscriber -SubscriptionId $eventSubscriber.SubscriptionId | Unregister-Event -Force # remove event
    }
  }

  [System.Void] hidden Set([System.Object[]]$Objects) {
    $this._Components = $Objects

    $this._Job = $null
    $this._Event = $null
  }

  [System.Object[]] Get([System.String]$Type) {

    [System.Object[]] $ReturnObject = @()

    if ($Type -eq 'all') {
      $ReturnObject = $this._Components
    }
    elseif ($Type -eq 'Print') {
      $ReturnObject = $this._Components | Where-Object { $_.Type -eq 'Print' }
    }
    elseif ($Type -eq 'Disk') {
      $ReturnObject = $this._Components | Where-Object { $_.Type -eq 'Disk' }
    }

    return $ReturnObject | Sort-Object -Property DisplayName
  }

  [System.Void] SetLocalComponent([System.Object[]]$Component) {
    $this._Components = $Component
  }

  [System.Object] Remove($Component) {

    [System.Object] $Result = [pscustomobject]@{}

    if ($Component.Type -eq 'Print') {
      $Result = $this.RemovePrinter($Component)
    }
    elseif ($Component.Type -eq 'Disk') {
      $Result = $this.RemoveMapDrive($Component)
    }

    if ($Result.Status -eq 'Success') {
      $this._Components | Where-Object { $_.SourcePath -ne $Component.SourcePath }
    }

    return $Result
  }

  [System.Object] RemoveMapDrive([System.Object]$MapObject) {

    $ErrorActionPreference = 'Stop'

    $MapName = $MapObject.AdditionalInfo

    try {
      
      Remove-PSDrive -Name $MapObject.AdditionalInfo `
        -Scope Global `
        -PSProvider FileSystem `
        -Force 

      # check if ps drive is remove successfully
      if (Get-PSDrive -Name $MapObject.AdditionalInfo -ErrorAction SilentlyContinue ) {
      
        # if connection still exists, use `net use @mapname: with /delete /yes
        net.exe use "$($MapObject.AdditionalInfo):" /d /y

      }

      return Invoke-OperationStatus
    }
    catch {

      $GetSmb = Get-SmbMapping -LocalPath "$($MapName):" -ErrorAction SilentlyContinue

      if (-not $GetSmb) {
        return Invoke-OperationStatus `
          -Status "Error" `
          -Message $_.Exception.Message `
          -Code $_.Exception.HResult
      }

      net.exe use "$($MapName):" /d /y

      return Invoke-OperationStatus

    }
  }

  [System.Object] RemovePrinter([System.Object]$PrinterObject) {

    try {
      Remove-Printer `
        -Name $PrinterObject.SourcePath `
        -ErrorAction Stop `

      return Invoke-OperationStatus
    }
    catch {
      return Invoke-OperationStatus `
        -Status "Error" `
        -Message $_.Exception.Message `
        -Code $_.Exception.HResult
    }

  }

  [System.Object] SetDefaultPrinter([System.String]$Source) {
    
    $ErrorActionPreference = "Stop"

    $result = [pscustomobject] @{}

    try {
      $printer = Get-CimInstance -Class Win32_Printer | Where-Object { $_.Name -eq $Source }

      Invoke-CimMethod -InputObject $printer -MethodName SetDefaultPrinter

      $result = Invoke-OperationStatus -Status Success
    }
    catch {
      $result = Invoke-OperationStatus `
        -Status Error `
        -Message $_.Exception.Message
      -Code $_.Exception.HResult
    }

    return $result
  }
}

function Invoke-LocalComponents {
  [LocalComponents]::new()
}

Export-ModuleMember -Function Invoke-LocalComponents