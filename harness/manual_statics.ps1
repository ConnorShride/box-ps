# gets the script being passed in arguments to powershell.exe
# decodes encoded command if necessary
static [string] GetScriptFromArguments([string] $arguments) {

    $script = ""
    
    if (($flagNdx = $arguments.ToLower().IndexOf("-e")) -ne -1) {
        $cmdNdx = $arguments.IndexOf(' ', $flagNdx) + 1
        $encodedScript = $arguments.SubString($cmdNdx)
        $script = [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String($encodedScript))
    }
    elseif (($flagNdx = $arguments.ToLower().IndexOf("-c")) -ne 1) {
        $cmdNdx = $arguments.IndexOf(' ', $flagNdx) + 1
        $script = $arguments.SubString($cmdNdx)
    }

    return $script
}

static [System.Diagnostics.Process] Start([System.Diagnostics.ProcessStartInfo] $startInfo) {
    
    $behaviorProps = @{}

    # if powershell, treat this now as a script_exec rather than file_exec
    if ($startInfo.FileName.ToLower().Contains("powershell") -and $startInfo.Arguments) {

        $script = [BoxPSStatics]::GetScriptFromArguments($startInfo.Arguments)

        # record the action
        $behaviorProps["script"] = @($script)
        RecordAction $([Action]::new(@("script_exec"), "[System.Diagnostics.Process]::Start", $behaviorProps, $PSBoundParameters, $MyInvocation.Line, ""))

        # run the script
        $boxifiedScript = PreProcessScript $script
        Microsoft.PowerShell.Utility\Invoke-Expression $boxifiedScript
    }
    else {
        $behaviorProps["files"] = @($startInfo.FileName)
        RecordAction $([Action]::new(@("file_exec"), "[System.Diagnostics.Process]::Start", $behaviorProps, $PSBoundParameters, $MyInvocation.Line, ""))
    }

    return $null
}

static [System.Diagnostics.Process] Start([string] $fileName, [string] $arguments) {

    $behaviorProps = @{}
    
    # if powershell, treat this now as a script_exec rather than file_exec
    if ($fileName.ToLower().Contains("powershell") -and $arguments) {

        $script = [BoxPSStatics]::GetScriptFromArguments($arguments)

        # record the action
        $behaviorProps["script"] = @($script)
        RecordAction $([Action]::new(@("script_exec"), "[System.Diagnostics.Process]::Start", $behaviorProps, $PSBoundParameters, $MyInvocation.Line, ""))

        # run the script
        $boxifiedScript = PreProcessScript $script
        Microsoft.PowerShell.Utility\Invoke-Expression $boxifiedScript
    }
    else {
        $behaviorProps["files"] = @($fileName)
        RecordAction $([Action]::new(@("file_exec"), "[System.Diagnostics.Process]::Start", $behaviorProps, $PSBoundParameters, $MyInvocation.Line, ""))
    }

    return $null
}

static [System.Diagnostics.Process] Start([string] $fileName, [string] $arguments, [string] $userName, [securestring] $password, [string] $domain) {
    
    $behaviorProps = @{}

    # if powershell, treat this now as a script_exec rather than file_exec
    if ($fileName.ToLower().Contains("powershell") -and $arguments) {

        $script = [BoxPSStatics]::GetScriptFromArguments($arguments)

        # record the action
        $behaviorProps["script"] = @($script)
        RecordAction $([Action]::new(@("script_exec"), "[System.Diagnostics.Process]::Start", $behaviorProps, $PSBoundParameters, $MyInvocation.Line, ""))

        # run the script
        $boxifiedScript = PreProcessScript $script
        Microsoft.PowerShell.Utility\Invoke-Expression $boxifiedScript
    }
    else {
        $behaviorProps["files"] = @($fileName)
        RecordAction $([Action]::new(@("file_exec"), "[System.Diagnostics.Process]::Start", $behaviorProps, $PSBoundParameters, $MyInvocation.Line, ""))
    }
    
    return $null
}

static [void] Copy([byte[]] $source, [object] $destination, [object] $startIndex, [object] $length) {

    $CODE_DIR = "<CODE_DIR>"
    $WORK_DIR = "./working"
    $behaviorProps = @{}
    $behaviorProps["bytes"] = @($source)
    
    $extraInfo = ""
    $routineArg = $source
    $routineReturn = ""
    $routineCode = Microsoft.PowerShell.Management\Get-Content -Raw $CODE_DIR/harness/find_in_bytes_iocs.ps1
    Microsoft.PowerShell.Utility\Invoke-Expression $routineCode
    if ($routineReturn) {
        $extraInfo = $routineReturn
    }

    RecordAction $([Action]::new(@("memory_manipulation"), "[System.Runtime.InteropServices.Marshal]::Copy", $behaviorProps, $PSBoundParameters, $MyInvocation.Line, $extraInfo))
}

static [void] Copy([long[]] $source, [object] $destination, [object] $startIndex, [object] $length) {

    $CODE_DIR = "<CODE_DIR>"
    $WORK_DIR = "./working"
    $behaviorProps = @{}
    $behaviorProps["bytes"] = @($source)
    
    $extraInfo = ""
    $routineArg = $source
    $routineReturn = ""
    $routineCode = Microsoft.PowerShell.Management\Get-Content -Raw $CODE_DIR/harness/find_in_bytes_iocs.ps1
    Microsoft.PowerShell.Utility\Invoke-Expression $routineCode
    if ($routineReturn) {
        $extraInfo = $routineReturn
    }

    RecordAction $([Action]::new(@("memory_manipulation"), "[System.Runtime.InteropServices.Marshal]::Copy", $behaviorProps, $PSBoundParameters, $MyInvocation.Line, $extraInfo))
}

static [void] Copy([char[]] $source, [object] $destination, [object] $startIndex, [object] $length) {

    $CODE_DIR = "<CODE_DIR>"
    $WORK_DIR = "./working"
    $behaviorProps = @{}
    $behaviorProps["bytes"] = @($source)
    
    $extraInfo = ""
    $routineArg = $source
    $routineReturn = ""
    $routineCode = Microsoft.PowerShell.Management\Get-Content -Raw $CODE_DIR/harness/find_in_bytes_iocs.ps1
    Microsoft.PowerShell.Utility\Invoke-Expression $routineCode
    if ($routineReturn) {
        $extraInfo = $routineReturn
    }

    RecordAction $([Action]::new(@("memory_manipulation"), "[System.Runtime.InteropServices.Marshal]::Copy", $behaviorProps, $PSBoundParameters, $MyInvocation.Line, $extraInfo))
}

static [void] Copy([short[]] $source, [object] $destination, [object] $startIndex, [object] $length) {

    $CODE_DIR = "<CODE_DIR>"
    $WORK_DIR = "./working"
    $behaviorProps = @{}
    $behaviorProps["bytes"] = @($source)
    
    $extraInfo = ""
    $routineArg = $source
    $routineReturn = ""
    $routineCode = Microsoft.PowerShell.Management\Get-Content -Raw $CODE_DIR/harness/find_in_bytes_iocs.ps1
    Microsoft.PowerShell.Utility\Invoke-Expression $routineCode
    if ($routineReturn) {
        $extraInfo = $routineReturn
    }

    RecordAction $([Action]::new(@("memory_manipulation"), "[System.Runtime.InteropServices.Marshal]::Copy", $behaviorProps, $PSBoundParameters, $MyInvocation.Line, $extraInfo))
}