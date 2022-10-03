class ProgramAttributes {

  [System.Object] CreateReconnectObjects([System.Object[]]$LocalComponents, [System.Object[]]$RecordComponents) {

    [System.Object]$result = [pscustomobject] @{Recorded = @() ; UnRecorded = @() }
    $loopCount = 0

    $LocalComponents = $LocalComponents | Sort-Object -Property DisplayName
    $RecordComponents = $RecordComponents | Sort-Object -Property DisplayName

    $LocalComponentLength = $LocalComponents.Length

    foreach ($_ in $RecordComponents) {
      $outerRow = $_
      $tmpRecorded = [pscustomobject]@{ Record = $_ ; Local = @() }
      $tmpUnRecorded = @()

      for ($_index = $loopCount; $_index -lt $LocalComponentLength; $_index++) {

        $innerFirstRow = $LocalComponents[$_index]
        $innerSecondRow = $LocalComponents[$_index + 1]

        $isInnerFirstRowMatch = $innerFirstRow.DisplayName -eq $outerRow.Displayname -and $innerFirstRow.Type -eq $outerRow.Type

        $isInnerSecondRowMatch = $innerSecondRow.DisplayName -eq $outerRow.Displayname -and $innerSecondRow.Type -eq $outerRow.Type


        if ($isInnerFirstRowMatch) {
          $tmpRecorded.Local += $innerFirstRow
        }
        else {

          if (-not $isInnerSecondRowMatch) {
            $loopCount = $_index
            break
          }

          $tmpUnRecorded += $innerFirstRow
          $_index++
          $loopCount = $_index

        }

        $loopCount++
        if (-not $isInnerFirstRowMatch -and $isInnerSecondRowMatch) {
          $tmpRecorded.Local += $innerSecondRow
          continue
        }

        break
      }

      $result.Recorded += $tmpRecorded
      $result.UnRecorded += $tmpUnRecorded
    }

    if ((-not $RecordComponents.Count -and $LocalComponents.Count -gt 0) -or ($loopCount -lt $LocalComponents.Count)) {
      for ($_index = $loopCount; $_index -lt $LocalComponents.Count; $_index++) {
        $result.UnRecorded += $LocalComponents[$_index]
      }
    }

    return $result
  }

  [System.String] InputMapName() {

    $Name = ''
    $isNotValid = $false

    do {
      $Name = (Read-Host -Prompt "Map name (enter number 0 to exit)" )

      if ($Name -eq 0) {
        $this.Status("`nAn attempt to connect is cancelled.", "Normal")
        return 'Cancelled'
      }

      $Name = $Name.ToUpper()

      $isNotValid = (-not $Name -or -not($Name -match '^[a-zA-Z]{1}') -or -not ($Name.Length -eq 1))

      if ($isNotValid) {
        $this.Status("Invalid name. Please try again.", "Normal")
      }

    } while ( $isNotValid )

    return $Name
  }

  [System.Collections.ArrayList] ToArray([System.Object[]]$Objects) {
    $toArr = @()

    $Objects.ForEach( {
        $toArr += $_.DisplayName
      }
    )

    return $toArr
  }

  [System.Void] Status([System.String]$Status, [System.String]$Type) {
    $time = 0
    if ($Type -eq 'Fast') {
      $time = 1
    }
    elseif ($Type -eq 'Normal') {
      $time = 2
    }
    elseif ($Type -eq 'Slow') {
      $time = 3
    }
    Write-Host $Status
    Start-Sleep -Seconds $time
  }

  [int] MenuOptions ([System.Object]$Objects, [System.String]$Title, [System.String]$BackText) {

    # Write-Host $Title
    $display += $Title
    $display += $this._MenuList($Objects, $BackText)

    return $this._ChooseMenu($display, $Objects.Count)
  }

  [int] hidden _ChooseMenu ([System.String]$Menu, [System.Int16]$ArrayLength) {
    $select = -1
    $isInvalid = $false

    do {
      Clear-Host

      Write-Host $Menu

      if ($isInvalid) {
        Write-Warning "Invalid selection. Please select again.`n"
        Start-Sleep -Seconds 1
      }

      $select = Read-Host -Prompt "Select"

      $isInvalid = if ((0..$ArrayLength -notcontains $select) -or (-not $select)) { $true }else { $false }

      if ($isInvalid) { continue }

      if ($select -eq 0) {
        $select = -1
      }
      else {
        $select = $select - 1
      }

    } while ( $isInvalid)

    return $select
  }

  [System.String] hidden _MenuList ([System.Object]$Objects, [System.String]$BackText) {

    $display = "`n[ 0 ] $BackText`n"

    if (-not $Objects.Count) {
      Throw "There is no data available for display."
    }

    $index = 1
    foreach ($object in $Objects) {

      $display += "[ $index ] $object`n"

      $index++
    }

    return $display
  }
}

function Invoke-ProgramAttributes {
  [ProgramAttributes]::new()
}

Export-ModuleMember -Function Invoke-ProgramAttributes