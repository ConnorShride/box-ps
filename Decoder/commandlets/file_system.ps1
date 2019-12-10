# ADVANCED FUNCTION ALL PARAMS BOUND
function Remove-Item {

    param(
        [Parameter(ValueFromPipeline=$true)][System.Management.Automation.PSCredential] $Credential,
        [String[]] $Exclude,
        [String[]] $Include,
        [String[]] $Stream,
        [String] $Filter,
        [Parameter(ValueFromPipeline=$true,Position=0)][String[]] $Path,
        [Parameter(ValueFromPipeLine=$true)][Alias("PSPath")][String[]] $LiteralPath,
        [Switch] $Recurse,
        [Switch] $Force,
        [Alias("cf")][Switch] $Confirm,
        [Alias("wi")][Switch] $WhatIf
    )

    $behaviorProps = @{ "paths" = @() }

    if ($PSBoundParameters.ContainsKey("Path")) {
        $behaviorProps["paths"] = $Path
    }
    elseif ($PSBoundParameters.ContainsKey("LiteralPath")) {
        $behaviorProps["paths"] = $LiteralPath
    }

    RecordAction $([Action]::new(@("file_system"), "[Microsoft.PowerShell.Management] Remove-Item", `
        $behaviorProps, $MyInvocation))
}

# ADVANCED FUNCTION ALL PARAMS BOUND
function Get-Item {

    param(
        [Parameter(ValueFromPipeline=$true)][System.Management.Automation.PSCredential] $Credential,
        [String[]] $Exclude,
        [String[]] $Include,
        [String[]] $Stream,
        [String] $Filter,
        [Switch] $Force,
        [Parameter(ValueFromPipeline=$true,Position=0)][String[]] $Path,
        [Parameter(ValueFromPipeLine=$true)][Alias("PSPath")][String[]] $LiteralPath
    )

    $behaviorProps = @{ "paths" = @() }

    if ($PSBoundParameters.ContainsKey("Path")) {
        $behaviorProps["paths"] = $Path
    }
    elseif ($PSBoundParameters.ContainsKey("LiteralPath")) {
        $behaviorProps["paths"] = $LiteralPath
    }

    RecordAction $([Action]::new(@("file_system"), "[Microsoft.PowerShell.Management] Get-Item", `
        $behaviorProps, $MyInvocation))

    return Microsoft.PowerShell.Management\Get-Item @PSBoundParameters
}

# ADVANCED FUNCTION ALL PARAMS BOUND
function Set-Content {
    
    param(
        [Parameter(ValueFromPipeline=$true)][System.Management.Automation.PSCredential] $Credential,
        [Parameter(ValueFromPipeLine=$true)][Alias("PSPath")][String[]] $LiteralPath,
        [Parameter(ValueFromPipeline=$true,Position=0)][String[]] $Path,
        [Parameter(ValueFromPipeline=$true,Position=1)][Object[]] $Value,
        [Alias("wi")][Switch] $WhatIf,
        [System.Text.Encoding] $Encoding,
        [Switch] $AsByteStream,
        [Alias("cf")][Switch] $Confirm,
        [String] $Filter,
        [Switch] $Force,
        [Switch] $NoNewLine,
        [Switch] $PassThru,
        [String[]] $Exclude,
        [String[]] $Include,
        [String[]] $Stream
    )

    $behaviorProps = @{ "paths" = @() }

    if ($PSBoundParameters.ContainsKey("Path")) {
        $behaviorProps["paths"] = $Path
    }
    elseif ($PSBoundParameters.ContainsKey("LiteralPath")) {
        $behaviorProps["paths"] = $LiteralPath
    }

    RecordAction $([Action]::new(@("file_system"), "[Microsoft.PowerShell.Management] Set-Content", `
        $behaviorProps, $MyInvocation))
}

# ADVANCED FUNCTION ALL PARAMS BOUND
function Set-Location {

    param(
        [parameter(ValueFromPipeline=$true)][Alias("PSPath")][String] $LiteralPath,
        [Switch] $PassThru,
        [parameter(Position=0,ValueFromPipeline=$true)][String] $Path,
        [parameter(ValueFromPipeline=$true)][String] $StackName
    )

    $behaviorProps = @{ "paths" = @() }
 
    if ($PSBoundParameters.ContainsKey("Path")) {
        $behaviorProps["paths"] = @($Path)
    }
    elseif ($PSBoundParameters.ContainsKey("LiteralPath")) {
        $behaviorProps["paths"] = @($LiteralPath)
    }

    RecordAction $([Action]::new(@("file_system"), "[Microsoft.PowerShell.Management] Set-Location",
        $behaviorProps, $MyInvocation))
}

# ADVANCED FUNCTION ALL PARAMS BOUND
function New-Item {

    param(
        [Parameter(ValueFromPipeline=$true)][System.Management.Automation.PSCredential] $Credential,
        [Parameter(ValueFromPipeline=$true,Position=0)][String[]] $Path,
        [Parameter(ValueFromPipeline=$true)][Alias("Target")][Object] $Value,
        [Parameter(ValueFromPipeline=$true)][String] $ItemType,
        [Parameter(ValueFromPipeline=$true)][String] $Name,
        [Alias("wi")][Switch] $WhatIf,
        [Alias("cf")][Switch] $Confirm,
        [Switch] $Force
    )

    $behaviorProps = @{ "paths" = @() }

    if ($PSBoundParameters.ContainsKey("Path")) {
        $behaviorProps["paths"] = $Path
    }
    elseif ($PSBoundParameters.ContainsKey("Name")) {
        $behaviorProps["paths"] = $Name
    }

    RecordAction $([Action]::new(@("file_system"), "[Microsoft.PowerShell.Management] New-Item", `
        $behaviorProps, $MyInvocation))
}

# replicate the mkdir that's on windows. On linux, it's an alias for /bin/mkdir
# ADVANCED FUNCTION ALL PARAMS BOUND
function mkdir {

    param(
        [Parameter(ValueFromPipeline=$true)][System.Management.Automation.PSCredential] $Credential,
        [Parameter(ValueFromPipeline=$true,Position=0)][String[]] $Path,
        [Alias("wi")][Switch] $WhatIf,
        [Alias("cf")][Switch] $Confirm,
        [Switch] $Force
    )

    $behaviorProps = @{ 
        "paths" = $Path
    }

    RecordAction $([Action]::new(@("file_system"), "[Microsoft.PowerShell.Core] mkdir", `
        $behaviorProps, $MyInvocation))
}

# not fully implemented
function Get-ChildItem {

    param(
        [String[]] $Path
    )

    $behaviorProps = @{
        "paths" = $Path
    }

    RecordAction $([Action]::new(@("file_system"), "[Microsoft.PowerShell.Management] Get-ChildItem", `
        $behaviorProps, $MyInvocation))
}

# not fully implemented
function Test-Path {

    param(
        [String[]] $Path
    )

    $behaviorProps = @{
        "paths" = $Path
    }

    RecordAction $([Action]::new(@("file_system"), "[Microsoft.PowerShell.Management] Test-Path", `
        $behaviorProps, $MyInvocation))
}

# not fully implemented
function Get-Content {

    param(
        [Alias("PSPath")][String[]] $LiteralPath,
        [String[]] $Path
    )

    $behaviorProps = @{ "paths" = @() }

    if ($PSBoundParameters.ContainsKey("Path")) {
        $behaviorProps["paths"] = $Path
    }
    elseif ($PSBoundParameters.ContainsKey("LiteralPath")) {
        $behaviorProps["paths"] = $LiteralPath
    }

    RecordAction $([Action]::new(@("file_system"), "[Microsoft.PowerShell.Management] Get-Content", `
        $behaviorProps, $MyInvocation))
}