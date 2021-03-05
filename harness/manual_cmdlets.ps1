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

    $behaviorProps = @{ 
        "paths" = $Path
    }

    RecordAction $([Action]::new(@("file_system"), "Microsoft.PowerShell.Core\mkdir", $behaviorProps, $MyInvocation, ""))
}

function Invoke-Expression {

	param(
		[Parameter(ValueFromPipeline=$true,Position=0,Mandatory=$true)]
		[string] $Command
	)
    
	$behaviorProps = @{
        "script" = @($Command)
    }
	
	$parentVars = Microsoft.PowerShell.Utility\Get-Variable -Scope 1
	$localVars = Microsoft.PowerShell.Utility\Get-Variable -Scope 0
    $localVars = $localVars | Microsoft.PowerShell.Core\ForEach-Object { $_.Name }
    
    # import all the variables from the parent scope so the invoke expression has them to work with
	foreach ($parentVar in $parentVars) {
	    if (!($localVars.Contains($parentVar.Name))) {
	        Microsoft.PowerShell.Utility\Set-Variable -Name $parentVar.Name -Value $parentVar.Value
	    }
    }
    
    RecordAction $([Action]::new(@("script_exec"), "Microsoft.PowerShell.Utility\Invoke-Expression", $behaviorProps, $MyInvocation, ""))

    $modifiedCommand = PreProcessScript $Command "<PID>"

    # actually run it, assign the result for situations like...
    # ex. $foo = Invoke-Expression "New-Object System.Net.WebClient"
    $invokeRes = Microsoft.PowerShell.Utility\Invoke-Expression $modifiedCommand

    # invoked command may have initialized more variables that are to be used later, that are now
    # defined in this local scope
    $localVars = Microsoft.PowerShell.Utility\Get-Variable -Scope 0
    $parentVars = $parentVars | Microsoft.PowerShell.Core\ForEach-Object { $_.Name }

    # yes... foreach is indeed a variable
    $thisDeclaredVars = @("Command", "behaviorProps", "parentVars", "localVars", "parentVar", 
        "invokeRes", "localVar", "varName", "foreach", "PSCmdlet")

    # pick out the variables the Invoke-Expression defined, export them to the parent scope
    foreach ($localVar in $localVars) {
        $varName = $localVar.Name
        if (!($parentVars.Contains($varName)) -and !($thisDeclaredVars.Contains($varName))) {
	        Microsoft.PowerShell.Utility\Set-Variable -Name $varName -Value $localVar.Value -Scope 1
	    }
    }

	return $invokeRes
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
	$behaviorProps = @{}
    
	# read in the script from the file to sandbox
	# just try to on the off chance they put it in the current dir so this will actually work (no windows paths)
	if ($FilePath) {
        $script = Microsoft.PowerShell.Management\Get-Content -Raw $FilePath
        $behaviorProps["script"] = @($script)
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

        $behaviorProps["script"] = @($ScriptBlock.StartPosition.Content)
	}

	RecordAction $([Action]::new(@("script_exec"), "Microsoft.PowerShell.Core\Start-Job", $behaviorProps, $MyInvocation, ""))

	$invokeRes = ""
	if ($script) {

		$modifiedCommand = PreProcessScript $script "<PID>"

		# actually run it, assign the result for situations like...
		# ex. $foo = Invoke-Expression "New-Object System.Net.WebClient"
		$invokeRes = Microsoft.PowerShell.Utility\Invoke-Expression $modifiedCommand
	}

	return $invokeRes
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
		$behaviorProps["object"] = @($COMObject)
    }
    
	elseif ($PSBoundParameters.ContainsKey("TypeName")) {
		$behaviorProps["object"] = @($TypeName)
	}
	
    RecordAction $([Action]::new(@("new_object"), "Microsoft.PowerShell.Utility\New-Object", $behaviorProps, $MyInvocation, ""))
    
	if ($(GetOverridedClasses).Contains($behaviorProps["object"].ToLower())) {
	   return RedirectObjectCreation $TypeName
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
        [switch] $NoLogo,
        [switch] $NoProfile,
        [switch] $NonInteractive
    )
    
    $behaviorProps = @{}

    if ($PSBoundParameters.ContainsKey("Command")) {
		# command was given arg list style like "powershell Write-Host foo"
		# join the list into a single string
		if ($Command.Count -gt 1) {
			foreach ($token in $Command) {
				$behaviorProps["script"] += $token + " "
			}
		}
		else {
			$behaviorProps["script"] = $Command[0].ToString()
		}
    }
    if ($PSBoundParameters.ContainsKey("EncodedCommand")) {
        $decodedScript = [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String($EncodedCommand))
        $behaviorProps["script"] = $decodedScript
    }
    # read the script and execute?
    elseif ($PSBoundParameters.ContainsKey("File")) {
        $behaviorProps["script"] = $File
    }

    RecordAction $([Action]::new(@("script_exec"), "powershell.exe", $behaviorProps, $MyInvocation, ""))

    $boxifiedScript = PreProcessScript $behaviorProps["script"] "<PID>"

	Microsoft.PowerShell.Utility\Invoke-Expression $boxifiedScript
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
