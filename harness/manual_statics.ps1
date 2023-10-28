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

# returns a path to a new harnessed_script_X.ps1 file that hasn't been taken
static [string] GetHarnessFile([string] $directory) {

    $found = $false
    $count = 0
    while (!$found) {
        if (Microsoft.PowerShell.Management\Test-Path ($directory + "/harnessed_script_" + [string]$count + ".ps1")) {
            $count++
        }
        else {
            $found = $true
        }
    }
    return ($directory + "/harnessed_script_" + [string]$count + ".ps1")
}

# run another box-ps subprocess to sandbox a script
static [void] SandboxScript([string] $script) {

    $CODE_DIR = "<CODE_DIR>"
    $WORK_DIR = "./working_<PID>"

    # get off my back I'm not proud of what's happening here.
    $harness = (BuildHarness).Replace("<CODE_" + "DIR>", $CODE_DIR).Replace("<PI" + "D>", "<PID>")
    $harnessedScriptPath = [BoxPSStatics]::GetHarnessFile($WORK_DIR)
    $harnessedScript = $harness + "`r`n`r`n" + (PreProcessScript $script "<PID>")
    $harnessedScript | Out-File -FilePath $harnessedScriptPath
    pwsh -noni $harnessedScriptPath 2>> $WORK_DIR/stderr.txt 1>> $WORK_DIR/stdout.txt
}

static [ScriptBlock] ScriptBlockCreate([string] $script) {

    $behaviors = @("code_create")
    $subBehaviors = @("init_code_block")

    $behaviorProps = @{"code" = $script}
    RecordAction $([Action]::new($behaviors, $subBehaviors, "[ScriptBlock]::Create", $behaviorProps, $PSBoundParameters, $MyInvocation.Line, ""))

    return [scriptblock]::Create((PreProcessScript $script "<PID>"))
}

static [System.Diagnostics.Process] SystemDiagnosticsProcessStart([System.Diagnostics.ProcessStartInfo] $startInfo) {

    $subBehaviors = @("start_process")
    $behaviorProps = @{}

    # if powershell, treat this now as a script_exec rather than file_exec and sandbox the script
    if ($startInfo.FileName.ToLower().Contains("powershell") -and $startInfo.Arguments) {

        $behaviors += @("script_exec")
        $script = [BoxPSStatics]::GetScriptFromArguments($startInfo.Arguments)

        # record the action
        $behaviorProps["script"] = $script
        RecordAction $([Action]::new($behaviors, $subBehaviors, "[System.Diagnostics.Process]::Start", $behaviorProps, $PSBoundParameters, $MyInvocation.Line, ""))

        # sandbox the script
        [BoxPSStatics]::SandboxScript($script)
    }
    else {

        $behaviors += @("file_exec")
        $behaviorProps["files"] = @($startInfo.FileName)
        RecordAction $([Action]::new($behaviors, $subBehaviors, "[System.Diagnostics.Process]::Start", $behaviorProps, $PSBoundParameters, $MyInvocation.Line, ""))
    }

    return $null
}

static [System.Diagnostics.Process] SystemDiagnosticsProcessStart([string] $fileName, [string] $arguments) {

    $subBehaviors = @("start_process")
    $behaviorProps = @{}

    # if powershell, treat this now as a script_exec rather than file_exec and sandbox the script
    if ($fileName.ToLower().Contains("powershell") -and $arguments) {

        $behaviors = @("script_exec")
        $script = [BoxPSStatics]::GetScriptFromArguments($arguments)

        # record the action
        $behaviorProps["script"] = $script
        RecordAction $([Action]::new($behaviors, $subBehaviors, "[System.Diagnostics.Process]::Start", $behaviorProps, $PSBoundParameters, $MyInvocation.Line, ""))

        # sandbox the script
        [BoxPSStatics]::SandboxScript($script)
    }
    else {

        $behaviors = @("file_exec")
        $behaviorProps["files"] = @($fileName)
        RecordAction $([Action]::new($behaviors, $subBehaviors, "[System.Diagnostics.Process]::Start", $behaviorProps, $PSBoundParameters, $MyInvocation.Line, ""))
    }

    return $null
}

static [System.Diagnostics.Process] SystemDiagnosticsProcessStart([string] $fileName, [string] $arguments, [string] $userName, [securestring] $password, [string] $domain) {

    $subBehaviors = @("start_process")
    $behaviorProps = @{}

    # if powershell, treat this now as a script_exec rather than file_exec and sandbox the script
    if ($fileName.ToLower().Contains("powershell") -and $arguments) {

        $behaviors = @("script_exec")
        $script = [BoxPSStatics]::GetScriptFromArguments($arguments)

        # record the action
        $behaviorProps["script"] = $script
        RecordAction $([Action]::new($behaviors, $subBehaviors, "[System.Diagnostics.Process]::Start", $behaviorProps, $PSBoundParameters, $MyInvocation.Line, ""))

        # sandbox the script
        [BoxPSStatics]::SandboxScript($script)
    }
    else {
        $behaviors = @("file_exec")
        $behaviorProps["files"] = @($fileName)
        RecordAction $([Action]::new($behaviors, $subBehaviors, "[System.Diagnostics.Process]::Start", $behaviorProps, $PSBoundParameters, $MyInvocation.Line, ""))
    }

    return $null
}

static [void] SystemRuntimeInteropServicesMarshalCopy([byte[]] $source, [object] $destination, [object] $startIndex, [object] $length) {

    $CODE_DIR = "<CODE_DIR>"
    $WORK_DIR = "./working_<PID>"
    $behaviorProps = @{}
    $behaviorProps["bytes"] = [Int32[]]$source

    $extraInfo = ""
    $routineArg = $source
    $routineReturn = ""
    $routineCode = Microsoft.PowerShell.Management\Get-Content -Raw $CODE_DIR/harness/find_in_bytes_iocs.ps1
    Microsoft.PowerShell.Utility\Invoke-Expression $routineCode
    if ($routineReturn) {
        $extraInfo = $routineReturn
    }

    $behaviors = @("memory")
    $subBehaviors = @("write_to_memory")

    RecordAction $([Action]::new($behaviors, $subBehaviors, "[System.Runtime.InteropServices.Marshal]::Copy", $behaviorProps, $PSBoundParameters, $MyInvocation.Line, $extraInfo))
}

static [void] SystemRuntimeInteropServicesMarshalCopy([long[]] $source, [object] $destination, [object] $startIndex, [object] $length) {

    $CODE_DIR = "<CODE_DIR>"
    $WORK_DIR = "./working_<PID>"
    $behaviorProps = @{}
    $behaviorProps["bytes"] = [Int32[]]$source

    $extraInfo = ""
    $routineArg = $source
    $routineReturn = ""
    $routineCode = Microsoft.PowerShell.Management\Get-Content -Raw $CODE_DIR/harness/find_in_bytes_iocs.ps1
    Microsoft.PowerShell.Utility\Invoke-Expression $routineCode
    if ($routineReturn) {
        $extraInfo = $routineReturn
    }

    $behaviors = @("memory")
    $subBehaviors = @("write_to_memory")

    RecordAction $([Action]::new($behaviors, $subBehaviors, "[System.Runtime.InteropServices.Marshal]::Copy", $behaviorProps, $PSBoundParameters, $MyInvocation.Line, $extraInfo))
}

static [void] SystemRuntimeInteropServicesMarshalCopy([char[]] $source, [object] $destination, [object] $startIndex, [object] $length) {

    $CODE_DIR = "<CODE_DIR>"
    $WORK_DIR = "./working_<PID>"
    $behaviorProps = @{}
    $behaviorProps["bytes"] = [Int32[]]$source

    $extraInfo = ""
    $routineArg = $source
    $routineReturn = ""
    $routineCode = Microsoft.PowerShell.Management\Get-Content -Raw $CODE_DIR/harness/find_in_bytes_iocs.ps1
    Microsoft.PowerShell.Utility\Invoke-Expression $routineCode
    if ($routineReturn) {
        $extraInfo = $routineReturn
    }

    $behaviors = @("memory")
    $subBehaviors = @("write_to_memory")

    RecordAction $([Action]::new($behaviors, $subBehaviors, "[System.Runtime.InteropServices.Marshal]::Copy", $behaviorProps, $PSBoundParameters, $MyInvocation.Line, $extraInfo))
}

static [void] SystemRuntimeInteropServicesMarshalCopy([short[]] $source, [object] $destination, [object] $startIndex, [object] $length) {

    $CODE_DIR = "<CODE_DIR>"
    $WORK_DIR = "./working_<PID>"
    $behaviorProps = @{}
    $behaviorProps["bytes"] = [Int32[]]$source

    $extraInfo = ""
    $routineArg = $source
    $routineReturn = ""
    $routineCode = Microsoft.PowerShell.Management\Get-Content -Raw $CODE_DIR/harness/find_in_bytes_iocs.ps1
    Microsoft.PowerShell.Utility\Invoke-Expression $routineCode
    if ($routineReturn) {
        $extraInfo = $routineReturn
    }

    $behaviors = @("memory")
    $subBehaviors = @("write_to_memory")

    RecordAction $([Action]::new($behaviors, $subBehaviors, "[System.Runtime.InteropServices.Marshal]::Copy", $behaviorProps, $PSBoundParameters, $MyInvocation.Line, $extraInfo))
}

static [string] SystemRuntimeInteropServicesMarshalPtrToStringAuto([IntPtr] $ptr) {
    return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
}
