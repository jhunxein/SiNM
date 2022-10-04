Get-ChildItem . | ForEach-Object {
  if ($_.Extension -ne '.psm1') { return }
  Import-Module $_.FullName -Force
}

class NetworkMapper {

  $Attributes

  $MENU
  $UserProfile
  $NetworkComponent
  $LocalComponent

  NetworkMapper() {
    Clear-Host 

    $this.MENU = [ordered] @{
      "Reconnect"    = $this.Reconnect
      "Connect"      = $this.Connect
      "Disconnect"   = $this.Disconnect
      "Printers"     = $this.Printers
      "Scan Network" = $this.ScanNetwork
      
    }

    $this.Attributes = Invoke-ProgramAttributes

    $this.Attributes.Status("Loading system requirements ... ", 'Fast')

    $this.UserProfile = Invoke-UserProfile
    $this.LocalComponent = Invoke-LocalComponents
    $this.NetworkComponent = Invoke-NetworkComponents

    Clear-Host
    $this.Attributes.Status("Loaded succesfully", "normal")
  }

  [System.Void] Load() {
    $continue = $true

    # check cache
    $isCacheExpired = $this.NetworkComponent.IsCacheExpired()

    if ($isCacheExpired) {
      $this.Attributes.Status("Refreshing connection record. This may take a while. Please wait ...", 'fast')

      $this.ScanNetwork()

    }

    do {

      Clear-Host

      $title = "`tPROGRAM MENU`n"

      $keys = $this.MENU.Keys -as [array]

      $selected = ($this.Attributes.MenuOptions($Keys, $title, 'Exit Program'))

      Clear-Host

      if ($selected -eq -1) {
        Write-Host "Program Exit."
        Exit
      }

      $this.MENU[$keys[$selected]].Invoke()

    }while ($continue)
  }

  [System.Void] hidden Reconnect() {

    Clear-Host

    Write-Host "`tRECONNECTING COMPONENTS`n"

    $Locals = $this.LocalComponent.Get('all')
    $Users = $this.UserProfile.RemovedDuplicates()
    [System.Object]$ComponentList = [pscustomobject] @{
      Recorded   = [System.Collections.ArrayList]::new()
      UnRecorded = [System.Collections.ArrayList]::new()
    }

    $ComponentList = $this.Attributes.CreateReconnectObjects($Locals, $Users)
    $ReconnectingResult = [System.Collections.ArrayList]::new()

    if (-not $ComponentList.Recorded.Count -and -not $ComponentList.UnRecorded.Count) {
      $this.Attributes.Status("No components are connected. Established a connection first.", "Normal")

      return
    }

    # profile list to be inserted raw in profile
    $profileList = @()

    foreach ($Component in $ComponentList.Recorded) {

      $Record = $Component.Record

      $Name = $Record.DisplayName
      $NewIP = $null

      try {
        $NewIP = ([System.Net.DNS]::GetHostAddresses($Record.ConnectionOwner) |
          Where-Object { $_.AddressFamily -eq "InterNetwork" } |
          Select-Object IPAddressToString)[0].IPAddressToString -as [string]
      }
      catch {
        $ReconnectingResult += [PSCustomObject]@{
          Component = $Record
          Result    = Invoke-OperationStatus `
            -Status Error `
            -Message "Not available."
        }

        continue
      }

      $newSource = "\\$NewIP\$Name"

      # Remove excess duplicates that are not active
      if (-not $Component.Local) {

        $this.Attributes.Status("Adding $Name connection ...", "Fast")
        $result = $this.NetworkComponent.Connect($Record)

        if ($result.Status -eq 'Success') {
          $this.Attributes.Status("$Name connection added.", "Fast")
          $profileList += $Record

          if ($Record.AdditionalInfo -eq 'Default') {
            $this.LocalComponent.SetDefaultPrinter($Record.SourcePath)
          }

          $ReconnectingResult += [PSCustomObject]@{
            Component = $Record
            Result    = Invoke-OperationStatus `
              -Status Success `
              -Message "Connection retrieve."
          }
          continue
        }
        else {
          $this.Attributes.Status($result.Info.Message, "Fast")
        }
      }
      else {

        $duplicateFound = $false

        $this.Attributes.Status("Checking $Name", "Fast")
        foreach ($Local in $Component.Local) {
          if ($Record.SourcePath -eq $Local.SourcePath) {
            if ($Local.Type -eq 'print') { if ($Local.AdditionalInfo -eq 'Default') { $Record.AdditionalInfo = 'Default' } }
            continue
          }
          $duplicateFound = $true
          $this.LocalComponent.Remove($Local)
        }

        if ($duplicateFound) {
          $this.Attributes.Status("Duplicate remove.", "Fast")
        }
        else {
          $this.Attributes.Status("No duplicates are found.", "Fast")
        }
      }

      if ($newSource -eq $Record.SourcePath) {
        $profileList += $Record

        $ReconnectingResult += [PSCustomObject]@{
          Component = $Record
          Result    = Invoke-OperationStatus `
            -Status Success `
            -Message "Active connection"
        }

        $this.Attributes.Status("Skipping $Name since connection is still active.", "Fast")
        continue
      }

      $this.Attributes.Status("Attempting to reconnect $Name ...", "Fast")

      $this.LocalComponent.Remove($Record)

      $Record.SourceIPAddress = $NewIP
      $Record.SourcePath = $newSource

      $Result = $this.NetworkComponent.Connect($Record)

      if ($Result.Status -eq 'Error') {
        $this.Attributes.Status($Result.Info.Message)
      }
      else {
        $profileList += $Record
        $this.Attributes.Status("$Name is sucessfully reconnected.", "Fast")
      }

      $ReconnectingResult += [PSCustomObject]@{
        Component = $Record
        Result    = $Result
      }
    }

    foreach ($UnRecorded in $ComponentList.UnRecorded) {
      # for components that are connected directly

      $Name = $UnRecorded.DisplayName

      $this.Attributes.Status("Adding $Name to record.", "Fast")

      $isActive = $false

      if ($UnRecorded.Type -eq 'Disk') {
        $isActive = Test-Path $UnRecorded.SourcePath
      }
      elseif ($UnRecorded.Type -eq 'Print') {
        $printer = Get-Printer -Name $UnRecorded.SourcePath

        $isActive = $printer.PrinterStatus -eq 'Normal'
      }

      if (-not $isActive) {
        $this.LocalComponent.RemoveMapDrive($UnRecorded)

        $ReconnectingResult += [PSCustomObject]@{
          Component = $UnRecorded
          Result    = Invoke-OperationStatus `
            -Status Success `
            -Message "Invalid connection."
        }
        continue
      }

      # for successful test connections, proceed to reconnect
      $UnRecorded.ConnectionOwner = (Resolve-DnsName $UnRecorded.SourceIPAddress -ErrorAction SilentlyContinue).NameHost

      $profileList += $UnRecorded

      $ReconnectingResult += [PSCustomObject]@{
        Component = $UnRecorded
        Result    = Invoke-OperationStatus `
          -Status Success `
          -Message "Added"
      }

      $this.Attributes.Status("$Name successfully added.", "Fast")
    }

    # write to user profile
    $this.UserProfile.RecordRaw($profileList, 'all')

    Clear-Host

    $display = "`tRECONNECTING RESULT`n"

    $ReconnectingResult | ForEach-Object {
      $display += "$($_.Component.DisplayName)`t$($_.Result.Info.Message)`n"
    }

    foreach ($index in @(5..1)) {

      Clear-Host

      Write-Host $display
      Write-Host "Back to menu in $index"
      Start-Sleep -Seconds 1

    }
  }

  [System.Void] hidden Connect() {

    do {

      $title = "`tCONNECT NETWORK CONNECTION`n"

      $shared = $this.NetworkComponent.Get('all')

      if (-not $shared -or -not $shared.Count) {
        $this.Attributes.Status("No shared component available. Try to scan the network and try again.")
        return
      }

      $selected = $this.Attributes.MenuOptions($this.Attributes.ToArray($shared), $title, 'Back to Menu')

      # back to menu
      if ($selected -eq -1) { break }

      $selected = $shared[$selected]

      Clear-Host
      Write-Host "Connecting $($selected.DisplayName)`n"

      # for selecting new connection for disk type component, prompt for a drive name
      if ($selected.Type -eq 'Disk') {

        $MapName = $this.Attributes.InputMapName()

        if ($MapName -eq 'Cancelled') { continue } # go back to selecting components

        $selected.AdditionalInfo = $MapName
      }

      $RetryCount = 0

      $ConnectionResult = @{}

      do {

        # guard for breaking possible infinite loop
        if ($RetryCount -gt 3) {
          $RetryCount = 0
          break
        }

        $RetryCount++

        $ConnectionResult = $this.NetworkComponent.Connect($selected)

        # Err for possible duplication of map name
        if ($ConnectionResult.Info.Code -eq -2147467259) {

          $override = $null
          $isInValid = $false

          do {

            Clear-Host

            $override = (Read-Host -Prompt "Overide drive name $($Selected.AdditionalInfo):? [Y] Yes [N] No").ToUpper()

            $isInvalid = (-not $override -or $override -notmatch "^[a-zA-Z]{1}$" -or (@('Y', 'N') -notcontains $override))

            if ($isInValid ) {
              $this.Attributes.Status("Invalid selection. Try again.", "Normal")
              continue
            }

          }while ($isInValid)

          if ($override -eq 'N') {
            $RetryCount = 0
            break
          }
          elseif ($override -eq 'Y') {
            $this.LocalComponent.Remove($selected)
            $this.UserProfile.Remove($selected)
            continue
          }
        }

        if ($ConnectionResult.Status -eq 'Success') {
          $this.UserProfile.Record($selected)
          $this.LocalComponent.Set($selected)
          break
        }
      }while ($true)

      Clear-Host

      $this.Attributes.Status($ConnectionResult.Info.Message, "Normal")

    }while ($true)
  }

  [System.Void] hidden Disconnect() {

    do {

      $title = "`tDISCONNECT NETWORK COMPONENT`n"

      $components = $this.UserProfile.Get('all')

      if (-not $components.count) {
        $this.Attributes.Status("No components ared connected. Please established a connection first.", "Normal")
        break
      }

      $selected = $this.Attributes.MenuOptions($this.Attributes.ToArray($components), $title, 'Back to Menu')

      # back to menu
      if (($selected -eq -1)) {
        break
      }

      $selected = $components[$selected]

      Clear-Host
      Write-Host "Attempt to disconnect $($selected.DisplayName)`n"

      $DisconnectionResult = $this.LocalComponent.Remove($selected)

      if ($DisconnectionResult.Status -eq 'Error') {
        if ($DisconnectionResult.Info.Code -eq -2146233087) {
          # error if map name is not found
          $this.UserProfile.Remove($selected)
        }
        $this.Attributes.Status($DisconnectionResult.Info.Message, "Normal")
      }
      elseif ($DisconnectionResult.Status -eq 'Success') {
        $this.UserProfile.Remove($selected)
        $this.Attributes.Status("Disconnected successfully.", "Normal")
      }

    }while ($true)
  }

  [System.Void] hidden Printers () {

    do {

      $title = "`tSET DEFAULT PRINTER`n"

      $components = $this.LocalComponent.Get('print')

      $selected = $this.Attributes.MenuOptions($this.Attributes.ToArray($components), $title, 'Back to Menu')

      # back to menu
      if ($selected -eq -1) {
        break
      }

      $selected = $components[$selected]

      Clear-Host
      Write-Host "Setting printer $($selected.DisplayName) to default ...`n"

      $printerResult = $this.LocalComponent.SetDefaultPrinter($selected.SourcePath)

      if ($printerResult.Status -eq 'Error') {
        $this.Attributes.Status("An error occurs in setting $($selected.DisplayName) to default. Please check printer.", "Normal")

        continue
      }

      $printerList = @()

      $this.UserProfile.Get('print') | ForEach-Object {
        if ($_.DisplayName -eq $selected.DisplayName) { return }
        $_.AdditionalInfo = ''
        $printerList += $_
      }

      $selected.AdditionalInfo = 'Default'
      $printerList += $selected

      $this.UserProfile.RecordRaw($printerList, 'print')

      $this.Attributes.Status("Printer set successfully.", "Normal")


    }while ($true)
  }

  [System.Void] hidden ScanNetwork() {
    Clear-Host

    $this.Attributes.Status("Scanning network...", "fast")

    $this.NetworkComponent.PerformScan()

    $Result = @{}

    do {

      $Result = $this.NetworkComponent.ScanStatus()

      if (@('success', 'error') -contains $Result.Status) { break }

      Start-Sleep -Seconds 1

    }while ($true)

    $sharedComponents = $this.NetworkComponent.Get('all')

    Clear-Host
    $this.Attributes.Status($Result.Message, 'normal')

    Clear-Host
    # display shared components
    if ($sharedComponents.Count) {
      $display = "SCANNED SHARED COMPONENTS`n"

      foreach ($shared in $sharedComponents) {
        $display += "$($shared.DisplayName)`n"
      }

      $this.Attributes.Status($display, 'normal')
    }

  }
}

$Program = [NetworkMapper]::new()
$Program.Load()

Write-Host $script:_Objects
