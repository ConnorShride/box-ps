$config = Get-Content $PSScriptRoot\config.json | ConvertFrom-Json -AsHashtable

function TabPad {
    
    param (
        [string] $block
    )

    $newBlock = ""

    foreach ($line in $block.Split("`r`n")) {
        $newBlock += "`t" + $line + "`r`n"
    }
    
    return $newBlock
}

function StaticParamsCode {

    param(
        [string] $Signature
    )

    $Signature = TranslateClassFuncSignature $Signature
    $paramsReg = "\((.+)\)"
    $code = "param(`r`n"
    
    $Signature -match $paramsReg > $null
    $params = $Matches[1].Replace(", ", ",`r`n")
    $code += TabPad $params

    return $code + "`r`n)"
}

function CmdletParamsCode {

    param(
        [string] $Commandlet,
        [hashtable] $ArgAdditions
    )

    $helpParams = Get-Help -Full $Commandlet
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
        [hashtable] $BehaviorPropArgs
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
                # if there are multiple args in the function that can give you the desired 
                # behavior property, take either argument that is present
                if ($BehaviorPropArgs[$behaviorProp].Count -gt 1) {

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
                elseif ($BehaviorPropArgs[$behaviorProp].Count -eq 1) {
                    $code += "`$behaviorProps[`"$behaviorProp`"] = `@(`$$($BehaviorPropArgs[$behaviorProp][0]))`r`n"
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

function ClassFunctionOverride {

    param(
        [switch] $BoxPSStatic,
        [string] $ParentClass,
        [string] $Behavior,
        [string] $FuncName,
        [hashtable] $BehaviorPropArgs
    )

    $signatures = @()

    if ($BoxPSStatic) {
        $signatures = $(Invoke-Expression $FuncName).OverloadDefinitions
    }
    else {
        $tmpObject = Microsoft.PowerShell.Utility\New-Object $ParentClass
        $signatures = $tmpObject | Get-Member | Where-Object Name -eq $FuncName
        $signatures = $signatures.Definition.Split("),")
    }

    $code = ""

    # iterate over each signature the function has 
    foreach ($signature in $signatures) {

        $signature = $signature.ToString().Trim()

        if (!($signature.EndsWith(")"))) {
            $signature += ")"
        }

        $signature = TranslateClassFuncSignature $signature

        $code += $signature + " {`r`n"
        $code += TabPad $(BehaviorPropsCode $BehaviorPropArgs)

        if ($BoxPSStatic) {
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

    # iterate over the behaviors
    foreach ($behavior in $Functions.Keys) {

        # iterate over the functions we want to create overrides for
        foreach ($functionName in $Functions[$behavior].Keys) {

            $behaviorPropArgs = $Functions[$behavior][$functionName]
            $code += TabPad $(ClassFunctionOverride -ParentClass $FullClassName -Behavior $behavior `
                 -FuncName $functionName -BehaviorPropArgs $behaviorPropArgs)
        }
    }

    return $code + "}`r`n"
}

function ClassOverrides {

    $code = ""

    foreach ($class in $config["classes"].Keys) {
        $code += ClassOverride $class $config["classes"][$class]
    }

    return $code
}

function StaticOverrides {

    $code = "class BoxPSStatics {`r`n"

    foreach ($behavior in $config["statics"].keys) {
        foreach ($staticFunc in $config["statics"][$behavior].keys) {

            $overrideInfo = $config["statics"][$behavior][$staticFunc]

            $code += TabPad $(ClassFunctionOverride -BoxPSStatic -Behavior $behavior -FuncName `
                $overrideInfo.FullActor -BehaviorPropArgs $overrideInfo.BehaviorPropArgs)
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

    $code = "function $CmdletName {`r`n"
    $code += TabPad $(CmdletParamsCode $CmdletName $CmdletInfo["ArgAdditions"])
    $code += TabPad $(ArgModificationCode $CmdletInfo["ArgModifications"])
    $code += TabPad $(BehaviorPropsCode $CmdletInfo.BehaviorPropArgs)

    if ($CmdletInfo.LayerArg) {
        $code += "`tRecordLayer(`$$($CmdletInfo.LayerArg))`r`n"
    }

    $code += "`tRecordAction `$([Action]::new(@(`"$Behavior`"), `"$($CmdletInfo.FullActor)`", `$behaviorProps, `$MyInvocation))`r`n"

    if ($CmdletInfo.ExtraCode) {
        foreach ($line in $CmdletInfo.ExtraCode) {
            $code += "`t" + $line + "`r`n"
        }
    }

    if ($CmdletInfo.Flags) {
        if ($CmdletInfo.Flags -contains "call_parent") {
            $code += "`treturn $($CmdletInfo.FullActor) @PSBoundParameters`r`n"
        }
    }

    return $code + "}`r`n"
}

function EnvironmentVars {

    $code = ""
    foreach ($var in $config["environment"].keys) {
        $code += "$var = `"$($config["environment"][$var])`"`r`n"
    }
    return $code
}

function Build {

    param(
        [String] $ActionFilePath,
        [String] $LayersFilePath
    )

    $decoderPath = "$PSScriptRoot/decoder"
    $baseDecoder = ""

    $baseDecoder += [IO.File]::ReadAllText("$decoderPath/administrative.ps1") + "`n`n"

    $baseDecoder = $baseDecoder.Replace("ACTIONS_OUTFILE_PLACEHOLDER", $ActionFilePath)
    $baseDecoder = $baseDecoder.Replace("LAYERS_OUTFILE_PLACEHOLDER", $LayersFilePath)
    $baseDecoder = $baseDecoder.Replace("CONFIG_PLACEHOLDER", $PSScriptRoot)

    foreach ($class in $config["classes"].Keys) {
        $baseDecoder += ClassOverride $class $config["classes"][$class]
    }

    $baseDecoder += StaticOverrides

    foreach ($behavior in $config["commandlets"].keys) {
        foreach($commandlet in $config["commandlets"][$behavior].keys) {
            $overrideInfo = $config["commandlets"][$behavior][$commandlet]
            $baseDecoder += CmdletOverride $behavior $commandlet $overrideInfo
        }
    }

    $baseDecoder += [IO.File]::ReadAllText("$decoderPath/manual_overrides.ps1") + "`r`n`r`n"
    $baseDecoder += EnvironmentVars
    $baseDecoder += [IO.File]::ReadAllText("$decoderPath/initial_setup.ps1") + "`r`n`r`n"

    return $baseDecoder
}

Export-ModuleMember -Function Build