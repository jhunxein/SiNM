class UserProfile {

  [System.String] hidden $_FullPath
  [System.Object[]] hidden $_UserProfile = [System.Collections.ArrayList]::new()

  UserProfile() {
    $this._FullPath = Join-Path -Path $global:Home -ChildPath "mapper_profile.json"
    $this._UserProfile = $this._GetUserProfile()
  }

  [System.Object[]] hidden _GetUserProfile() {

    [System.Object]$userProfile = @() 

    if (-not (Test-Path $this._FullPath)) {
      # if file is not created, create a new one
      New-Item `
        -Path $this._FullPath `
        -Value '[]' `
        -ItemType 'File' `
        -Force | Out-Null
    }
    else {
      $userProfile = Get-Content `
        -Path $this._FullPath | ConvertFrom-Json

      if ($null -eq $userProfile) {
        $userProfile = @()
      }

    }

    return $userProfile
  }

  [System.Object[]] Get([System.String]$Type) {

    [System.Object[]] $ReturnObject = @()

    if ($Type -eq 'all') {
      $ReturnObject = $this._UserProfile
    }
    elseif ($Type -eq 'Print') {
      $ReturnObject = $this._UserProfile | Where-Object { $_.Type -eq 'Print' }
    }
    elseif ($Type -eq 'Disk') {
      $ReturnObject = $this._UserProfile | Where-Object { $_.Type -like 'Dis*' }
    }

    return $ReturnObject | Sort-Object -Property DisplayName
  }

  [System.Void] Record([System.Object]$UserProfile) {

    $UserProfileGroup = $this.get($UserProfile.Type)

    $MatchProfile = $UserProfileGroup | Where-Object { $_.DisplayName -eq $UserProfile.DisplayName }

    if (-not $UserProfile.Key) {
      $UserProfile | Add-Member -Name "Key" -Value (New-Guid).Guid -MemberType NoteProperty -TypeName "System.String"
    }

    if ((-not $MatchProfile) -or (-not $MatchProfile.Count)) {
      $UserProfileGroup += $UserProfile
    }
    else {
      $isFound = $false
      
      for ($i = 0; $i -lt $UserProfileGroup.Count ; $i++) {
        $row = $UserProfileGroup[$i]

        if ($row.DisplayName -ne $UserProfile.DisplayName) { continue }

        $isFound = $true
        $UserProfileGroup[$i] = $UserProfile # replace match object
        break
      }

      if (-not $isFound) {
        $UserProfileGroup += $UserProfile
      }
    }

    $this._Set($UserProfile.Type, $UserProfileGroup)
  }

  [System.Void] hidden _Set([System.Object]$IncomingProfileType, [System.Object[]]$UserProfiles) {

    $remainingProfileType = if ($IncomingProfileType -eq 'Print') { 'disk' } else { 'print' }

    if (-not $UserProfiles) {
      $Merge = $this.Get($remainingProfileType)
    }
    else {
      $Merge = $this.Get($remainingProfileType) + $UserProfiles
    }
    
    $this._UserProfile = $this._Write($Merge)
  }

  [System.Void] Remove([System.Object]$UserProfile) {

    $tmpUserProfile = @()

    if ($UserProfile.Type -eq 'Disk') {

      $tmpUserProfile += $this.Get($UserProfile.Type) | 
      Where-Object { $_.AdditionalInfo -ne $UserProfile.AdditionalInfo }

    }
    elseif ($UserProfile.Type -eq 'Print') {
      $tmpUserProfile += $this.Get($UserProfile.Type) | 
      Where-Object { $_.DisplayName -ne $UserProfile.DisplayName -and $_.ConnectionOwner -ne $UserProfile.ConnectionOwner }
    }

    $this._Set($UserProfile.Type, $tmpUserProfile)
  }

  # only one object should be allowed
  # key - @{SourcePath = String}
  [System.Object] hidden GetMatchObject([System.Object]$Object) {

    $key = $Object.Keys

    if ($key.Count -gt 1) {
      Throw "Object key should only be one."
    }
    
    return $this._UserProfile | 
    Where-Object { $_.($key[0]) -eq $Object.($key[0]) }
  }

  [System.Object[]] hidden _Write([System.Object[]]$UserProfiles) {

    $ErrorActionPreference = 'SilentlyContinue'

    if ( -not $UserProfiles) {
      "[]" | Out-File $this._FullPath -Encoding utf8
    }
    elseif ($UserProfiles.Count -eq 1) {
      $UserProfiles |
      ConvertTo-Json -AsArray | 
      Out-File $this._FullPath -Encoding utf8
    }
    else {
      $UserProfiles |
      ConvertTo-Json | 
      Out-File $this._FullPath -Encoding utf8
    }

    return $UserProfiles
  }

  [System.Object[]]GetPrinters() {
    return $this._UserProfile | Where-Object { $_.Type -eq 'Print' }
  }

  [System.Object[]]GetDrives() {
    return $this._UserProfile | Where-Object { $_.Type -eq 'Dis' }
  }

  [System.Void]SetDefaultPrinter([System.String]$PrinterSource) {

    $printer = $this.GetMatchObject(@{SourcePath = $PrinterSource })

    $printer.AdditionalInfo = "Default"

    $this.Record($printer)
  }

  # used in reconnecting menu
  [System.Object[]] RemovedDuplicates() {
    $newProfile = $this.Get('all') | Sort-Object DisplayName -Unique

    return $this._Write($newProfile) # write the filtered profile
  }

  [System.Void] RecordRaw([System.Object[]]$UserProfiles, [System.String]$Type) {

    $Merge = @()

    if ($Type -eq 'all') {
      $Merge = $UserProfiles
    }
    elseif ($Type -eq 'print') {
      $Merge = $this.Get('disk') + $UserProfiles
    }
    elseif ($Type -eq 'disk') {
      $Merge = $this.Get('print') + $UserProfiles
    }

    # append keys in every profile
    $Merge | ForEach-Object {
      if (-not $_.Key) {
        $_ | Add-Member -Name "Key" -Value (New-Guid).Guid -MemberType NoteProperty -TypeName 'System.String'
      }
    }

    $this._UserProfile = $this._Write($Merge)
  }
}

function Invoke-UserProfile {
  [UserProfile]::new()
}

Export-ModuleMember -Function Invoke-UserProfile