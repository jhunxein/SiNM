class Jobs {

  [System.Object] $_Objects 
  [System.Object] $_Setters

  Jobs($SetterHost, $SetterShared, $SetterLocal) {
    $this._Objects = @{
      Host   = @{
        Job    = $null
        Event  = $null
        Status = $null
      }
      Shared = @{
        Job    = $null
        Event  = $null
        Status = $null
      }
      Local  = @{
        Job    = $null
        Event  = $null
        Status = $null
      }
    }

    $this._Setters = @{
      Host   = $SetterHost
      Shared = $SetterShared
      Local  = $SetterLocal
    }

    $this._Start()
  }

  [System.String] Status([System.String]$Type) {

    return $this._Objects[$Type].Status
  }

  [System.Void] hidden _Start() {

    Remove-Job * -Force
    
    <#
    Only call jobs for computer host and local component scan
    since shared network scan is dependent in the list of computer host 
    #>

    $this._StartLocalComponentScan()
    $this._StartComputerHostScan()
  }

  [System.Void] hidden _Terminate([System.String]$Type) {
    $SelectedType = $this._Objects[$Type]

    if (-not $SelectedType) { return }

    Remove-Job -Id $SelectedType.Job.Id -Force
    Remove-Job -Id $SelectedType.Event.Id -Force

    $this._Objects[$Type].Job = $null
    $this._Objects[$Type].Event = $null
  }

  [System.Void] Trigger([System.String]$Type, [System.Object[]]$Arguments) {
    $Arguments = $Arguments | Select-Object -Property DisplayName, Type, ConnectionOwner, SourcePath, SourceIPAddress, AdditionalInfo

    $this._Objects[$Type].Status = 'complete'

    $this._Setters[$Type].Invoke(@(, $Arguments))
    $this._Terminate($Type)
  }
  
  [System.Void] hidden _StartComputerHostScan () {
    $this._Objects.Host.Job = Start-Job -Name HostScan `
      -FilePath .\ComputerListJob.ps1

    $this._Objects.Host.Status = "on-progress"

    $this._Objects.Host.Event = Register-ObjectEvent `
      $this._Objects.Host.Job StateChanged `
      -MessageData $this `
      -Action {
      $ComputerHosts = Receive-Job -Id $sender.Id -Keep
      $Event.MessageData.Trigger('Host', $ComputerHost)
      $Event.MessageData._StartSharedComponentScan($ComputerHosts)
    } 
  }
  
  [System.Void] hidden _StartSharedComponentScan ([System.Object[]]$list) {
    $this._Objects.Shared.Job = Start-Job -Name SharedScan `
      -InitializationScript { Import-Module .\ProcessToObject.psm1 } `
      -FilePath .\ScanComputerJob.ps1 -ArgumentList (, $list)

    $this._Objects.Shared.Status = "on-progress"
  
    $this._Objects.Shared.Event = Register-ObjectEvent `
      $this._Objects.Shared.Job StateChanged `
      -MessageData $this `
      -Action {
      $SharedComponents = Receive-Job -Id $sender.Id -Keep
      $Event.MessageData.Trigger('Shared', $SharedComponents)
    }
  }

  [System.Void] hidden _StartLocalComponentScan () {
    $this._Objects.Local.Job = Start-Job -Name LocalScan `
      -FilePath .\LocalComponentJob.ps1 `
      -InitializationScript { Import-Module .\ProcessToObject.psm1 }

    $this._Objects.Local.Status = "on-progress"
  
    $this._Objects.Local.Event = Register-ObjectEvent `
      $this._Objects.Local.Job StateChanged `
      -MessageData $this `
      -Action {
      $LocalComponents = Receive-Job -Id sender.Id -Keep 

      $Event.MessageData.Trigger('Local', $LocalComponents)
    }
  }
}

function Invoke-Jobs {
  Param(
    [Parameter(Mandatory)]
    $SetterHost,
    [Parameter(Mandatory)]
    $SetterShared,
    [Parameter(Mandatory)]
    $SetterLocal
  )

  [Jobs]::new($SetterHost, $SetterShared, $SetterLocal)
}

Export-ModuleMember -Function Invoke-Jobs