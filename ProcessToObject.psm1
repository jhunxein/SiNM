function Invoke-ProcessToTemplate {
  Param(
    [Parameter(Mandatory)]
    [System.String]$DisplayName,

    [Parameter(Mandatory)]
    [System.String]$Type,

    [Parameter(Mandatory)]
    [System.String]$SourceIPAddress,

    [System.String]$ConnectionOwner,

    [System.String]$Info,

    [switch]$Record = $false
  )

  if ($Record) {

    $data = [PSCustomObject]@{
      Key             = New-Guid
      DisplayName     = $DisplayName 
      Type            = $Type
      ConnectionOwner = $ConnectionOwner
      SourcePath      = "\\$($SourceIPAddress)\$($DisplayName)"
      SourceIPAddress = $SourceIPAddress
      AdditionalInfo  = $Info
    }

  }
  else {

    $data = [PSCustomObject]@{
      DisplayName     = $DisplayName 
      Type            = $Type
      ConnectionOwner = $ConnectionOwner
      SourcePath      = "\\$($SourceIPAddress)\$($DisplayName)"
      SourceIPAddress = $SourceIPAddress
      AdditionalInfo  = $Info
    }

  }

  return $data
}

function Invoke-OperationStatus {
  Param(
    [ValidateSet("Success", "Error")]
    [System.String]$Status = "Success",
    [System.String]$Message = $null,
    [System.String]$Code = $null
  )

  return [pscustomobject] @{
    Status = $Status
    Info   = [pscustomobject] @{
      Message = $Message
      Code    = $Code
    }
  }

}

function Get-ConnectionOwner {
  Param(
    [Parameter(Mandatory)]
    [System.String]$IPAddress
  )

  return (Resolve-DnsName $list.IPAddress -ErrorAction SilentlyContinue).NameHost

}

Export-ModuleMember -Function Invoke-ProcessToTemplate, Invoke-OperationStatus, Get-ConnectionOwner