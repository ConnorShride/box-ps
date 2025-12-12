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

function fakecurl {

    # Strip out flags from parameters. Also see if we have the
    # -usebasicparsing option.
    $useBasic = $false
    $realArgs = @()
    foreach ($arg in $args) {
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
    return "Write-Host ""EXECUTED DOWNLOADED PAYLOAD"""
}

function mshta ($url) {

    $behaviors = @("network")
    $subBehaviors = @()
    $behaviorProps = @{
	"uri" = $url
    }

    RecordAction $([Action]::new($behaviors, $subBehaviors, "mshta", $behaviorProps, $MyInvocation, ""))
}

function Stub-Invoke($i) {

    # Stub out some static assembly method references.
    $iStr = "$i"
    if ($iStr -eq "static scriptblock Create(string script)") {
        class STUBBED {
            [scriptblock] Invoke($script) {
                $behaviors = @("code_create")
                $subBehaviors = @("init_code_block")
                
                $behaviorProps = @{"code" = $script}
                RecordAction $([Action]::new($behaviors, $subBehaviors, "[ScriptBlock]::Create", $behaviorProps, $PSBoundParameters, $MyInvocation.Line, ""))

                return [scriptblock]::Create((PreProcessScript $script "<PID>"))
            }
        }
        return ([STUBBED]::new())
    }
    
    return $i
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
                try {
                    if (!($localVars.Contains($parentVar.Name))) {
                        Microsoft.PowerShell.Utility\Set-Variable -Name $parentVar.Name -Value $parentVar.Value                        
                    }
                }
                catch {}
            }

            $modifiedCommand = PreProcessScript $Command "<PID>"

            # actually run it, assign the result for situations like...
            # ex. $foo = Invoke-Expression "New-Object System.Net.WebClient"
            try {
                $invokeRes = Microsoft.PowerShell.Utility\Invoke-Expression $modifiedCommand
            }
            catch {
                Write-Error "IEX Failed: $($_.Exception.Message)"
            }

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

            # We may want to stub out some results. Handle stubbing.
            $r = Stub-Invoke($invokeRes)

            $r
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

    # Linux PWSH does not have WindowsInstaller.Installer, so return a
    # stubbed object in that case.
    $className = ($behaviorProps["object"].ToLower() -replace "^system.")
    if ($className -eq "windowsinstaller.installer") {

        # Stubbed class.
        class INSTALLER {
            $UILevel
            INSTALLER() {
                $this.UILevel = 0
            }
            InstallProduct($url, $ignore) {
                $behaviors = @("network")
                $subBehaviors = @()
                $behaviorProps = @{
	            "uri" = $url
                }
                RecordAction $([Action]::new($behaviors, $subBehaviors, "WindowsInstaller.Installer.InstallProduct", $behaviorProps, $MyInvocation, ""))
            }
        }

        # Return stubbed installer object.
        return ([INSTALLER]::new())
    }
    
    if ($(GetOverridedClasses).Contains($className)) {
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
	    foreach ($token in $Command) {
		$behaviorProps["script"] += $token + " "
	    }
	}
	else {
            if ($Command -is [array]) {
	        $behaviorProps["script"] = $Command[0].ToString()
            }
            else {
                $behaviorProps["script"] = (("" + $Command).ToString())
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
	[Parameter(ParameterSetName="FromAssemblyName")]
	[Alias("AN")]
	[string[]] $AssemblyName,
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
    elseif ($PSBoundParameters.ContainsKey('AssemblyName')) {
        #$behaviorProps["code"] = "# Ignoring added assembly..."
        $behaviorProps["code"] = [string]$AssemblyName
    }
    
    $behaviors = @("code_import")
    $subBehaviors = @("import_dotnet_code")
    $extraInfo = ""

    # Not sure what new functionality the assembly will give, so just
    # record the Add-Type but don't add the assembly as a type.
    if (-not $PSBoundParameters.ContainsKey('AssemblyName')) {
        $separator = ("*" * 100 + "`r`n")
        $layerOut = $separator + $behaviorProps["code"] + "`r`n" + $separator
        $layerOut | Microsoft.PowerShell.Utility\Out-File -Append -Path $WORK_DIR/layers.ps1
    }

    RecordAction $([Action]::new($behaviors, $subBehaviors, "Microsoft.PowerShell.Utility\Add-Type", $behaviorProps, $MyInvocation, $extraInfo))

    # Not sure what new functionality the assembly will give, so just
    # record the Add-Type but don't add the assembly as a type.        
    if (-not $PSBoundParameters.ContainsKey('AssemblyName')) {
        return Microsoft.PowerShell.Utility\Add-Type @PSBoundParameters
    }
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
function wget {

    # Pull out the URL being hit from the arguments.
    $listArgs = $args
    $uriFlag = $false
    $url = ""
    $lastArg = ""
    foreach ($arg in $listArgs) {
        if ($arg -eq "-uri") {
            $uriFlag = $true
            continue
        }
        if ($uriFlag -or ($arg -like "http*")) {
            $url = $arg;
        }
        $uriFlag = $false
	$lastArg = $arg
    }

    # Looks like you can leave the https:// off the URL. Check for
    # that.
    if (($url -eq "") -and ($lastArg.Length -gt 5)) {
	$match = [Regex]::Match($lastArg[0], "[a-zA-Z0-9]")
	if ($match.Success) {
	    $url = ("https://" + $lastArg)
	}
    }
    
    $behaviors = @("network")
    $subBehaviors = @()
    $behaviorProps = @{
	"uri" = $url
    }    
    RecordAction $([Action]::new($behaviors, $subBehaviors, "wget", $behaviorProps, $MyInvocation, ""))
    return "";
}

function Invoke-RestMethod() {

    # Pull out the URL. We're ignoring all other arguments for now.
    $listArgs = $args
    $url = ""
    $pos = 0
    foreach ($arg in $listArgs) {
        if (($arg -like "-uri*") -and (($pos + 1) -lt $listArgs.length)) {
            $url = $listArgs[$pos + 1]
            break
        }
        if ($arg -like "http*") {
            $url = $arg
            break
        }
        $pos += 1
    }

    # If we don't have a URL, try the 1st arg as the URL.
    if (($pos -ge 1) -and ($url -eq "")) {
        $url = $listArgs[0]
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
    return "Write-Host ""EXECUTED DOWNLOADED PAYLOAD"""
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
	     ValueFromPipeline=$true,
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

    # Fake up exit code for cmd.exe calls to exit if needed.
    $args = ("" + $listArgs).Trim()
    $exit_pat = "exit +(\d+)"
    if ($args -match $exit_pat) {
	$global:LASTEXITCODE = ([int] $Matches[1])
    }

    # Echo commands could be run to return an array of strings back to
    # the powershell script. Look for that case.
    #
    # Seems to split array based on '&' and ',' in the echo statement.
    $args = ("" + $listArgs).Trim()
    $r = @()
    if ($args.Contains("echo ")) {
        $args = $args.SubString($args.IndexOf("echo ") + "echo ".Length).Trim()
        $splitChar = ","
        if ($args.Contains("&")) {
            $splitChar = "&"
        }
        foreach ($f in $args.Split($splitChar)){
            # Maybe just get the 1st char? CMD.exe is a mess...
            $r += $f.Trim()[0]
        }
    }
    return $r
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

function VirtualAlloc {

    param(
        [Parameter(
             Mandatory=$True,
             ValueFromRemainingArguments=$true,
             Position = 1
         )][string[]]
        $listArgs
    )

    # record the VirtualAlloc command.
    $behaviors = @("process")
    $subBehaviors = @()
    $behaviorProps = @{
	"args" = "" + $listArgs
    }
    
    RecordAction $([Action]::new($behaviors, $subBehaviors, "VirtualAlloc", $behaviorProps, $MyInvocation, ""))
}

function Invoke-WebRequest() {

    # Pull out the URL being hit from the arguments.
    $listArgs = $args
    $uriFlag = $false
    $url = ""
    $lastArg = ""
    $flagArg = $false
    foreach ($arg in $listArgs) {
        if ($arg -eq "-uri") {
            $uriFlag = $true
            $flagArg = $true
            continue
        }
        if ($uriFlag -or ($arg -like "http*")) {
            $url = $arg;
        }
        $uriFlag = $false
        if ($arg.StartsWith("-")) {
            $flagArg = $true
        }
        else {
            if (-not $flagArg) {
                $lastArg = $arg
            }
            $flagArg = $false
        }	
    }

    # Looks like you can leave the https:// off the URL. Check for
    # that.
    if (($url -eq "") -and ($lastArg.Length -gt 5)) {
	$match = [Regex]::Match($lastArg[0], "[a-zA-Z0-9]")
	if ($match.Success) {
	    $url = ("https://" + $lastArg)
	}
    }
    
    # Save the behavior.
    $behaviors = @("network")
    $subBehaviors = @()
    $behaviorProps = @{
	"uri" = $url
    }

    RecordAction $([Action]::new($behaviors, $subBehaviors, "Invoke-WebRequest", $behaviorProps, $MyInvocation, ""))
    # Return Write-Host so we can see if this is executed by IEX.
    return [PSCustomObject]@{
        "content"="Write-Host ""EXECUTED DOWNLOADED PAYLOAD"""
    }
}

##############################################
##############################################
# TYPE ACCELERATOR DEFINITIONS
##############################################
##############################################

# Ex: $c = [WMICLASS]"\\$computer\root\cimv2:WIn32_Process";
class WMICLASS {

    # Optionally, add attributes to prevent invalid values
    [ValidateNotNullOrEmpty()][string]$WMIItem

    # Constructor.
    WMICLASS($v) {
        # Save the WMI class in case we need it for future work.
        $this.WMIItem = $v
    }

    Create([string[]] $margs) {
        $proc = $margs[0]
        # record the full process creation command.
        $behaviors = @("script_exec")
        $subBehaviors = @("start_process")
        $behaviorProps = @{
	    "wmi_process" = $proc
        }
        
        RecordAction $([Action]::new($behaviors, $subBehaviors, "WMI", $behaviorProps, $MyInvocation, ""))
    }

    [PSCustomObject] CreateInstance() {
        return [PSCustomObject]@{
            "ShowWindow"=0
        }
    }
}

function Add-MpPreference {

    param(
        [Parameter(
             ValueFromRemainingArguments=$true,
             Position = 1
         )][string[]]
        $listArgs
    )

    # record the full Defender exclusions setting command.
    $behaviors = @("other")
    $subBehaviors = @()
    $behaviorProps = @{
	"args" = "" + $listArgs
    }
    RecordAction $([Action]::new($behaviors, $subBehaviors, "Add-MpPreference", $behaviorProps, $MyInvocation, ""))
}

function Set-MpPreference {

    param(
        [Parameter(
             ValueFromRemainingArguments=$true,
             Position = 1
         )][string[]]
        $listArgs
    )

    # record the full Defender exclusions setting command.
    $behaviors = @("other")
    $subBehaviors = @()
    $behaviorProps = @{
	"args" = "" + $listArgs
    }
    RecordAction $([Action]::new($behaviors, $subBehaviors, "Set-MpPreference", $behaviorProps, $MyInvocation, ""))
}

function Copy-Item {

    param(
        [Parameter(
             ValueFromRemainingArguments=$true,
             Position = 1
         )][string[]]
        $listArgs
    )

    $behaviors = @("other")
    $subBehaviors = @()
    $behaviorProps = @{
	"args" = "" + $listArgs
    }
    RecordAction $([Action]::new($behaviors, $subBehaviors, "Copy-Item", $behaviorProps, $MyInvocation, ""))
}

# gcm "i*x" returns more than just "iex" under Linux. Fix that.
$_origGetCommand = (Get-Command Get-Command)
function Get-Command {

    param(
        [Parameter(
             Mandatory=$True,
             ValueFromRemainingArguments=$true,
             Position = 1
         )][string[]]
        $listArgs
    )

    $cmds = (&($_origGetCommand) $listArgs)
    foreach ($cmd in $cmds) {
        if ($cmd.Name -eq "iex") {
            return @($cmd)
        }
    }

    return $cmds
}

$global:testPathAttempts = 0;
function Test-Path {

    param(
        [Parameter(
             ValueFromRemainingArguments=$true,
             ValueFromPipeline=$true,
             Position = 1
         )][string[]]
        $listArgs
    )

    $behaviors = @("file_system")
    $subBehaviors = @("check_for_file")
    $behaviorProps = @{
	"args" = "" + $listArgs
    }
    RecordAction $([Action]::new($behaviors, $subBehaviors, "Test-Path", $behaviorProps, $MyInvocation, ""))

    # TODO: Need command line argument to make this return true or
    #  false. For now return false until several calls have been made
    # and then return true. This is to handle while loops checking to
    # see if a file does or does not exist.
    $global:testPathAttempts++
    return ($testPathAttempts -gt 5)
}

function Invoke-CimMethod {

    param(
        $ClassName,
        $MethodName,
        $Arguments
    )

    # Currently only handling running a process with Invoke-CimMethod.
    # Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine=('ms' + 'hta' + '.exe '+$l)}
    if (($className -eq "Win32_Process") -and ($MethodName -eq "Create")) {
        if ($Arguments.ContainsKey("CommandLine")) {

            # Pull out the command being run.
            $cmd = $Arguments["CommandLine"]

            # Track box-ps behavior.
            $behaviors = @("script_exec")
            $subBehaviors = @("start_process")
            $behaviorProps = @{}
            $behaviorProps["script"] = $cmd
            RecordAction $([Action]::new($behaviors, $subBehaviors, "Invoke-CimMethod", $behaviorProps, $MyInvocation, ""))
        }
    }
}

function Convert-String {

    param(
        $Example,
        [Parameter(ValueFromPipeline=$true)]
        $InputObject
    )

    # This is a very limited implementation of Convert-String. It only
    # handles 1 usage case where -Example is of the form '...=...' and
    # -InputObject is a space delimited string.
    if ((-not ($Example -is [string])) -or (-not ($InputObject -is [string]))) {
        return
    }
    if (-not ($Example -like "*=*")) {
        return
    }

    # Pull out the pattern into which to subsititute substrings.
    $pat = (($Example -split "=")[1])

    # Pull out the substrings to put into the pattern.
    $substs = ($InputObject -split " ")

    # Replace the substrings in reverse index order to make sure 10 is
    #  replaced before 1. First step is replace the numbers in the
    # pattern with '##NUM##' so that when handle cases where there are
    # numbers in the replacement substrings.
    $pos = ($substs.Length)
    $r = $pat
    while ($pos -gt 0) {
        $r = ($r -replace ('' + $pos), ('##' + $pos + '##'))
        $pos--
    }

    # Now actually substitute in the replacement substrings.
    $pos = ($substs.Length)
    while ($pos -gt 0) {
        $currSubst = ($substs[$pos-1])
        $r = ($r -replace ('##' + $pos + '##'), $currSubst)
        $pos--
    }

    # Record that we ran this cmdlet.
    $behaviors = @("other")
    $subBehaviors = @()
    $behaviorProps = @{
	"result" = "" + $r
    }
    RecordAction $([Action]::new($behaviors, $subBehaviors, "Convert-String", $behaviorProps, $MyInvocation, ""))
    
    # Done.
    return $r
}

# Fake the result of Get-Location.
function Get-Location {
    return "\C_DRIVE\Users\victim\AppData\Local\Temp";
}

# A function that does nothing. Used to override commands/cmdlets that
# we just want to ignore.
function noop {}

function fakeschtasks {

    param(
        [Parameter(
	     ValueFromPipeline=$true,
             Mandatory=$True,
             ValueFromRemainingArguments=$true,
             Position = 1
         )][string[]]
        $listArgs
    )
    
    $behaviors = @("script_exec")
    $subBehaviors = @()
    $behaviorProps = @{
	"args" = "" + $listArgs
    }
    
    RecordAction $([Action]::new($behaviors, $subBehaviors, "schtasks", $behaviorProps, $MyInvocation, ""))
}

function Get-PSDrive {

    param(
        [Parameter(
	     ValueFromPipeline=$true,
             Mandatory=$True,
             ValueFromRemainingArguments=$true,
             Position = 1
         )][string[]]
        $listArgs
    )
    
    $behaviors = @("file_system")
    $subBehaviors = @()
    $behaviorProps = @{
	"args" = "" + $listArgs
    }
    
    RecordAction $([Action]::new($behaviors, $subBehaviors, "schtasks", $behaviorProps, $MyInvocation, ""))

    # Fake some disk info.
    $r = @(
	@{"Name" = "C:\"; "Used" = 231.12; "Free" = 76.1; "Root" = "C:\"}
    )
    return $r;
}

function Get-CimInstance {

    param(
        [Parameter(ValueFromPipeline=$true)] $item
    )

    # record the command.
    $behaviors = @("process")
    $subBehaviors = @()
    $behaviorProps = @{
	"args" = "" + $item
    }
    
    RecordAction $([Action]::new($behaviors, $subBehaviors, "Get-CimInstance", $behaviorProps, $MyInvocation, ""))
    
    # Stubbed class.
    class INFO {

        $TotalPhysicalMemory
	$NumberOfCores
	$Caption
	$Description
	$InstallDate
	$Name
	$Status
	$Availability
	$ConfigManagerErrorCode
	$ConfigManagerUserConfig
	$CreationClassName
	$DeviceID
	$ErrorCleared
	$ErrorDescription
	$LastErrorCode
	$PNPDeviceID
	$PowerManagementCapabilities
	$PowerManagementSupported
	$StatusInfo
	$SystemCreationClassName
	$SystemName
	$MaxNumberControlled
	$ProtocolSupported
	$TimeOfLastReset
	$AcceleratorCapabilities
	$CapabilityDescriptions
	$CurrentBitsPerPixel
	$CurrentHorizontalResolution
	$CurrentNumberOfColors
	$CurrentNumberOfColumns
	$CurrentNumberOfRows
	$CurrentRefreshRate
	$CurrentScanMode
	$CurrentVerticalResolution
	$MaxMemorySupported
	$MaxRefreshRate
	$MinRefreshRate
	$NumberOfVideoPages
	$VideoMemoryType
	$VideoProcessor
	$NumberOfColorPlanes
	$VideoArchitecture
	$VideoMode
	$AdapterCompatibility
	$AdapterDACType
	$AdapterRAM
	$ColorTableEntries
	$DeviceSpecificPens
	$DitherType
	$DriverDate
	$DriverVersion
	$ICMIntent
	$ICMMethod
	$InfFilename
	$InfSection
	$InstalledDisplayDrivers
	$Monochrome
	$ReservedSystemPaletteEntries
	$SpecificationVersion
	$SystemPaletteEntries
	$VideoModeDescription
	$PSComputerName
        $SystemDirectory
        $Organization
        $BuildNumber
        $RegisteredUser
        $SerialNumber
        $Version
        
        INFO() {
            $this.TotalPhysicalMemory = 15032385536
	    $this.NumberOfCores = 6
	    $this.Caption = "Intel(R) Graphics"
	    $this.Description = "Intel(R) Graphics"
	    $this.InstallDate = ""
	    $this.Name = "Intel(R) Graphics"
	    $this.Status = "OK"
	    $this.Availability = "3"
	    $this.ConfigManagerErrorCode = "0"
	    $this.ConfigManagerUserConfig = "False"
	    $this.CreationClassName = "Win32_VideoController"
	    $this.DeviceID = "VideoController1"
	    $this.ErrorCleared = ""
	    $this.ErrorDescription = ""
	    $this.LastErrorCode = ""
	    $this.PNPDeviceID = "PCI\VEN_8086&DEV_8AF7&SUBSYS_64D0A091&REV_08\3&11583659&0&10"
	    $this.PowerManagementCapabilities = ""
	    $this.PowerManagementSupported = ""
	    $this.StatusInfo = ""
	    $this.SystemCreationClassName = "Win32_ComputerSystem"
	    $this.SystemName = "DESKTOP_862"
	    $this.MaxNumberControlled = ""
	    $this.ProtocolSupported = ""
	    $this.TimeOfLastReset = ""
	    $this.AcceleratorCapabilities = ""
	    $this.CapabilityDescriptions = ""
	    $this.CurrentBitsPerPixel = "32"
	    $this.CurrentHorizontalResolution = "3440"
	    $this.CurrentNumberOfColors = "4294967296"
	    $this.CurrentNumberOfColumns = "0"
	    $this.CurrentNumberOfRows = "0"
	    $this.CurrentRefreshRate = "59"
	    $this.CurrentScanMode = "4"
	    $this.CurrentVerticalResolution = "1440"
	    $this.MaxMemorySupported = ""
	    $this.MaxRefreshRate = "75"
	    $this.MinRefreshRate = "29"
	    $this.NumberOfVideoPages = ""
	    $this.VideoMemoryType = "2"
	    $this.VideoProcessor = "Intel(R) Graphics Family"
	    $this.NumberOfColorPlanes = ""
	    $this.VideoArchitecture = "5"
	    $this.VideoMode = ""
	    $this.AdapterCompatibility = "Intel Corporation"
	    $this.AdapterDACType = "Internal"
	    $this.AdapterRAM = "2127378552"
	    $this.ColorTableEntries = ""
	    $this.DeviceSpecificPens = ""
	    $this.DitherType = "0"
	    $this.DriverDate = "9/12/2024 7:00:00 PM"
	    $this.DriverVersion = "32.0.101.6078"
	    $this.ICMIntent = ""
	    $this.ICMMethod = ""
	    $this.InfFilename = "oem302.inf"
	    $this.InfSection = "MTL_IG"
	    $this.InstalledDisplayDrivers = "C:\WINDOWS\System32\DriverStore\FileRepository\iigd_dch.inf_amd64_f40a5aed298593e0\igd9trinity64.dll"
	    $this.Monochrome = "False"
	    $this.ReservedSystemPaletteEntries = ""
	    $this.SpecificationVersion = ""
	    $this.SystemPaletteEntries = ""
	    $this.VideoModeDescription = "3440 x 1440 x 4294967296 colors"
	    $this.PSComputerName = ""
            $this.SystemDirectory = "C:\Windows\system32"
            $this.Organization = "solegit.com"
            $this.BuildNumber = "18363"
            $this.RegisteredUser = "desktop01@solegit.com"
            $this.SerialNumber = "00239-20000-00000-AAOEM"
            $this.Version = "10.0.18363"
        }
    }
    
    # Only handling getting certain info.
    if (($item -eq "Win32_ComputerSystem") -or
	($item -eq "Win32_Processor") -or
	($item -eq "Win32_Process") -or
        ($item -eq "Win32_OperatingSystem") -or
	($item -eq "Win32_VideoController")) {

	# Return stubbed info object.
        return ([INFO]::new())	
    }

    # Not handled.
    throw ("Get-CimInstance on unhandled item " + $item)
}

function Get-WmiObject {

    $listArgs = $args
    
    $behaviors = @("other")
    $subBehaviors = @()
    $behaviorProps = @{
	"args" = "" + $listArgs
    }
    RecordAction $([Action]::new($behaviors, $subBehaviors, "Get-WmiObject", $behaviorProps, $MyInvocation, ""))
    return ([WMICLASS]::new("" + $listArgs))
}
