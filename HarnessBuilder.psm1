$utils = Microsoft.PowerShell.Core\Import-Module -Name $PSScriptRoot/Utils.psm1 -AsCustomObject -Scope Local
$config = Microsoft.PowerShell.Management\Get-Content $PSScriptRoot/config.json | 
    Microsoft.PowerShell.Utility\ConvertFrom-Json -AsHashtable

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

    $helpResults = Microsoft.PowerShell.Core\Get-Help -Full $Cmdlet
    $helpParams = $helpResults.parameters.parameter

    if ($ArgAdditions) {
        foreach ($argAddition in $ArgAdditions.Keys) {
            $helpParams += $(Microsoft.PowerShell.Utility\New-Object `
                                PSObject -Property $ArgAdditions[$argAddition])
        }
    }

    $code = "param(`r`n"

    foreach ($helpParam in $HelpParams) {

        # check if it has a non-default parameter set that we need to support
        if ($helpParam.parameterSetName -ne "(All)" -and $helpParam.parameterSetName -ne "Default") {
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
    $Strings | ForEach-Object { $array += "`"" + $_ + "`"," } 
    return $array.Trim(",") + ")"
}

function InMemoryIOCsCode {
    $code += "`$scrapeIOCsCode = Microsoft.PowerShell.Management\Get-Content -Raw `$CODE_DIR/harness/find_in_mem_iocs.ps1`r`n"
    $code += "Microsoft.PowerShell.Utility\Invoke-Expression `$scrapeIOCsCode`r`n"
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

            # behavior property value is a hard-coded string, not a function argument
            if ($behaviorPropArgs.GetType() -eq [string]) {
                $code += "`$behaviorProps[`"$behaviorProp`"] = @(`"$($behaviorPropArgs)`")`r`n"
            }
            else {

                if ($behaviorPropArgs.Count -eq 1) {
                    $code += "`$behaviorProps[`"$behaviorProp`"] = `@(`$$($behaviorPropArgs[0]))`r`n"
                }
                # for commandlets, we have to find the argument that's present at script run-time
                elseif ($Cmdlet) {

                    $first = $true
                    foreach ($arg in $behaviorPropArgs) {

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

                    $sigArgsNames = $SigAndArgs.Item2

                    foreach ($arg in $behaviorPropArgValues) {
                        if ($arg.GetType() -eq [string]) {
                            if ($sigArgsNames.Contains($arg)) {
                                $code += "`$behaviorProps[`"$behaviorProp`"] = @(`$$arg)`r`n"
                            }
                        }
                        # it's a hashtable
                        # behavior property value may be a property of an argument that is an object
                        else {

                            # name of the object-arg in the signature and the property of the object
                            $objectArgName = $($arg.Keys[0]).ToString()
                            $objectProp = $arg[$objectArgName]

                            if ($sigArgsNames.Contains($objectArgName)) {
                                $code += "`$behaviorProps[`"$behaviorProp`"] = @(`$$objectArgName.$objectProp)`r`n"
                            }
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

    $guineaPig = Microsoft.PowerShell.Utility\New-Object $ParentClass
    $properties = GetPropertyTypes $ParentClass
    $shortName = $ParentClass.Split(".")[-1]
    $code = "BoxPS$shortName () {`r`n"

    foreach ($property in $properties.Keys) {

        # get the value of the property we're wanting to create an override for from our guinea pig 
        # object to see how the actual .Net constructor runs
        Microsoft.PowerShell.Utility\Invoke-Expression "`$realProperty = `$guineaPig.$property"

        if ($null -ne $realProperty) {
            
            # get the actual runtime type
            Microsoft.PowerShell.Utility\Invoke-Expression `
                "`$runtimeType = `$realProperty.GetType().FullName"
            if ($runtimeType.Contains("+")) {
                $runtimeType = $runtimeType.Split("+")[0]
            }

            # try to actually use the constructor first before putting it into the harness
            # powershell may give a type here that isn't actually useful, and in these situations
            # the script will (hopefully, probably) have to reassign the object anyways
            try{
                Microsoft.PowerShell.Utility\Invoke-Expression "[$runtimeType]::new()" > $null
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

    $guineaPig = Microsoft.PowerShell.Utility\New-Object $ParentClass
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
        $signatures = $guineaPig | Microsoft.PowerShell.Utility\Get-Member | 
                        Microsoft.PowerShell.Core\Where-Object Name -eq $FuncName
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
        $sigAndArgs[$signature] = @($Matches[1].Split(", ") | 
                                    Microsoft.PowerShell.Core\ForEach-Object { $_.Split()[1]})
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

    # if Static, FuncName must be fully qualified name including namespace
    # and ParentClass is not given
    # TODO: Make parameter sets for these for clarity
    param(
        [switch] $Static,
        [string] $ParentClass,
        [string] $FuncName,
        [hashtable] $OverrideInfo,
        [string[]] $Exclude
    )

    $signatures = @{}

    # get all the function signatures
    if ($Static) {
        $signatures = GetFunctionSignatures -Static -FuncName $FuncName
    }
    else {
        $signatures = GetFunctionSignatures -InstanceMember -FuncName $FuncName -ParentClass $ParentClass
    }

    $code = ""

    foreach ($signature in $signatures.keys) {

        $sigArgs = $signatures[$signature]
        $signature = TranslateClassFuncSignature -Signature $signature

        # don't create overrides for the signatures in the set to exclude
        if (!$Exclude.Contains($signature)) {

            $sigAndArgs = [Tuple]::Create($signature, $sigArgs)
    
            # if the signature does not take an argument that we listed in the config file, then we
            # aren't supporting it
            $BehaviorPropInfo = $OverrideInfo["BehaviorPropInfo"]
            $supportedArgs = @()
            foreach ($behaviorProp in $BehaviorPropInfo.keys) {

                $behaviorPropArgs = $BehaviorPropInfo[$behaviorProp]

                # if the behaviorprop value is an object, then the value is a property of the function 
                # argument which is an object e.g. ProcessStartInfo.FileName is the "File" value for 
                # behavior file_exec in the function [Diagnostics.Process]::Start(ProcessStartInfo)
                foreach ($behaviorPropArg in $behaviorPropArgs) {
                    if ($behaviorPropArg.GetType() -eq [Hashtable]) {
                        $supportedArgs += $behaviorPropArg.Keys[0]
                    }
                    else {
                        $supportedArgs += $behaviorPropArg
                    }
                }
            }

            $intersection = $utils.ListIntersection($sigAndArgs[1], $supportedArgs)
    
            if ($intersection) {
    
                $code += $signature + " {`r`n"
                $code += $utils.TabPad($(BehaviorPropsCode -ClassFunc -SigAndArgs $sigAndArgs -BehaviorPropInfo $OverrideInfo["BehaviorPropInfo"]))
                $behaviorsListCode = $(BuildStringArrayCode $OverrideInfo["Behaviors"])

                if ($Static) {
                    $code += "`tRecordAction `$([Action]::new($behaviorsListCode, `"$FuncName`", `$behaviorProps, `$PSBoundParameters, `$MyInvocation.Line))`r`n"
                }
                else {
                    $code += "`tRecordAction `$([Action]::new($behaviorsListCode, `"$ParentClass`.$FuncName`", `$behaviorProps, `$PSBoundParameters, `$MyInvocation.Line))`r`n"
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
                    else {
                        $code += "`treturn `$null`r`n"
                    }
                }
        
                $code += "}`r`n"
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
    $code += $utils.TabPad($(ClassConstructor -ParentClass $FullClassName))

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
    $behaviorsListCode = $(BuildStringArrayCode $CmdletInfo["Behaviors"])
    
    $code = "function $shortName {`r`n"
    $code += $utils.TabPad($(CmdletParamsCode $shortName $CmdletInfo["ArgAdditions"]))
    $code += $utils.TabPad($(InMemoryIOCsCode))
    $code += $utils.TabPad($(ArgModificationCode $CmdletInfo["ArgModifications"]))
    $code += $utils.TabPad($(BehaviorPropsCode -Cmdlet -BehaviorPropInfo $CmdletInfo.BehaviorPropInfo))

    $code += "`tRecordAction `$([Action]::new($behaviorsListCode, `"$($CmdletName)`", `$behaviorProps, `$MyInvocation))`r`n"

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

function BuildHarness {

    $harnessPath = "$PSScriptRoot/harness"
    $harness = ""
    $commentSep = "################################################################################"

    # code containing namespace imports, class definition for Actions
    $harness += [IO.File]::ReadAllText("$harnessPath/administrative.ps1").Replace("<CODE_DIR>", $PSScriptRoot) + "`r`n`r`n"

    # may need to boxify script layers as they get decoded and executed
    $harness += "Microsoft.PowerShell.Core\Import-Module -Name `$CODE_DIR/ScriptInspector.psm1`r`n`r`n"

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