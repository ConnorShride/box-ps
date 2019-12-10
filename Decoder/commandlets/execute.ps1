# ADVANCED FUNCTION ALL PARAMS BOUND
function Invoke-Expression {

    param(
        [Parameter(Position=0, ValueFromPipeline=$true)][String] $Command
    )

    $behaviorProps = @{
        "script" = $Command
    }

    RecordLayer($Command)
    RecordAction $([Action]::new(@("script_exec"), "Invoke-Expression",
        "Microsoft.PowerShell.Utility\InvokeExpression", $behaviorProps, $MyInvocation))
}

function Start-Process {
        
    param(
        [Alias("PSPath","Path")][String] $FilePath
    )

    $behaviorProps = @{
        "files" = @($FilePath)
    }

    RecordAction $([Action]::new(@("file_exec"), "Start-Process", 
        "Microsoft.PowerShell.Management\Start-Process", $behaviorProps, $MyInvocation))
}

# ADVANCED FUNCTION ALL PARAMS BOUND
function Invoke-Item {
    
    param(
        [Alias("cf")][Switch] $Confirm,
        [Parameter(ValueFromPipeline=$true)][System.Management.Automation.PSCredential] $Credential,
        [String[]] $Exclude,
        [String] $Filter,
        [String[]] $Include,
        [Parameter(ValueFromPipeLine=$true)][Alias("PSPath")][String[]] $LiteralPath,
        [Parameter(ValueFromPipeline=$true,Position=0)][String[]] $Path,
        [Alias("wi")][Switch] $WhatIf
    )

    $behaviorProps = @{ "files" = @() }

    if ($PSBoundParameters.ContainsKey("Path")) {
        $behaviorProps["files"] = $Path
    }
    elseif ($PSBoundParameters.ContainsKey("LiteralPath")) {
        $behaviorProps["files"] = $LiteralPath
    }

    RecordAction $([Action]::new(@("file_exec"), "Invoke-Item", 
        "Microsoft.PowerShell.Management\Invoke-Item", $behaviorProps, $MyInvocation))
}