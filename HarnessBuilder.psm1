$utils = Microsoft.PowerShell.Core\Import-Module -Name $PSScriptRoot/Utils.psm1 -AsCustomObject -Scope Local
$config = Microsoft.PowerShell.Management\Get-Content $PSScriptRoot/config.json |
    Microsoft.PowerShell.Utility\ConvertFrom-Json -AsHashtable

# Use the current PID to give each box-ps run a unique working directory.
# This allows multiple box-ps instances to analyze samples in the same directory.
$WORK_DIR = "./working_" + $PID

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

    $helpParams = (Microsoft.PowerShell.Core\Get-Help -Full $Cmdlet).parameters.parameter
    $doneParams = @()

    # get the default parameter set
    $defaultParamSet = (Microsoft.Powershell.Core\Get-Command $Cmdlet).DefaultParameterSet

    if ($ArgAdditions) {
        foreach ($argAddition in $ArgAdditions.Keys) {
            $helpParams += $(Microsoft.PowerShell.Utility\New-Object `
                                PSObject -Property $ArgAdditions[$argAddition])
        }
    }

    $code = ""
    if ($defaultParamSet) {
        $code += "[cmdletbinding(DefaultParameterSetName=`"$defaultParamSet`")]`r`n"
    }

    $code += "param(`r`n"

    foreach ($helpParam in $HelpParams) {

        # don't add duplicate parameters (thanks Microsoft)
        if ($doneParams -contains $helpParam.Name) {
            continue
        }

        # check if it has a non-default parameter set that we need to support
        if ($helpParam.parameterSetName -ne $null -and
            $helpParam.parameterSetName -ne "(All)" -and
            $helpParam.parameterSetName -ne "Default") {
            $setNames = $helpParam.parameterSetName.Split(",")

            foreach ($setName in $setNames) {

                $code += "`t[Parameter(ParameterSetName=`"$($setName.Trim())`""

                # parameters are mandatory with respect to the individual sets they're in,
                # and if a parameter is in multiple sets and mandatory, it's mandatory for all sets
                if ($helpParam.required -eq "true") {
                    $code += ",Mandatory=`$true"
                }

                $code += ")]`r`n"
            }
        }

        $paramOptLine = "`t[Parameter("

        # parameter takes input from the pipeline
        if ($helpParam.pipelineInput.Contains("true")) {
            $paramOptLine += "ValueFromPipeline=`$true,"
        }

        # parameter is either explicitely named or has a position
        if ($helpParam.position -ne "Named") {
            $paramOptLine += "Position=$($helpParam.position),"
        }

        $paramOptLine = $paramOptLine.TrimEnd(',')

        if ($paramOptLine -ne "`t[Parameter(") {
            $code += $paramOptLine + ")]`r`n"
        }

        # parameter may have aliases
        if ($helpParam.aliases -ne "None") {
            $code += "`t[Alias("
            foreach ($alias in $helpParam.aliases) {
                $code += "`"$alias`","
            }
            $code = $code.TrimEnd(",") + ")]`r`n"
        }

        $code += "`t[$($helpParam.type.name)] `$$($helpParam.Name),`r`n"

        $doneParams += $helpParam.Name
    }

    $code = $code.TrimEnd(",`r`n`t") + "`r`n)"

    return $code
}

# build the code to initialize an array of strings given the strings
function BuildStringArrayCode {

    param (
        [string[]] $Strings
    )

    $array = "@("
    if ($null -ne $Strings) {
        $Strings | ForEach-Object { $array += "`"" + $_ + "`"," }
    }
    return $array.Trim(",") + ")"
}

function InMemoryIOCsCode {
    $code += "`$scrapeIOCsCode = Microsoft.PowerShell.Management\Get-Content -Raw `$CODE_DIR/harness/find_in_mem_iocs.ps1`r`n"
    $code += "Microsoft.PowerShell.Utility\Invoke-Expression `$scrapeIOCsCode`r`n"
    return $code
}

function RoutineCode {

    param(
        [hashtable] $RoutineInfo
    )

    $routineScript = $RoutineInfo.Keys[0]

    # prepend an assignment of a variable the routine script cares about to an "$routineArg" variable
    if ($null -ne $RoutineInfo[$routineScript]) {
        $code += "`$routineArg = `$$($RoutineInfo[$routineScript])`r`n"
    }

    # read in the code from the snipped stored in the harness directory and IEX it
    $code += "`$routineCode = Microsoft.PowerShell.Management\Get-Content -Raw `$CODE_DIR/harness/$routineScript.ps1`r`n"
    $code += "`$routineReturn = Microsoft.PowerShell.Utility\Invoke-Expression `$routineCode`r`n"

    return $code
}

function SubBehaviorsCode {

    param(
        [string[]] $SubBehaviors
    )

    $code += ""
    $code += "`$subBehaviors = @("
    foreach ($sub in $SubBehaviors) {
        $code += "`"" + $sub + "`", "
    }
    $code = $code.TrimEnd(", ")
    $code += ")`r`n"

    return $code
}

function BuildBehaviorPropValueCode {

    param(
        [string] $BehaviorPropName,
        [string] $ArgName
    )

    $flexibleTypes = $config["BehaviorPropFlexibleTypes"]
    $forcedTypes = $config["BehaviorPropForcedTypes"]

    $code = ""

    # just leave the type as the type it is in the function
    if ($flexibleTypes.Contains($ArgName)) {
        $code += "$ArgName"
    }
    # it's forced to be a certain type in config. just cast it and pray
    else {
        if ($ArgName -eq "") {
            $code += "$($forcedTypes[$BehaviorPropName])`"`""
        }
        else {
            $code += "$($forcedTypes[$BehaviorPropName])`$$ArgName"
        }
    }

    return $code
}

function BehaviorPropsCode {

    param(
        [hashtable] $BehaviorPropInfo,
        [switch] $ClassFunc,
        [Tuple[string, string[]]] $SigAndArgs,
        [switch] $Cmdlet
    )

    $code = "`$behaviorProps = @{}`r`n"

    # functions belonging to the "other" behavior will not have defined behavior properties
    if ($BehaviorPropInfo) {

        foreach ($behaviorProp in $BehaviorPropInfo.Keys) {

            $behaviorPropArgs = $BehaviorPropInfo[$behaviorProp]

            # don't have a way to get the behavior property value yet or we can't
            if ($null -eq $behaviorPropArgs) {
                $empty = ""
                $code += "`$behaviorProps[`"$behaviorProp`"] = $(BuildBehaviorPropValueCode $behaviorProp $empty)`r`n"
            }
            # behavior property value is from a function parameter
            else {

                if ($behaviorPropArgs.Count -eq 1) {
                    $code += "`$behaviorProps[`"$behaviorProp`"] = $(BuildBehaviorPropValueCode $behaviorProp $behaviorPropArgs[0])`r`n"
                }
                # we have more than one parameter (different usages of the function) that could contain the behavior property value
                # for commandlets, we have to find the parameter that's present at script run-time
                elseif ($Cmdlet) {

                    $first = $true
                    foreach ($arg in $behaviorPropArgs) {

                        $block = "if (`$PSBoundParameters.ContainsKey(`"$arg`")) {`r`n"
                        $block += "`t`$behaviorProps[`"$behaviorProp`"] = $(BuildBehaviorPropValueCode $behaviorProp $arg)`r`n"
                        $block += "}`r`n"

                        if (!$first) {
                            $block = $block.Replace("if ", "elseif ")
                        }

                        $first = $false
                        $code += $block
                    }
                }
                # we have more than one parameter (different usages of the function) that could contain the behavior property value
                # for class functions, find the parameter that it must be from the function signature
                elseif ($ClassFunc) {

                    $arg = $utils.ListIntersection($sigAndArgs.Item2, $behaviorPropArgs)
                    $code += "`$behaviorProps[`"$behaviorProp`"] = $(BuildBehaviorPropValueCode $behaviorProp $arg)`r`n"
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

# translate .Net (C#) function signature into PowerShell class syntax
function TranslateClassFuncSignature {

    param(
        [string] $Signature
    )

    # translate function return type. wrap [] around type name
    if ($Signature.StartsWith("static ")) {
        $scanNdx = $Signature.IndexOf(" ") + 1
        $Signature = $Signature.Insert($scanNdx, "[").Insert($Signature.IndexOf(" ", $scanNdx) + 1, "]")
    }
    else {
        $Signature = $Signature.Insert(0, "[").Insert($Signature.IndexOf(" ") + 1, "]")
    }

    # handle first argument first
    # remove Params keyword (can't use the functionality in powershell anyways)
    $firstArgTypeNdx = $Signature.IndexOf('(') + 1
    if ($Signature.Substring($firstArgTypeNdx, 6) -eq "Params") {
        $Signature = $Signature.Remove($firstArgTypeNdx, 7)
    }

    # wrap [] around argument type and prepend $ to variable name
    $Signature = $Signature.Insert($firstArgTypeNdx, "[")
    $firstArgNdx = $Signature.IndexOf(' ', $firstArgTypeNdx) + 2
    $Signature = $Signature.Insert($firstArgNdx - 2, "]").Insert($firstArgNdx, "$")

    # same thing for subsequent argument types and variables
    $scanNdx = $firstArgNdx
    while ($Signature.IndexOf(',', $scanNdx) -ne -1) {
        $typeNdx = $Signature.IndexOf(',', $scanNdx) + 2
        if ($Signature.Substring($typeNdx, 6) -eq "Params") {
            $Signature = $Signature.Remove($typeNdx, 7)
        }
        $Signature = $Signature.Insert($typeNdx, '[')
        $endTypeNdx = $Signature.IndexOf(' ', $typeNdx)
        $Signature = $Signature.Insert($endTypeNdx, ']').Insert($endTypeNdx + 2, '$')
        $scanNdx = $endTypeNdx
    }

    return $Signature
}

function ClassConstructors {

    param(
        [string] $ParentClass
    )

    $guineaPig = Microsoft.PowerShell.Utility\New-Object $ParentClass
    $properties = GetPropertyTypes $ParentClass
    $shortName = $ParentClass.Split(".")[-1]
    $code = ""

    # build each public constructor
    foreach ($constructor in ([type]$ParentClass).GetConstructors()) {
        $code += "BoxPS$shortName ("

        # add constructor parameters to function signature
        foreach ($parameter in $constructor.GetParameters()) {
            $code += ("[" + $parameter.ParameterType + "]`$" + $parameter.Name + ", ")
        }
        $code = $code.Trim(", ") + ") {`r`n"

        # write code to assign the class properties to values within the constructor
        foreach ($property in $properties.Keys) {

            # TODO assign the property to the corresponding parameter if the name matches

            # get the value of the property we're wanting to create an override for from our guinea pig
            # object to see how the actual .Net constructor assigns values to the property
            Microsoft.PowerShell.Utility\Invoke-Expression "`$realProperty = `$guineaPig.$property"

            # assign the property to it's empty value, or leave it null if it is that IRL
            if ($null -ne $realProperty) {

                # get the actual runtime type
                Microsoft.PowerShell.Utility\Invoke-Expression "`$runtimeType = `$realProperty.GetType().FullName"
                if ($runtimeType.Contains("+")) {
                    $runtimeType = $runtimeType.Split("+")[0]
                }

                # try to actually use the constructor first before putting it into the harness.
                # powershell may give a type here that isn't actually initializable, and in these situations
                # the script will (hopefully, probably) have to reassign the property anyways if it's
                # important
                try{
                    Microsoft.PowerShell.Utility\Invoke-Expression "[$runtimeType]::new()" > $null
                    $code += $utils.TabPad("`$this.$($property) = [$runtimeType]::new()")
                }
                catch {}
            }
        }

        $code += "}`r`n"
    }

    return $code
}

function GetPropertyTypes {

    param(
        [string] $ObjectType
    )

    $guineaPig = Microsoft.PowerShell.Utility\New-Object $ObjectType

    # get all the advertised properties from the guineapig object
    $properties = Microsoft.PowerShell.Utility\Get-Member -InputObject $guineaPig |
                    Microsoft.PowerShell.Core\Where-Object MemberType -eq property

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
		$signatures = $(Microsoft.PowerShell.Utility\Invoke-Expression $FuncName).OverloadDefinitions
	}
    elseif ($InstanceMember) {
        $guineaPig = Microsoft.PowerShell.Utility\New-Object $ParentClass
        $signatures = $guineaPig | Microsoft.PowerShell.Utility\Get-Member | Microsoft.PowerShell.Core\Where-Object Name -eq $FuncName
        $signatures = $signatures.Definition.Split("),") | Microsoft.PowerShell.Core\ForEach-Object {
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
        $sigAndArgs[$signature] = @($Matches[1].Split(", ") | Microsoft.PowerShell.Core\ForEach-Object { $_.Split()[-1]})
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

function ClassFunctionOverrides {

    # if Static, FuncName must be fully qualified name including namespace and ParentClass is not given
    # TODO: Make parameter sets for these for clarity
    param(
        [switch] $Static,
        [string] $ParentClass,
        [string] $FuncName,
        [hashtable] $OverrideInfo,
        [object] $Exclude  # hashtable if Static, list if not
    )

    $signatures = @{}

    # get all the function signatures
    if ($Static) {

        $signatures = GetFunctionSignatures -Static -FuncName $FuncName

        # build static function signatures we're excluding from the info in config
        $excludeSignatures = @()
        foreach ($namespaceAndName in $Exclude.Keys) {
            $functionName = $utils.GetUnqualifiedName($namespaceAndName)
            foreach ($returnType in $Exclude[$namespaceAndName].Keys) {
                foreach ($parameters in $Exclude[$namespaceAndName][$returnType]) {
                    $excludeSignatures += "static " + $returnType + " $functionName($parameters)"
                }
            }
        }
        $Exclude = $excludeSignatures
    }
    else {
        $signatures = GetFunctionSignatures -InstanceMember -FuncName $FuncName -ParentClass $ParentClass
    }

    $code = ""

    foreach ($signature in $signatures.keys) {

        $sigArgs = $signatures[$signature]
        $signature = TranslateClassFuncSignature -Signature $signature

        # create overrides for the signatures we don't want to exclude
        if (!$Exclude.Contains($signature)) {

            $sigAndArgs = [Tuple]::Create($signature, $sigArgs)

            # if the signature does not take an argument that we listed in the config file, then we aren't supporting it
            $BehaviorPropInfo = $OverrideInfo["BehaviorPropInfo"]
            $supportedArgs = @()
            foreach ($behaviorProp in $BehaviorPropInfo.keys) {

                # TODO if behavior prop args are only null we want to support all signatures
                $supportedArgs += $BehaviorPropInfo[$behaviorProp]
            }

            $intersection = $utils.ListIntersection($sigAndArgs[1], $supportedArgs)

            # this signature contains a parameter we're wanting to track as a behavior property
            if ($intersection) {

                # function name will be a "squashed" name containing the namespace information
                $code += $($signature.Replace($utils.GetUnqualifiedName($FuncName) + "(", $utils.SquashStaticName($FuncName) + "(")) + " {`r`n"
                $code += "`t`$CODE_DIR = `"<CODE_DIR>`"`r`n"
                $code += "`t`$WORK_DIR = `"./working_<PID>`"`r`n"
                $code += $utils.TabPad($(BehaviorPropsCode -ClassFunc -SigAndArgs $sigAndArgs -BehaviorPropInfo $OverrideInfo["BehaviorPropInfo"]))
                $code += "`t`$behaviors = " + (BuildStringArrayCode $OverrideInfo["Behaviors"]) + "`r`n"
                $code += "`t`$subBehaviors = " + (BuildStringArrayCode $OverrideInfo.SubBehaviors) + "`r`n"

                if ($OverrideInfo["Routine"]) {
                    $code += $utils.TabPad($(RoutineCode $OverrideInfo["Routine"]))
                }

                if ($OverrideInfo["ExtraInfo"]) {
                    $code += "`t`$extraInfo = `"$($OverrideInfo["ExtraInfo"])`"`r`n"
                }
                else {
                    $code += "`t`$extraInfo = `"`"`r`n"
                }

                if ($Static) {
                    $code += "`tRecordAction `$([Action]::new(`$behaviors, `$subBehaviors, `"$FuncName`", `$behaviorProps, `$PSBoundParameters, `$MyInvocation.Line, `$extraInfo))`r`n"
                }
                else {
                    $code += "`tRecordAction `$([Action]::new(`$behaviors, `$subBehaviors, `"$ParentClass`.$FuncName`", `$behaviorProps, `$PSBoundParameters, `$MyInvocation.Line, `$extraInfo))`r`n"
                }

                # if the method actually has a return value
                if (!$signature.Contains("[void]")) {

                    # build a call to the real function to return the actual result from the override
                    if ($OverrideInfo["Flags"] -and $OverrideInfo["Flags"].Contains("call_parent")) {

                        $code += "`treturn "

                        if ($Static) {
                            $code += "$FuncName("
                        }
                        else {
                            $code += "([$ParentClass]`$this).$FuncName("
                        }

                        # build arguments to the function
                        $args = ""
                        foreach ($arg in $sigArgs) {
                            $args += "`$$arg, "
                        }
                        $args = $args.TrimEnd(", ")
                        $code += $args + ")`r`n"
                    }
                    elseif ($OverrideInfo["Return"]) {
                        $code += "`treturn $($OverrideInfo["Return"])`r`n"
                    }
                    # return null when we don't have anything to fake and we don't want to call the real one
                    else {
                        $code += "`treturn `$null`r`n"
                    }
                }

                $code += "}`r`n`r`n"
            }
        }
    }

    return $code
}


function ClassOverride {

    param(
        [string] $FullClassName,
        [hashtable] $Functions
    )

    # get the class member functions that we're overriding manually
    $excludes = $config["Manuals"]["ClassMembers"]

    $shortName = $FullClassName.Split(".")[-1]
    $code = "class BoxPS$shortName : $FullClassName {`r`n"

    $code += $utils.TabPad($(ClassPropertiesCode -ParentClass $FullClassName))
    $code += $utils.TabPad($(ClassConstructors -ParentClass $FullClassName))

    foreach ($functionName in $Functions.Keys) {

        $overrideInfo = $Functions[$functionName]
        $code += $utils.TabPad($(ClassFunctionOverrides -ParentClass $FullClassName `
                -FuncName $functionName -OverrideInfo $overrideInfo -Exclude $excludes))
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

    $commentSep = "################################################################################"
    $code = "class BoxPSStatics {`r`n"

    # get the statics that we're overriding manually
    $excludes = $config["Manuals"]["Statics"]

    foreach ($staticFunc in $config["Statics"].keys) {

        $overrideInfo = $config["Statics"][$staticFunc]

        $code += $utils.TabPad($(ClassFunctionOverrides -Static -FuncName `
            $staticFunc -OverrideInfo $overrideInfo -Exclude $excludes))
    }

    # tack on the manual overrides
    $code += $utils.TabPad($commentSep + "`r`n#MANUAL STATICS`r`n" + $commentSep + "`r`n")
    $code += $utils.TabPad($(Microsoft.PowerShell.Management\Get-Content -Raw $PSScriptRoot/harness/manual_statics.ps1))

    return $code + "}`r`n"
}

function CmdletOverride {

    param (
        [string] $CmdletName,
        [hashtable] $CmdletInfo
    )

    $shortName = $utils.GetUnqualifiedName($CmdletName)
    $code = "function $shortName {`r`n"

    # if the override does not have a behaviors member, it's not an action the user cares about
    # tracking, just a cmdlet we want to intercept for other reasons
    if (!$CmdletInfo["Behaviors"]) {
        return $code + "}`r`n"
    }

    $code += $utils.TabPad($(CmdletParamsCode $shortName $CmdletInfo["ArgAdditions"]))
    $code += $utils.TabPad($(InMemoryIOCsCode))
    $code += $utils.TabPad($(ArgModificationCode $CmdletInfo["ArgModifications"]))
    $code += $utils.TabPad($(BehaviorPropsCode -Cmdlet -BehaviorPropInfo $CmdletInfo.BehaviorPropInfo))
    $code += "`t`$behaviors = " + (BuildStringArrayCode $CmdletInfo["Behaviors"]) + "`r`n"
    $code += "`t`$subBehaviors = " + (BuildStringArrayCode $CmdletInfo.SubBehaviors) + "`r`n"

    # extra routine to run before the action is recorded, sourced from the harness directory and ran via Invoke-Expression
    if ($CmdletInfo["Routine"]) {
        $code += $utils.TabPad($(RoutineCode $CmdletInfo["Routine"]))
    }

    # there may be a hardcoded value for ExtraInfo in the config file
    # TODO add support for making the value $routineReturn
    if ($CmdletInfo["ExtraInfo"]) {
        $code += "`t`$extraInfo = `"$($CmdletInfo["ExtraInfo"])`"`r`n"
    }
    else {
        $code += "`t`$extraInfo = `"`"`r`n"
    }

    $code += "`tRecordAction `$([Action]::new(`$behaviors, `$subBehaviors, `"$($CmdletName)`", `$behaviorProps, `$MyInvocation, `$extraInfo))`r`n"

    if ($CmdletInfo.Flags -and $CmdletInfo.Flags -contains "call_parent") {
        $code += "`treturn $CmdletName @PSBoundParameters`r`n"
    }
    elseif ($CmdletInfo["Return"]) {
        $code += "`treturn $($CmdletInfo["Return"])`r`n"
    }

    return $code + "}`r`n"
}

function EnvironmentVars {

    $inputEnvFile = "$WORK_DIR/input_env.json"
    $code = ""

    # place the variables we've got in config
    foreach ($var in $config["Environment"].keys) {
        $code += "$var = `"$($config["Environment"][$var])`"`r`n"
    }

    # place whatever user-supplied variables that may or may have not been given
    if (Microsoft.PowerShell.Management\Test-Path $inputEnvFile) {
        $envVars = Microsoft.PowerShell.Management\Get-Content -Raw $inputEnvFile | ConvertFrom-Json -AsHashTable
        foreach ($envVar in $envVars.Keys) {
            $code += "`${env:$envVar} = `"$($envVars[$envVar])`"`r`n"
        }
    }

    return $code
}

function BuildHarness {

    $harnessPath = "$PSScriptRoot/harness"
    $harness = ""
    $commentSep = "################################################################################"

    # code containing namespace imports, class definition for Actions
    $harness += [IO.File]::ReadAllText("$harnessPath/administrative.ps1") + "`r`n`r`n"

    $harness += $commentSep + "`r`n#CLASSES`r`n" + $commentSep + "`r`n"
    foreach ($class in $config["Classes"].Keys) {
        $harness += ClassOverride $class $config["Classes"][$class]
    }

    $harness += $commentSep + "`r`n#STATIC FUNCTIONS`r`n" + $commentSep + "`r`n"
    $harness += StaticOverrides

    $harness += $commentSep + "`r`n#COMMANDLETS`r`n" + $commentSep + "`r`n"
    foreach ($cmdlet in $config["Cmdlets"].keys) {
        $overrideInfo = $config["Cmdlets"][$cmdlet]
        $harness += CmdletOverride $cmdlet $overrideInfo
    }

    $harness += $commentSep + "`r`n#MANUAL COMMANDLETS`r`n" + $commentSep + "`r`n"
    $harness += [IO.File]::ReadAllText("$harnessPath/manual_cmdlets.ps1") + "`r`n`r`n"
    $harness += $commentSep + "`r`n#ENVIRONMENT`r`n" + $commentSep + "`r`n"
    $harness += EnvironmentVars + "`r`n"
    $harness += $commentSep + "`r`n#OTHER SETUP`r`n" + $commentSep + "`r`n"
    $harness += [IO.File]::ReadAllText("$harnessPath/other_setup.ps1") + "`r`n`r`n"

    return $harness
}

Export-ModuleMember -Function BuildHarness
