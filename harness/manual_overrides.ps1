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

    RecordAction $([Action]::new(@("file_system"), "Microsoft.PowerShell.Core\mkdir", $behaviorProps, $MyInvocation))
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
    
    RecordAction $([Action]::new(@("script_exec"), "Microsoft.PowerShell.Utility\Invoke-Expression", $behaviorProps, $MyInvocation))

    $modifiedCommand = BoxifyScript $Command

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
	
    RecordAction $([Action]::new(@("new_object"), "Microsoft.PowerShell.Utility\New-Object", $behaviorProps, $MyInvocation))
    
	if ($(GetOverridedClasses).Contains($behaviorProps["object"].ToLower())) {
	   return RedirectObjectCreation $TypeName
    }
    
	return Microsoft.PowerShell.Utility\New-Object @PSBoundParameters
}

function powershell.exe {

    param(
        [Alias("e")]
        [string] $EncodedCommand,
        [string] $File,
        [switch] $NoLogo,
        [Alias("nop")]
        [switch] $NoProfile,
        [switch] $NonInteractive,
        [Alias("w")]
        [string] $WindowStyle
    )

    $behaviorProps = @{}

    if ($PSBoundParameters.ContainsKey("EncodedCommand")) {
        $decodedCommand = [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String($EncodedCommand))
        $behaviorProps["script"] = $decodedCommand
    }
    elseif ($PSBoundParameters.ContainsKey("File")) {
        $behaviorProps["script"] = $File
    }

    RecordAction $([Action]::new(@("script_exec"), "powershell.exe", $behaviorProps, $MyInvocation))

    Microsoft.PowerShell.Utility\Invoke-Expression $decodedCommand
}
