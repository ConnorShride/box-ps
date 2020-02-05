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
	
	$parentVars = Get-Variable -Scope 1
	$localVars = Get-Variable -Scope 0
    $localVars = $localVars | ForEach-Object { $_.Name }
    
    # import all the variables from the parent scope so the invoke expression has them to work with
	foreach ($parentVar in $parentVars) {
	    if (!($localVars.Contains($parentVar.Name))) {
	        Set-Variable -Name $parentVar.Name -Value $parentVar.Value
	    }
    }
    
    RecordLayer $Command
    RecordAction $([Action]::new(@("script_exec"), "Microsoft.PowerShell.Utility\Invoke-Expression", $behaviorProps, $MyInvocation))

    # ex. $foo = Invoke-Expression "New-Object System.Net.WebClient"
    $invokeRes = Microsoft.PowerShell.Utility\Invoke-Expression @PSBoundParameters

    # invoked command may have initialized more variables that are to be used later
    $localVars = Get-Variable -Scope 0
    $parentVars = $parentVars | ForEach-Object { $_.Name }

    # yes... foreach is indeed a variable
    $thisDeclaredVars = @("Command", "behaviorProps", "parentVars", "localVars", "parentVar", 
        "invokeRes", "localVar", "varName", "foreach", "PSCmdlet")

    foreach ($localVar in $localVars) {
        $varName = $localVar.Name
        # Export the variable only if it came from the Invoke-Expression
        if (!($parentVars.Contains($varName)) -and !($thisDeclaredVars.Contains($varName))) {
	        Set-Variable -Name $varName -Value $localVar.Value -Scope 1
	    }
    }

	return $invokeRes
}
