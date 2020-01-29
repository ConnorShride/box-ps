$utils = Import-Module -Name ./Utils.psm1 -AsCustomObject -Scope Local

$config = Get-Content $PSScriptRoot\config.json | ConvertFrom-Json -AsHashtable


function StaticParamsCode {

    param(
        [string] $Signature
    )

    $Signature = TranslateClassFuncSignature $Signature
    $paramsReg = "\((.+)\)"
    $code = "param(`r`n"
    
    $Signature -match $paramsReg > $null
    $params = $Matches[1].Replace(", ", ",`r`n")
    $code += $utils.TabPad($params)

    return $code + "`r`n)"
}

function CmdletParamsCode {

    param(
        [string] $Cmdlet,
        [hashtable] $ArgAdditions
    )

    $helpParams = Get-Help -Full $Cmdlet
    $helpParams = $helpParams.parameters.parameter

    if ($ArgAdditions) {
        foreach ($argAddition in $ArgAdditions.Keys) {
            $helpParams += $(New-Object PSObject -Property $ArgAdditions[$argAddition])
        }
    }

    $code = "param(`r`n"

    foreach ($helpParam in $HelpParams) {

        $advancedArgOps = ""

        if ($helpParam.parameterSetName -ne "(All)" -and $helpParam.parameterSetName -ne "Default") {
            $setNames = $helpParam.parameterSetName.Split(",")
            if ($setNames.Length -gt 1) {
                foreach ($setName in $setNames) {
                    $code += "`t[Parameter(ParameterSetName=`"$($setName.Trim())`")]`r`n"
                }
            }
            else {
                $advancedArgOps += "ParameterSetName=`"$($helpParam.parameterSetName)`","
            }
        }

        if ($helpParam.pipelineInput.Contains("true")) {
            $advancedArgOps += "ValueFromPipeline=`$true,"
        }
        if ($helpParam.position -ne "Named") {
            $advancedArgOps += "Position=$($helpParam.position),"
        }
        if ($helpParam.required -eq "true") {
            $advancedArgOps += "Mandatory=`$true,"
        }
        $advancedArgOps = $advancedArgOps.TrimEnd(',') 

        if ($advancedArgOps) {
            $code += "`t[Parameter($advancedArgOps)]`r`n"
        }

        if ($helpParam.aliases -ne "None") {
            $code += "`t[Alias("
            foreach ($alias in $helpParam.aliases) {
                $code += "`"$alias`","
            }
            $code = $code.TrimEnd(",") + ")]`r`n"
        }

        $code += "`t[$($helpParam.type.name)] `$$($helpParam.Name),`r`n"
    }

    $code = $code.TrimEnd(",`r`n`t") + "`r`n)"

    return $code
}

function BehaviorPropsCode {

    param(
        [hashtable] $BehaviorPropArgs,
        [switch] $ClassFunc,
        [Tuple[string, string[]]] $SigAndArgs,
        [switch] $Cmdlet
    )

    $code = "`$behaviorProps = @{}`r`n"

    # functions belonging to the "other" behavior will not have defined behavior properties
    if ($BehaviorPropArgs) {

        foreach ($behaviorProp in $BehaviorPropArgs.Keys) {

            # behavior property value is a hard-coded string, not a function argument
            if ($BehaviorPropArgs[$behaviorProp].GetType() -eq [string]) {
                $code += "`$behaviorProps[`"$behaviorProp`"] = @(`"$($BehaviorPropArgs[$behaviorProp])`")`r`n"
            }
            else {

                if ($BehaviorPropArgs[$behaviorProp].Count -eq 1) {
                    $code += "`$behaviorProps[`"$behaviorProp`"] = `@(`$$($BehaviorPropArgs[$behaviorProp][0]))`r`n"
                }
                # for commandlets, we have to find the argument that's present at script run-time
                elseif ($Cmdlet) {

                    $first = $true
                    foreach ($arg in $BehaviorPropArgs[$behaviorProp]) {

                        $block = "if (`$PSBoundParameters.ContainsKey(`"$arg`")) {`r`n"
                        $block += "`t`$behaviorProps[`"$behaviorProp`"] = @(`$$arg)`r`n"
                        $block += "}`r`n"

                        if (!$first) {
                            $block = $block.Replace("if ", "elseif ")
                        }

                        $first = $false
                        $code += $block
                    }
                }
                # for class functions, find the argument that it must be from the function signature
                elseif ($ClassFunc) {
                    foreach ($arg in $BehaviorPropArgs[$behaviorProp]) {
                        if ($SigAndArgs.Item2.Contains($arg)) {
                            $code += "`$behaviorProps[`"$behaviorProp`"] = @(`$$arg)`r`n"
                        }
                    }
                }
            }
        }
    }

    return $code
}

function ArgModificationCode {

    param(
        [hashtable] $ArgModifications
    )

    $code = ""

    foreach ($argument in $ArgModifications.Keys) {

        $code += "if (`$PSBoundParameters.ContainsKey(`"$argument`")) {`r`n"

        foreach ($modification in $ArgModifications[$argument]) {
            $modification = $modification.Replace("<arg>", "`$PSBoundParameters[`"$argument`"]")
            $code += "`t`$$argument = $modification`r`n"
            $code += "`t`$PSBoundParameters[`"$argument`"] = $modification`r`n"
        }

        $code += "}`r`n"
    }

    return $code
}

# translate .Net function signature into PS syntax
function TranslateClassFuncSignature {

    param(
        [string] $Signature
    )

    # function return value type
    if ($Signature.StartsWith("static ")) {
        $scanNdx = $Signature.IndexOf(" ") + 1
        $Signature = $Signature.Insert($scanNdx, "[").Insert($Signature.IndexOf(" ", $scanNdx) + 1, "]")
    }
    else {
        $Signature = $Signature.Insert(0, "[").Insert($Signature.IndexOf(" ") + 1, "]")
    }

    # first argument type and variables 
    $firstArgTypeNdx = $Signature.IndexOf('(') + 1
    $Signature = $Signature.Insert($firstArgTypeNdx, "[")
    $firstArgNdx = $Signature.IndexOf(' ', $firstArgTypeNdx) + 2
    $Signature = $Signature.Insert($firstArgNdx - 2, "]").Insert($firstArgNdx, "$")
    
    # subsequent argument types and variables
    $scanNdx = $firstArgNdx
    while ($Signature.IndexOf(',', $scanNdx) -ne -1) {
        $typeNdx = $Signature.IndexOf(',', $scanNdx) + 2
        $Signature = $Signature.Insert($typeNdx, '[')
        $endTypeNdx = $Signature.IndexOf(' ', $typeNdx)
        $Signature = $Signature.Insert($endTypeNdx, ']').Insert($endTypeNdx + 2, '$')
        $scanNdx = $endTypeNdx
    }

    return $Signature
}

# currently only builds code for the default constructor, so some object initialization will fail on
# scripts in the wild
function ClassConstructor {

    param(
        [string] $ParentClass
    )

    $guineaPig = New-Object $ParentClass
    $properties = GetPropertyTypes $ParentClass
    $shortName = $ParentClass.Split(".")[-1]
    $code = "BoxPS$shortName () {`r`n"

    foreach ($property in $properties.Keys) {

        # get the value of the property we're wanting to create an override for from our guinea pig 
        # object to see how the actual .Net constructor runs
        Invoke-Expression "`$realProperty = `$guineaPig.$property"

        if ($null -ne $realProperty) {
            
            # get the actual runtime type
            Invoke-Expression "`$runtimeType = `$realProperty.GetType().FullName"
            if ($runtimeType.Contains("+")) {
                $runtimeType = $runtimeType.Split("+")[0]
            }

            # try to actually use the constructor first before putting it into the harness
            # powershell may give a type here that isn't actually useful, and in these situations
            # the script will (hopefully, probably) have to reassign the object anyways
            try{
                Invoke-Expression "[$runtimeType]::new()" > $null
                $code += $utils.TabPad("`$this.$($property) = [$runtimeType]::new()")
            }
            catch {}
        }
    }

    return $code + "}`r`n"
}

function GetPropertyTypes {

    param(
        [string] $ObjectType
    )

    $guineaPig = New-Object $ParentClass
    $properties = Get-Member -InputObject $guineaPig | Where-Object MemberType -eq property

    $res = @{}
    foreach ($property in $properties) {
        $res[$property.Name] = $property.Definition.Split(" ")[0]
    }

    return $res
}

# returns a dictionary where the keys are the full signature and the values are a list of arguments
function GetFunctionSignatures {

    param(
        [string] $FuncName,
        [string] $ParentClass,
        [switch] $Static,
        [switch] $InstanceMember
    )

    $signatures = @()

	# get the list of signatures
    if ($Static) {
		$signatures = $(Invoke-Expression $FuncName).OverloadDefinitions
	}
    elseif ($InstanceMember) {
        $guineaPig = Microsoft.PowerShell.Utility\New-Object $ParentClass
		$signatures = $guineaPig | Get-Member | Where-Object Name -eq $FuncName
        $signatures = $signatures.Definition.Split("),") | ForEach-Object {
			if (!$_.EndsWith(")")) {
				$_ += ")"
			}
			$_.Trim()
		}
    }

	$sigAndArgs = @{}

    # parse out the arguments, parse out names of arguments only
    foreach ($signature in $signatures) {

        $signature -match "\((.*)\)" > $null
        $sigAndArgs[$signature] = @($Matches[1].Split(", ") | ForEach-Object { $_.Split()[1]})
    }
    
    return $sigAndArgs
}

function ClassPropertiesCode {

    param(
        [string] $ParentClass
    )

    $properties = GetPropertyTypes $ParentClass

    foreach ($propertyType in $properties.Keys) {
        $code += "[$($properties[$propertyType])] `$$propertyType`r`n"
    }

    return $code
}

function ClassFunctionOverride {

    # if Static, FuncName must be fully qualified name including namespace
    param(
        [switch] $Static,
        [string] $ParentClass,
        [string] $Behavior,
        [string] $FuncName,
        [hashtable] $BehaviorPropArgs
    )

    $signatures = @{}

    if ($Static) {
        $signatures = GetFunctionSignatures -Static -FuncName $FuncName
    }
    else {
        $signatures = GetFunctionSignatures -InstanceMember -FuncName $FuncName -ParentClass $ParentClass
    }

    $code = ""

    foreach ($signature in $signatures.keys) {

        $sigArgs = $signatures[$signature]
        $signature = TranslateClassFuncSignature $signature
        $sigAndArgs = [Tuple]::Create($signature, $sigArgs)

        $code += $signature + " {`r`n"
        $code += $utils.TabPad($(BehaviorPropsCode -ClassFunc -SigAndArgs $sigAndArgs -BehaviorPropArgs $BehaviorPropArgs))

        if ($Static) {
            $code += "`tRecordAction `$([Action]::new(@(`"$Behavior`"), `"$FuncName`", `$behaviorProps, `$PSBoundParameters, `$MyInvocation.Line))`r`n"
        }
        else {
            $code += "`tRecordAction `$([Action]::new(@(`"$Behavior`"), `"$ParentClass`.$FuncName`", `$behaviorProps, `$PSBoundParameters, `$MyInvocation.Line))`r`n"
        }

        if (!$signature.Contains("[void]")) {
            $code += "`treturn `$null`r`n"
        }

        $code += "}`r`n"
    }

    return $code
}

function ClassOverride {

    param(
        [string] $FullClassName,
        [hashtable] $Functions
    )

    $shortName = $FullClassName.Split(".")[-1]
    $code = "class BoxPS$shortName {`r`n"

    $code += $utils.TabPad($(ClassPropertiesCode -ParentClass $FullClassName))
    $code += $utils.TabPad($(ClassConstructor -ParentClass $FullClassName))

    # iterate over the behaviors
    foreach ($behavior in $Functions.Keys) {

        # iterate over the functions we want to create overrides for
        foreach ($functionName in $Functions[$behavior].Keys) {

            $behaviorPropArgs = $Functions[$behavior][$functionName].BehaviorPropArgs
            $code += $utils.TabPad($(ClassFunctionOverride -ParentClass $FullClassName -Behavior $behavior `
                 -FuncName $functionName -BehaviorPropArgs $behaviorPropArgs))
        }
    }

    return $code + "}`r`n"
}

function ClassOverrides {

    $code = ""

    foreach ($class in $config["Classes"].Keys) {
        $code += ClassOverride $class $config["Classes"][$class]
    }

    return $code
}

function StaticOverrides {

    $code = "class BoxPSStatics {`r`n"

    foreach ($behavior in $config["Statics"].keys) {
        foreach ($staticFunc in $config["Statics"][$behavior].keys) {

            $overrideInfo = $config["Statics"][$behavior][$staticFunc]

            $code += $utils.TabPad($(ClassFunctionOverride -Static -Behavior $behavior -FuncName `
                $staticFunc -BehaviorPropArgs $overrideInfo.BehaviorPropArgs))
        }
    }

    return $code + "}`r`n"
}

function CmdletOverride {
    
    param (
        [string] $Behavior,
        [string] $CmdletName,
        [hashtable] $CmdletInfo
    )

    $shortName = $utils.GetUnqualifiedName($CmdletName)
    $code = "function $shortName {`r`n"
    $code += $utils.TabPad($(CmdletParamsCode $shortName $CmdletInfo["ArgAdditions"]))
    $code += $utils.TabPad($(ArgModificationCode $CmdletInfo["ArgModifications"]))
    $code += $utils.TabPad($(BehaviorPropsCode -Cmdlet -BehaviorPropArgs $CmdletInfo.BehaviorPropArgs))

    if ($CmdletInfo.LayerArg) {
        $code += "`tRecordLayer(`$$($CmdletInfo.LayerArg))`r`n"
    }

    $code += "`tRecordAction `$([Action]::new(@(`"$Behavior`"), `"$($CmdletName)`", `$behaviorProps, `$MyInvocation))`r`n"

    if ($CmdletInfo.ExtraCode) {
        foreach ($line in $CmdletInfo.ExtraCode) {
            $code += "`t" + $line + "`r`n"
        }
    }

    if ($CmdletInfo.Flags) {
        if ($CmdletInfo.Flags -contains "call_parent") {
            $code += "`treturn $CmdletName @PSBoundParameters`r`n"
        }
    }

    return $code + "}`r`n"
}

function EnvironmentVars {

    $code = ""
    foreach ($var in $config["Environment"].keys) {
        $code += "$var = `"$($config["Environment"][$var])`"`r`n"
    }
    return $code
}

function Build {

    param(
        [String] $ActionFilePath,
        [String] $LayersFilePath
    )

    $harnessPath = "$PSScriptRoot/harness"
    $baseHarness = ""

    $baseHarness += [IO.File]::ReadAllText("$harnessPath/administrative.ps1") + "`n`n"

    $baseHarness = $baseHarness.Replace("ACTIONS_OUTFILE_PLACEHOLDER", $ActionFilePath)
    $baseHarness = $baseHarness.Replace("LAYERS_OUTFILE_PLACEHOLDER", $LayersFilePath)
    $baseHarness = $baseHarness.Replace("CONFIG_PLACEHOLDER", $PSScriptRoot)

    foreach ($class in $config["Classes"].Keys) {
        $baseHarness += ClassOverride $class $config["Classes"][$class]
    }

    $baseHarness += StaticOverrides

    foreach ($behavior in $config["Cmdlets"].keys) {
        foreach($cmdlet in $config["Cmdlets"][$behavior].keys) {
            $overrideInfo = $config["Cmdlets"][$behavior][$cmdlet]
            $baseHarness += CmdletOverride $behavior $cmdlet $overrideInfo
        }
    }

    $baseHarness += [IO.File]::ReadAllText("$harnessPath/manual_overrides.ps1") + "`r`n`r`n"
    $baseHarness += EnvironmentVars
    $baseHarness += [IO.File]::ReadAllText("$harnessPath/initial_setup.ps1") + "`r`n`r`n"

    return $baseHarness
}

Export-ModuleMember -Function Build