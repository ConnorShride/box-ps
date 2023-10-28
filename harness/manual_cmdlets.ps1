# replicate the mkdir that's on windows. On linux, it's an alias for /bin/mkdir
# on windows, it's an alias for New-Item
function mkdir {

    param(
        [Parameter(ValueFromPipeline=$true)][PSCredential] $Credential,
        [Parameter(ValueFromPipeline=$true,Position=0)][String[]] $Path,
        [Alias("wi")][Switch] $WhatIf,
        [Alias("cf")][Switch] $Confirm,
        [Switch] $Force
    )

    $scrapeIOCsCode = Microsoft.PowerShell.Management\Get-Content -Raw $CODE_DIR/harness/find_in_mem_iocs.ps1
    Microsoft.PowerShell.Utility\Invoke-Expression $scrapeIOCsCode

    $behaviors = @("file_system")
    $subBehaviors = @("new_directory")

    $behaviorProps = @{
        "paths" = @($Path)
    }

    RecordAction $([Action]::new($behaviors, $subBehaviors, "Microsoft.PowerShell.Core\mkdir", $behaviorProps, $MyInvocation, ""))
}

function curl {

    param(
        [Parameter(
             Mandatory=$True,
             ValueFromRemainingArguments=$true,
             Position = 1
         )][string[]]
        $listArgs
    )

    # Strip out flags from parameters. Also see if we have the
    # -usebasicparsing option.
    $useBasic = $false
    $realArgs = @()
    foreach ($arg in $listArgs) {
        if (-not ($arg -like "-*")) {
            $realArgs += $arg
        }
        if ($arg -like "-useb*") {
            $useBasic = $true
        }
    }

    # Pull out URL and maybe output file. This assumes arguments go in
    # a certain order.
    $o = $false
    $url = ""
    if ($realArgs.length -ge 2) {
        $o = $realArgs[-1]
        $url = $realArgs[-2]
    }
    elseif ($realArgs.length -eq 1) {
        $url = $realArgs[-1]
    }

    # A malware campaign has a mistake in their obfuscation and spaces
    # can wind up in the URL argument. Try to fix this.
    $realUrl = $url
    if ($url.Contains(" ")) {
        ForEach ($piece in $url.Split(" ")) {
            if ($piece.Contains(".") -and $piece.Contains("/")) {
                $realUrl = $piece
            }
        }
    }
    $url = $realUrl

    # Fix the URL if -usebasicparsing option given.
    if ($useBasic -and (-not ($url -like "http*"))) {
        $url = ("http://" + $url)
    }

    $behaviors = @("network")
    $subBehaviors = @()
    $behaviorProps = @{
	"uri" = $url
    }

    if ($o) {
	$behaviors += @("file_system")
	$subBehaviors += @("file_write")
	$behaviorProps["paths"] = @($o)
    }

    RecordAction $([Action]::new($behaviors, $subBehaviors, "curl.exe", $behaviorProps, $MyInvocation, ""))
    return "Write-Host ""fake curl results"""
}

function mshta ($url) {

    $behaviors = @("network")
    $subBehaviors = @()
    $behaviorProps = @{
	"uri" = $url
    }

    RecordAction $([Action]::new($behaviors, $subBehaviors, "mshta.exe", $behaviorProps, $MyInvocation, ""))
}

function Invoke-Expression {
    param(
	[Parameter(ValueFromPipeline=$true,Position=0,Mandatory=$true)]
	[string] $Command
    )

    Begin {}
    Process {

        $isInteger = $false

        # don't do anything for commands that are just integers (using IEX to init a byte array)
        try {
            $test = [int]$Command
            $isInteger = $true
        }
        # assume we've got a live one
        catch {

	    # record the action
            $behaviors = @("script_exec")
            $subBehaviors = @()
	    $behaviorProps = @{
		"script" = $Command
	    }

            RecordAction $([Action]::new($behaviors, $subBehaviors, "Microsoft.PowerShell.Utility\Invoke-Expression", $behaviorProps, $MyInvocation, ""))

            $scrapeIOCsCode = Microsoft.PowerShell.Management\Get-Content -Raw $CODE_DIR/harness/find_in_mem_iocs.ps1
            Microsoft.PowerShell.Utility\Invoke-Expression $scrapeIOCsCode

            $gotEnclosingScope = $true
            try{
                $parentVars = Microsoft.PowerShell.Utility\Get-Variable -Scope 1
            }
            catch
            {
                # No enclosing scope.
                $parentVars = @()
                $gotEnclosingScope = $false
            }
            $localVars = Microsoft.PowerShell.Utility\Get-Variable -Scope 0
            $localVars = $localVars | Microsoft.PowerShell.Core\ForEach-Object { $_.Name }

            # import all the variables from the parent scope so the invoke expression has them to work with
            foreach ($parentVar in $parentVars) {
                if (!($localVars.Contains($parentVar.Name))) {
                    Microsoft.PowerShell.Utility\Set-Variable -Name $parentVar.Name -Value $parentVar.Value
                }
            }

            $modifiedCommand = PreProcessScript $Command "<PID>"

            # actually run it, assign the result for situations like...
            # ex. $foo = Invoke-Expression "New-Object System.Net.WebClient"
            try {
                $invokeRes = Microsoft.PowerShell.Utility\Invoke-Expression $modifiedCommand
            }
            catch { }

            # invoked command may have initialized more variables that are to be used later, that are now
            # defined in this local scope
            $localVars = Microsoft.PowerShell.Utility\Get-Variable -Scope 0
            $parentVars = $parentVars | Microsoft.PowerShell.Core\ForEach-Object { $_.Name }

            # yes... foreach is indeed a variable
            $thisDeclaredVars = @("Command", "behaviorProps", "parentVars", "localVars", "parentVar",
                                  "invokeRes", "localVar", "varName", "foreach", "PSCmdlet")

            # pick out the variables the Invoke-Expression defined,
            # export them to the parent scope (if we have one).
            if ($parentVars -eq $null) {
                $parentVars = @()
            }
            if ($gotEnclosingScope) {
                foreach ($localVar in $localVars) {
                    $varName = $localVar.Name
                    if (!($parentVars.Contains($varName)) -and !($thisDeclaredVars.Contains($varName))) {
                        Microsoft.PowerShell.Utility\Set-Variable -Name $varName -Value $localVar.Value -Scope 1
                    }
                }
            }

            $invokeRes
        }

        if ($isInteger) {
            Microsoft.PowerShell.Utility\Invoke-Expression $Command
        }
    }
    End {}
}

function Start-Job {

    [cmdletbinding(DefaultParameterSetName="ComputerName")]
    param(
	[Parameter(ParameterSetName="FilePathComputerName")]
	[Parameter(ParameterSetName="ComputerName")]
	[Parameter(ParameterSetName="LiteralFilePathComputerName")]
	[Alias("Args")]
	[Object[]] $ArgumentList,
	[Parameter(ParameterSetName="LiteralFilePathComputerName")]
	[Parameter(ParameterSetName="ComputerName")]
	[Parameter(ParameterSetName="FilePathComputerName")]
	[AuthenticationMechanism] $Authentication,
	[Parameter(ParameterSetName="ComputerName")]
	[Parameter(ParameterSetName="FilePathComputerName")]
	[Parameter(ParameterSetName="LiteralFilePathComputerName")]
	[pscredential] $Credential,
	[Parameter(ParameterSetName="DefinitionName",Mandatory=$true)]
	[string] $DefinitionName,
	[Parameter(ParameterSetName="DefinitionName")]
	[string] $DefinitionPath,
	[Parameter(ParameterSetName="FilePathComputerName",Mandatory=$true)]
	[string] $FilePath,
	[Parameter(ParameterSetName="ComputerName")]
	[Parameter(ParameterSetName="LiteralFilePathComputerName")]
	[Parameter(ParameterSetName="FilePathComputerName")]
	[scriptblock] $InitializationScript,
	[Parameter(ParameterSetName="LiteralFilePathComputerName")]
	[Parameter(ParameterSetName="ComputerName")]
	[Parameter(ParameterSetName="FilePathComputerName")]
	[Parameter(ValueFromPipeline=$true)]
	[psobject] $InputObject,
	[Parameter(ParameterSetName="LiteralFilePathComputerName",Mandatory=$true)]
	[Alias("PSPath, LP")]
	[string] $LiteralPath,
	[Parameter(ParameterSetName="ComputerName")]
	[Parameter(ParameterSetName="FilePathComputerName")]
	[Parameter(ParameterSetName="LiteralFilePathComputerName")]
	[Parameter(ValueFromPipeline=$true)]
	[string] $Name,
	[Parameter(ParameterSetName="FilePathComputerName")]
	[Parameter(ParameterSetName="ComputerName")]
	[Parameter(ParameterSetName="LiteralFilePathComputerName")]
	[version] $PSVersion,
	[Parameter(ParameterSetName="FilePathComputerName")]
	[Parameter(ParameterSetName="ComputerName")]
	[Parameter(ParameterSetName="LiteralFilePathComputerName")]
	[switch] $RunAs32,
	[Parameter(ParameterSetName="ComputerName",Mandatory=$true)]
	[Parameter(Position=0)]
	[Alias("Command")]
	[scriptblock] $ScriptBlock,
	[Parameter(ParameterSetName="DefinitionName")]
	[string] $Type,
	[string] $WorkingDirectory
    )

    $scrapeIOCsCode = Microsoft.PowerShell.Management\Get-Content -Raw $CODE_DIR/harness/find_in_mem_iocs.ps1
    Microsoft.PowerShell.Utility\Invoke-Expression $scrapeIOCsCode

    # the script that is executed by the job here is the scriptblock which is an unnamed function,
    # so we need to give it a name and feed in the arguments properly to sandbox

    $script = ""
    $behaviors = @("script_exec")
    $subBehaviors = @("start_process")
    $behaviorProps = @{}

    # read in the script from the file to sandbox
    # just try to on the off chance they put it in the current dir so this will actually work (no windows paths)
    if ($FilePath) {
        $script = Microsoft.PowerShell.Management\Get-Content -Raw $FilePath
        $behaviorProps["script"] = $script
    }
    # script executed in the job is given with a scriptblock, implement as a function
    else {

	# pass down an argument list variable if present with a
	if ($ArgumentList) {
	    $script += "`$arglist = @`'`r`n$ArgumentList`r`n'@`r`n"
	}

	$script += "function boxpsjob {`r`n"

	# if the scriptblock starts with a parameter block, Start-Job seems to treat this like
	# a function, taking in an argument list through it, so write one with it
	$match = [Regex]::Match($ScriptBlock, "^\s*(param\(.*\)).*")
	if ($match.Success) {

	    # grab the parameter block definition
	    $paramBlockCapture = $match.Groups[1].Captures[0]
	    $paramBlock = $paramBlockCapture.Value

	    # grab the rest of the script block minus the parameter block
	    $functionBlock = $ScriptBlock.ToString().Substring($paramBlockCapture.Index + $paramBlock.Length)

	    # build the body of the function
	    $script += "`t$paramBlock`r`n"
	    $script += "`t$functionBlock`r`n"
	}
	# the scriptblock is not defining a parameter block, so if it's taking in an argument list,
	# it's going to be input with the $args automatic variable
	else {
	    $script += "`t$ScriptBlock`r`n"
	}

	$script += "}`r`n"

	# add the call to the function
	$script += "boxpsjob"

	if ($ArgumentList) {
	    $script += " `$arglist"
        }

        $behaviorProps["script"] = $ScriptBlock.StartPosition.Content
    }

    RecordAction $([Action]::new($behaviors, $subBehaviors, "Microsoft.PowerShell.Core\Start-Job", $behaviorProps, $MyInvocation, ""))

    if ($script) {
	[boxpsstatics]::SandboxScript($script)
    }
}

function New-Object {
    param(
	[Parameter(ParameterSetName="Net",Position=1)]
	[Alias("Args")]
	[Object[]] $ArgumentList,
	[IDictionary] $Property,
	[Parameter(ParameterSetName="Com")]
	[switch] $Strict,
	[Parameter(ParameterSetName="Net",Position=0,Mandatory=$true)]
	[string] $TypeName,
	[string] $COMObject
    )

    $scrapeIOCsCode = Microsoft.PowerShell.Management\Get-Content -Raw $CODE_DIR/harness/find_in_mem_iocs.ps1
    Microsoft.PowerShell.Utility\Invoke-Expression $scrapeIOCsCode

    $behaviors = @("new_object")
    $subBehaviors = @()

    if ($PSBoundParameters.ContainsKey("TypeName")) {
	$TypeName = $PSBoundParameters["TypeName"].ToLower()
	$PSBoundParameters["TypeName"] = $PSBoundParameters["TypeName"].ToLower()
    }

    if ($PSBoundParameters.ContainsKey("COMObject")) {
	$COMObject = $PSBoundParameters["COMObject"].ToLower()
	$PSBoundParameters["COMObject"] = $PSBoundParameters["COMObject"].ToLower()
    }

    $behaviorProps = @{}

    if ($PSBoundParameters.ContainsKey("COMObject")) {
	$behaviorProps["object"] = $COMObject
    }

    elseif ($PSBoundParameters.ContainsKey("TypeName")) {
	$behaviorProps["object"] = $TypeName
    }

    # too noisy and not valuable except for debugging
    #RecordAction $([Action]::new($behaviors, $subBehaviors, "Microsoft.PowerShell.Utility\New-Object", $behaviorProps, $MyInvocation, ""))

    if ($(GetOverridedClasses).Contains($behaviorProps["object"].ToLower() -replace "^system.")) {
	return RedirectObjectCreation $TypeName $ArgumentList
    }

    return Microsoft.PowerShell.Utility\New-Object @PSBoundParameters
}

function powershell.exe {

    param(
	[Parameter(Position=0, ValueFromRemainingArguments=$true)]
	$Command,
        [string] $EncodedCommand,
	[string] $File,
	[string] $WindowStyle,
        [string] $ExecutionPolicy,
        [switch] $NoLogo,
        [switch] $NoProfile,
        [switch] $NonInteractive
    )

    $scrapeIOCsCode = Microsoft.PowerShell.Management\Get-Content -Raw $CODE_DIR/harness/find_in_mem_iocs.ps1
    Microsoft.PowerShell.Utility\Invoke-Expression $scrapeIOCsCode

    $behaviors = @("script_exec")
    $subBehaviors = @("start_process")
    $behaviorProps = @{}

    if ($PSBoundParameters.ContainsKey("Command")) {

	# command was given arg list style like "powershell Write-Host foo". join the list into a single string
	if ($Command.Count -gt 1) {
            Write-Host "PS: 1"
	    foreach ($token in $Command) {
		$behaviorProps["script"] += $token + " "
	    }
	}
	else {
            if ($Command -is [array]) {
	        $behaviorProps["script"] = $Command[0].ToString()
            }
            else {
                $behaviorProps["script"] = $Command.ToString()
            }
	}
    }
    # command is given as a b64 encoded string, decode it
    if ($PSBoundParameters.ContainsKey("EncodedCommand")) {
        $decodedScript = [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String($EncodedCommand))
        $behaviorProps["script"] = $decodedScript
    }
    # read the script from a file
    # TODO test this with a windows style path (should work I think)
    elseif ($PSBoundParameters.ContainsKey("File")) {

	$behaviors += @("file_system")
	$subBehaviors += @("file_read")

	$behaviorProps["paths"] = @($File)
        $behaviorProps["script"] = $(Microsoft.PowerShell.Management\Get-Content -Raw $File | Out-String)
    }

    RecordAction $([Action]::new($behaviors, $subBehaviors, "powershell.exe", $behaviorProps, $MyInvocation, ""))

    [BoxPSStatics]::SandboxScript($behaviorProps["script"])
}

function Add-Type {
    [cmdletbinding(DefaultParameterSetName="FromSource")]
    param(
	<#
Don't support importing from a path
	[Parameter(ParameterSetName="FromAssemblyName",Mandatory=$true)]
	[Alias("AN")]
	[string[]] $AssemblyName,
	#>
	[Parameter(ParameterSetName="FromPath")]
	[Parameter(ParameterSetName="FromMember")]
	[Parameter(ParameterSetName="FromSource")]
	[Parameter(ParameterSetName="FromLiteralPath")]
	[string[]] $CompilerOptions,
	[Parameter(ParameterSetName="FromPath")]
	[Parameter(ParameterSetName="FromMember")]
	[Parameter(ParameterSetName="FromSource")]
	[Parameter(ParameterSetName="FromLiteralPath")]
	[switch] $IgnoreWarnings,
	[Parameter(ParameterSetName="FromSource")]
	[Parameter(ParameterSetName="FromMember")]
	[Language] $Language,
	[Parameter(ParameterSetName="FromLiteralPath",Mandatory=$true)]
	[Alias("PSPath, LP")]
	[string[]] $LiteralPath,
	[Parameter(ParameterSetName="FromMember",Mandatory=$true)]
	[Parameter(Position=1)]
	[string[]] $MemberDefinition,
	[Parameter(ParameterSetName="FromMember",Mandatory=$true)]
	[Parameter(Position=0)]
	[string] $Name,
	[Parameter(ParameterSetName="FromMember")]
	[Alias("NS")]
	[string] $Namespace,
	[Parameter(ParameterSetName="FromPath")]
	[Parameter(ParameterSetName="FromMember")]
	[Parameter(ParameterSetName="FromSource")]
	[Parameter(ParameterSetName="FromLiteralPath")]
	[Alias("OA")]
	[string] $OutputAssembly,
	[Parameter(ParameterSetName="FromPath")]
	[Parameter(ParameterSetName="FromMember")]
	[Parameter(ParameterSetName="FromSource")]
	[Parameter(ParameterSetName="FromLiteralPath")]
	[Alias("OT")]
	[OutputAssemblyType] $OutputType,
	[switch] $PassThru,
	<#
	Don't support importing from a path
[Parameter(ParameterSetName="FromPath",Mandatory=$true)]
[Parameter(Position=0)]
[string[]] $Path,
#>
	[Parameter(ParameterSetName="FromPath")]
	[Parameter(ParameterSetName="FromMember")]
	[Parameter(ParameterSetName="FromSource")]
	[Parameter(ParameterSetName="FromLiteralPath")]
	[Alias("RA")]
	[string[]] $ReferencedAssemblies,
	[Parameter(ParameterSetName="FromSource",Mandatory=$true)]
	[Parameter(Position=0)]
	[string] $TypeDefinition,
	[Parameter(ParameterSetName="FromMember")]
	[Alias("Using")]
	[string[]] $UsingNamespace
    )

    $scrapeIOCsCode = Microsoft.PowerShell.Management\Get-Content -Raw $CODE_DIR/harness/find_in_mem_iocs.ps1
    Microsoft.PowerShell.Utility\Invoke-Expression $scrapeIOCsCode

    $behaviorProps = @{}
    if ($PSBoundParameters.ContainsKey("TypeDefinition")) {
	$behaviorProps["code"] = [string]$TypeDefinition
    }
    elseif ($PSBoundParameters.ContainsKey("MemberDefinition")) {
	$behaviorProps["code"] = [string]$MemberDefinition
    }

    $behaviors = @("code_import")
    $subBehaviors = @("import_dotnet_code")
    $extraInfo = ""

    $separator = ("*" * 100 + "`r`n")
    $layerOut = $separator + $behaviorProps["code"] + "`r`n" + $separator
    $layerOut | Microsoft.PowerShell.Utility\Out-File -Append -Path $WORK_DIR/layers.ps1

    RecordAction $([Action]::new($behaviors, $subBehaviors, "Microsoft.PowerShell.Utility\Add-Type", $behaviorProps, $MyInvocation, $extraInfo))
    return Microsoft.PowerShell.Utility\Add-Type @PSBoundParameters
}

# not for sandboxing. I need this to compensate for a bug in this function which
# does not convert ProcessStartInfo objects to Json without erroring out.
# ...pls fix... (https://github.com/PowerShell/PowerShell/issues/11915)
function ConvertTo-Json {
    param(
	[switch] $AsArray,
	[switch] $Compress,
	[int] $Depth,
	[switch] $EnumsAsStrings,
	[StringEscapeHandling] $EscapeHandling,
	[Parameter(ValueFromPipeline=$true,Position=0)]
	[Object] $InputObject
    )

    if ($InputObject.GetType() -eq [Action] -and $InputObject.Parameters["startInfo"]) {

        $startInfo = $InputObject.Parameters["startInfo"]

        $objectDict = @{
            "Arguments" = $startInfo.Arguments;
            "CreateNoWindow" = $startInfo.CreateNoWindow;
            "Domain" = $startInfo.Domain;
            #"Environment" = $startInfo.Environment; #OFFENDER
            # below is offender but somehow works after we do this
            # also get rid of it because the output sucks
            # "EnvironmentVariables" = $startInfo.EnvironmentVariables;
            "ErrorDialog" = $startInfo.ErrorDialog;
            "ErrorDialogParentHandle" = $startInfo.ErrorDialogParentHandle;
            "FileName" = $startInfo.FileName;
            "LoadUserProfile" = $startInfo.LoadUserProfile;
            "Password" = $startInfo.Password;
            "PasswordInClearText" = $startInfo.PasswordInClearText;
            "RedirectStandardError" = $startInfo.RedirectStandardError;
            "RedirectStandardInput" = $startInfo.RedirectStandardInput;
            "RedirectStandardOutput" = $startInfo.RedirectStandardOutput;
            "StandardErrorEncoding" = $startInfo.StandardErrorEncoding;
            "StandardOutputEncoding" = $startInfo.StandardOutputEncoding;
            "UserName" = $startInfo.UserName;
            "UseShellExecute" = $startInfo.UseShellExecute;
            "Verb" = $startInfo.Verb;
            "Verbs" = $startInfo.Verbs;
            "WindowStyle" = $startInfo.WindowStyle;
            "WorkingDirectory" = $startInfo.WorkingDirectory;
        }

        $object = Microsoft.PowerShell.Utility\New-Object psObject -Property $objectDict
        $InputObject.Parameters["startInfo"] = $object

        return $InputObject | Microsoft.PowerShell.Utility\ConvertTo-Json
    }

    return Microsoft.PowerShell.Utility\ConvertTo-Json @PSBoundParameters
}

function New-ScheduledTaskAction {

    [cmdletbinding(DefaultParameterSetName="FromSource")]
    param(
        $Execute,
        $Argument,
        $WorkingDirectory,
        $CimSession,
        $ThrottleLimit,
        $AsJob
    )

    $scrapeIOCsCode = Microsoft.PowerShell.Management\Get-Content -Raw $CODE_DIR/harness/find_in_mem_iocs.ps1
    Microsoft.PowerShell.Utility\Invoke-Expression $scrapeIOCsCode

    $behaviors = @("task")
    $subBehaviors = @("new_task")

    $behaviorProps = @{
        "execute" = $Execute;
        "argument" = $Argument;
        "working_directory" = $WorkingDirectory
    }

    RecordAction $([Action]::new($behaviors, $subBehaviors, "New-ScheduledTaskAction", $behaviorProps, $MyInvocation, ""))
}

function New-ScheduledTaskPrincipal {

    [cmdletbinding(DefaultParameterSetName="FromSource")]
    param(
        $RunLevel,
        $ProcessTokenSidType,
        $RequiredPrivilege,
        $UserId,
        $LogonType,
        $CimSession,
        $ThrottleLimit,
        $AsJob
    )

    $scrapeIOCsCode = Microsoft.PowerShell.Management\Get-Content -Raw $CODE_DIR/harness/find_in_mem_iocs.ps1
    Microsoft.PowerShell.Utility\Invoke-Expression $scrapeIOCsCode

    $behaviors = @("task")
    $subBehaviors = @("new_task")

    $behaviorProps = @{
        "run_level" = $RunLevel;
        "user_id" = $UserId;
        "logon_type" = $LogonType
    }

    RecordAction $([Action]::new($behaviors, $subBehaviors, "New-ScheduledTaskPrincipal", $behaviorProps, $MyInvocation, ""))
}

function New-ScheduledTaskTrigger {

    [cmdletbinding(DefaultParameterSetName="FromSource")]
    param(
        [switch] $AsJob,
        $At,
        [switch] $AtLogOn,
        [switch] $AtStartup,
        $CimSession,
        [switch] $Daily,
        $DaysInterval,
        $DaysOfWeek,
        [switch] $Once,
        $RandomDelay,
        $RepetitionDuration,
        $RepetitionInterval,
        $ThrottleLimit,
        $User,
        [switch] $Weekly,
        $WeeksInterval
    )

    $scrapeIOCsCode = Microsoft.PowerShell.Management\Get-Content -Raw $CODE_DIR/harness/find_in_mem_iocs.ps1
    Microsoft.PowerShell.Utility\Invoke-Expression $scrapeIOCsCode

    # Convert flags to bools for tracking results.
    $Trigger = "??"
    if ($AtLogon) { $Trigger = "At Logon" }
    if ($AtStartup) { $Trigger = "At Startup" }
    if ($Daily) { $Trigger = "Daily" }
    if ($Once ) { $Trigger = "Once" }
    if ($Weekly) { $Trigger = "Weekly" }

    $behaviors = @("task")
    $subBehaviors = @("new_task")

    $behaviorProps = @{
        "random_delay" = $RandomDelay;
        "at" = $At;
        "trigger" = $Trigger;
        "days_interval" = $DaysInterval;
        "days_of_week" = $DaysOfWeek;
        "user" = $User;
    }

    RecordAction $([Action]::new($behaviors, $subBehaviors, "New-ScheduledTaskTrigger", $behaviorProps, $MyInvocation, ""))
}

# Placeholder. Fill in as needed.
function New-ScheduledTaskSettingsSet {}
# Placeholder. Fill in as needed.
function Register-ScheduledTask {}

# Don't want to actually run wget ever.
function wget ($url) {

    $behaviors = @("network")
    $subBehaviors = @()
    $behaviorProps = @{
	"uri" = $url
    }
    RecordAction $([Action]::new($behaviors, $subBehaviors, "wget", $behaviorProps, $MyInvocation, ""))
    return "";
}

function Invoke-RestMethod {

    param(
        [Parameter(
             Mandatory=$True,
             ValueFromRemainingArguments=$true,
             Position = 1
         )][string[]]
        $listArgs
    )

    # Pull out the URL. We're ignoring all other arguments for now.
    $url = ""
    $pos = 0
    $maybe = ""
    foreach ($arg in $listArgs) {
        $maybe = $arg
        $pos += 1
        if (($arg -like "-uri*") -and ($pos -lt $listArgs.length)) {
            $url = $listArgs[$pos]
            break
        }
    }

    # If we have just a single argument, assume it is a URL.
    if (($pos -eq 1) -and ($url -eq "")) {
        $url = $maybe
    }

    # Looks like you can leave the http: off. Fix that.
    if (-not ($url -like "http*")) {
        $url = ("http://" + $url)
    }

    $behaviors = @("network")
    $subBehaviors = @()
    $behaviorProps = @{
	"uri" = $url
    }

    RecordAction $([Action]::new($behaviors, $subBehaviors, "Invoke-RestMethod", $behaviorProps, $MyInvocation, ""))
    return "1.2.3.4"
}

function GetAsyncKeyState {

    param(
        [Parameter(
             Mandatory=$True,
             ValueFromRemainingArguments=$true,
             Position = 1
         )][string[]]
        $listArgs
    )

    $behaviors = @("keyboard")
    $subBehaviors = @()
    $behaviorProps = @{}

    RecordAction $([Action]::new($behaviors, $subBehaviors, "GetAsyncKeyState", $behaviorProps, $MyInvocation, ""))
    return 123
}

function Get-Item {

    param(
        [string] $Path,
        [Parameter(
             ValueFromRemainingArguments=$true,
             Position = 1
         )][string[]]
        $listArgs
    )

    # Got the path to the file being read? This is an IOC.
    if ($PSBoundParameters.ContainsKey("Path")) {

        # Save the path being read as an IOC.
	$behaviors = @("file_system")
	$subBehaviors = @("file_read")
        $behaviorProps = @{}
	$behaviorProps["paths"] = @($PSBoundParameters["Path"])

        RecordAction $([Action]::new($behaviors, $subBehaviors, "Microsoft.PowerShell.Core\Get-Item", $behaviorProps, $MyInvocation, ""))
    }

    # Return a large string for the fake file contents.
    return "fake" * 1000
}

# Hide the real hostname.
function hostname {

    param(
        [Parameter(
             ValueFromRemainingArguments=$true,
             Position = 1
         )][string[]]
        $listArgs
    )

    return "hammertime";
}

function Start-BitsTransfer {

    param(
        [Parameter(
             Mandatory=$True,
             ValueFromRemainingArguments=$true,
             Position = 1
         )][string[]]
        $listArgs
    )

    # Pull out the URL and where to write the downloaded file.
    $url = ""
    $dest = $null
    $pos = 0
    foreach ($arg in $listArgs) {
        $pos += 1
        if (($arg -like "-so*") -and ($pos -lt $listArgs.length)) {
            $url = $listArgs[$pos]
        }
        if (($arg -like "-de*") -and ($pos -lt $listArgs.length)) {
            $dest = $listArgs[$pos]
        }
    }

    $behaviors = @("network")
    $subBehaviors = @()
    $behaviorProps = @{
	"uri" = $url
    }
    if ($dest -ne $null) {
	$behaviorProps["dst"] = $dest
    }

    RecordAction $([Action]::new($behaviors, $subBehaviors, "Start-BitsTransfer", $behaviorProps, $MyInvocation, ""))
}

function fakecmdexe {

    param(
        [Parameter(
             Mandatory=$True,
             ValueFromRemainingArguments=$true,
             Position = 1
         )][string[]]
        $listArgs
    )

    # record the full cmd.exe command.
    $behaviors = @("script_exec")
    $subBehaviors = @()
    $behaviorProps = @{
	"args" = "" + $listArgs
    }

    RecordAction $([Action]::new($behaviors, $subBehaviors, "cmd.exe", $behaviorProps, $MyInvocation, ""))
}

function fakemv {

    param(
        [Parameter(
             Mandatory=$True,
             ValueFromRemainingArguments=$true,
             Position = 1
         )][string[]]
        $listArgs
    )

    # record the full mv command.
    $behaviors = @("file_system")
    $subBehaviors = @()
    $behaviorProps = @{
	"paths" = "" + $listArgs
    }

    RecordAction $([Action]::new($behaviors, $subBehaviors, "mv", $behaviorProps, $MyInvocation, ""))
}
