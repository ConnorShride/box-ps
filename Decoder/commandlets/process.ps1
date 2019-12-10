<# 
process objects make the output huge and it's not that useful
just keep the string representation
#> 
function FlattenProcessObjects {

    param(
        [System.Diagnostics.Process[]] $ProcessList
    )

    $strings = @()

    $count = 0;
    while ($count -lt $ProcessList.Count) {
        $strings += $ProcessList[$count].ToString()
        $count++
    }

    return $strings
}

# ADVANCED FUNCTION ALL PARAMS BOUND
function Get-Process {

    param(
        [Parameter(Position=0)][Alias("ProcessName")][String[]] $Name,
        [Parameter(ValueFromPipeline=$true)][Alias("PID")][Int32[]] $Id,
        [Parameter(ValueFromPipeline=$true)][System.Diagnostics.Process[]] $InputObject,
        [Switch][Alias("FV","FVI")] $FileVersionInfo,
        [Switch] $IncludeUserName,
        [Switch] $Module
    )

    $behaviorProps = @{ "processes" = @() }

    if ($PSBoundParameters.ContainsKey("Name")) {
        $behaviorProps["processes"] = $Name
    }
    elseif ($PSBoundParameters.ContainsKey("Id")) {
        $behaviorProps["processes"] = $Id
    }

    if ($PSBoundParameters.ContainsKey("InputObject")) {
        $PSBoundParameters["InputObject"] = FlattenProcessObjects $PSBoundParameters["InputObject"]
    }

    RecordAction $([Action]::new(@("process"), "Get-Process", 
        "Microsoft.PowerShell.Management\Get-Process", $behaviorProps, $MyInvocation))

    return Microsoft.PowerShell.Management\Get-Process @PSBoundParameters
}

# ADVANCED FUNCTION ALL PARAMS BOUND
function Stop-Process {

    param(
        [Parameter(Position=0, ValueFromPipeline=$true)][System.Diagnostics.Process[]] $InputObject,
        [Parameter(ValueFromPipeline=$true)][Alias("ProcessName")][String[]] $Name,
        [Parameter(Position=0, ValueFromPipeline=$true)][Int32[]] $Id,
        [Alias("cf")][Switch] $Confirm,
        [Switch] $Force,
        [Switch] $PassThru,
        [Alias("wi")][Switch] $WhatIf
    )

    $behaviorProps = @{ "processes" = @() }

    if ($PSBoundParameters.ContainsKey("InputObject")) {

        foreach ($process in $InputObject) {
            $behaviorProps["processes"] += $process.ProcessName
        }

        $PSBoundParameters["InputObject"] = FlattenProcessObjects $PSBoundParameters["InputObject"]
    }
    elseif ($PSBoundParameters.ContainsKey("Name")) {
        $behaviorProps["processes"] = $Name
    }
    elseif ($PSBoundParameters.ContainsKey("Id")) {
        $behaviorProps["processes"] = $Id
    }

    RecordAction $([Action]::new(@("process"), "Stop-Process", 
        "Microsoft.PowerShell.Management\Stop-Process", $behaviorProps, $MyInvocation))
}

# ADVANCED FUNCTION ALL PARAMS BOUND
function Start-Sleep {

    param(
        [parameter(ValueFromPipeline=$true)][Alias("m","ms")][Int32] $Milliseconds,
        [parameter(ValueFromPipeline=$true,Position=0)][double] $Seconds
    )

    $behaviorProps = @{
        "processes" = @("self")
    }

    RecordAction $([Action]::new(@("process"), "Start-Sleep", 
        "Microsoft.PowerShell.Utility\Start-Sleep", $behaviorProps, $MyInvocation))
}