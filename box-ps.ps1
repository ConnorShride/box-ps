<# known issues 
    Overrides do not support wildcard arguments, so if the malicious powershell uses wildcards and the
    override goes ahead and executes the function because it's safe, it may error out (which is fine)

    liable to have AmbiguousParameterSet errors...
        - Get-Help doesn't say whether or not the param is required differently accross parameter sets,
            so if it's required in one but not the other, we may get this error
        -Maybe just on New-Object so far? There was weird discrepancies between the linux Get-Help and the
            windows one
#>

param (
    [parameter(Position=0, Mandatory=$true)][String]$InFile,
    [parameter(Position=1, Mandatory=$true)][String]$OutFile
)

if (!(Test-Path $InFile)) {
    Write-Host "[-] input file does not exist. exiting."
    exit -1
}

$config = Get-Content .\config.json | ConvertFrom-Json -AsHashtable

<###################################################################################################
TODO

    -commandlets that may fit into two behaviors (upload/download) like Invoke-WebRequest or
        Invoke-RestMethod. maybe back off the specificity and just go network behavior


    -Output each layer's stderr as a possible canary?
    -Have the "Line" field split by semicolons and show just the statement?
        - or run a beautifier to make sure each line is on it's own (make sure it doesn't break it)
    -Add code inspection and replacement of explicit namespace references that is getting around our 
    overrides + Some deob of layers so we can have a chance of replacing namespaces
    -catch commands run like schtasks.exe
        See if hook is available in powershell to do something every time an executable that is not 
        .Net executes List of aliases to override (pointing straight to linux binaries)
    -overrides are formulaic. Make it easy to add a new one
        -don't rule out doing invoke expression
        -use Get-Help -Full commandlet to generate bound parameter definitions
            -if this is easy enough, there will be no Unbound params because every override will
            easily become a fully implemented advanced function clone of the real one

    Faking it...
        -Go through and allow more functions to do their stuff under certain circumstances
            ex. Get-ChildItem all the time
        -Have webclient methods return dummy data to keep the script from erroring out?

To Sandbox...
    Get-Date
    Get-WmiObject
    Get-Host
    Class System.Net.WebRequest

After inspection/replacement...

    [Environment]::GetFolderPath
    [IO.File]::WriteAllBytes
###################################################################################################>

####################################################################################################
function ReadNewLayers {
    param(
        [String]$LayersFilePath
    )

    # layer file may not have been created if there were no layering commands
    $layersContent = Get-Content $LayersFilePath -Raw -ErrorAction SilentlyContinue

    if ($null -ne $layersContent) {

        $layers = $layersContent.Split("LAYERDELIM")

        # check for empty entries manually b/c the split option didn't work
        return $layers | Where-Object { $_.Trim() –ne "" }
    }
    else {
        return $null
    }
}

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

function BuildFuncParamsCode {

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

        if ($helpParam.parameterSetName -ne "(All)") {
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

function BuildBehaviorPropsCode {

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

function BuildClassFuncOverrides {

    param(
        [string] $ParentClass,
        [string] $Behavior,
        [string] $FuncName,
        [hashtable] $BehaviorPropArgs
    )

    # have Get-Member give us all the function's signatures
    $tmpObject = Microsoft.PowerShell.Utility\New-Object $ParentClass
    $signatures = $tmpObject | Get-Member | Where-Object Name -eq $FuncName
    $signatures = $signatures.Definition.Split("),")
    $code = ""

    # iterate over each signature the function has 
    foreach ($signature in $signatures) {

        $signature = $signature.ToString().Trim()

        if (!($signature.EndsWith(")"))) {
            $signature += ")"
        }

        $signature = TranslateClassFuncSignature $signature

        $code += $signature + " {`r`n"
        $code += TabPad $(BuildBehaviorPropsCode $BehaviorPropArgs)
        $code += "`tRecordAction `$([Action]::new(@(`"$Behavior`"), `"$ParentClass`.$FuncName`", `$behaviorProps, `$PSBoundParameters, `$MyInvocation.Line))`r`n"
        if (!$signature.StartsWith("[void]")) {
            $code += "`treturn `$null`r`n"
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
    $Signature = $Signature.Insert(0, "[").Insert($Signature.IndexOf(" ") + 1, "]")

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

function BuildClassOverride {

    param(
        [string] $FullClassName,
        [hashtable] $Functions
    )

    $shortName = $FullClassName.Split(".")[-1]
    $code = "class BoxPS$shortName : $FullClassName {`r`n"

    # iterate over the behaviors
    foreach ($behavior in $Functions.Keys) {

        # iterate over the functions we want to create overrides for
        foreach ($functionName in $Functions[$behavior].Keys) {

            $behaviorPropArgs = $Functions[$behavior][$functionName]
            $code += TabPad $(BuildClassFuncOverrides $FullClassName $behavior $functionName `
                $behaviorPropArgs)
        }
    }

    return $code + "}`r`n"
}

function BuildArgModificationCode {

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

function BuildCmdletOverride {
    
    param (
        [string] $Behavior,
        [string] $CmdletName,
        [hashtable] $CmdletInfo
    )

    $code = "function $CmdletName {`r`n"
    $code += TabPad $(BuildFuncParamsCode $CmdletName $CmdletInfo["ArgAdditions"])
    $code += TabPad $(BuildArgModificationCode $CmdletInfo["ArgModifications"])
    $code += TabPad $(BuildBehaviorPropsCode $CmdletInfo.BehaviorPropArgs)

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

function BuildEnvVars {

    $code = ""
    foreach ($var in $config["environment"].keys) {
        $code += "$var = `"$($config["environment"][$var])`"`r`n"
    }
    return $code
}

function SeparateLines
{
    param([char[]]$Script)

    $prevChar = ''
    $beautified = ''
    $inLiteral = $false
    $quotingChar = ''
    $quotes = '"', "'"
    $whitespace = ''

    foreach ($char in $Script) {

        # if the character is not inside a string literal
        if ($inLiteral -eq $false) {
            
            # if this is the start of a string literal, record the quote used to start it
            if ($char -contains $quotes) {
                $quotingChar = $char
                $inLiteral = $true
            }
            elseif ($char -eq ';') { $whitespace = "`r`n" }
        }
        # otherwise if it's the ending quote of a string literal
        elseif ($char -contains $quotes -and $quotingChar -eq $char -and $prevChar -ne '`') {
            $quotingChar = ''
            $inLiteral = $false
        }

        $beautified += $char + $whitespace
        $prevChar = $char
        $whitespace = ''
    }

    return $beautified
}


####################################################################################################
function BuildBaseDecoder {

    param(
        [String] $ActionFilePath,
        [String] $LayersFilePath
    )

    $decoderPath = "$PSScriptRoot/decoder"
    $baseDecoder = ""

    $baseDecoder += [IO.File]::ReadAllText("$decoderPath/administrative.ps1") + "`n`n"

    $baseDecoder = $baseDecoder.Replace("ACTIONS_OUTFILE_PLACEHOLDER", $ActionFilePath)
    $baseDecoder = $baseDecoder.Replace("LAYERS_OUTFILE_PLACEHOLDER", $LayersFilePath)

    foreach ($class in $config["classes"].Keys) {
        $baseDecoder += BuildClassOverride $class $config["classes"][$class]
    }

    foreach ($behavior in $config["commandlets"].keys) {
        foreach($commandlet in $config["commandlets"][$behavior].keys) {
            $cmdletInfo = $config["commandlets"][$behavior][$commandlet]
            $baseDecoder += BuildCmdletOverride $behavior $commandlet $cmdletInfo
        }
    }

    $baseDecoder += [IO.File]::ReadAllText("$decoderPath/manual_overrides.ps1") + "`r`n`r`n"
    $baseDecoder += BuildEnvVars
    $baseDecoder += [IO.File]::ReadAllText("$decoderPath/initial_setup.ps1") + "`r`n`r`n"

    return $baseDecoder
}

####################################################################################################
function SplitReplacement {

    param(
        [String] $Layer
    )

    if (($Layer -is [String]) -and ($Layer -Like "*.split(*")) {

        $start = $Layer.IndexOf(".split(", [System.StringComparison]::CurrentCultureIgnoreCase)
        $end = $Layer.IndexOf(")", $start)
        $split1 = $Layer.Substring($start, $end - $start + 1)
        $split2 = $split1
        if (($split1.Length -gt 11) -and (-not ($split1 -Like "*[char[]]*"))) {
            $start = $split1.IndexOf("(") + 1
            $end = $split1.IndexOf(")") - 1
            $chars = $split1.Substring($start, $end - $start + 1).Trim()
            $split2 = ".Split([char[]]" + $chars + ")"
        }
        $Layer = $Layer.Replace($split1, $split2)
    }    

    return $Layer
}

# look for environment variables and coerce them to be lowercase
function EnvReplacement {

    param(
        [String] $Layer
    )

    foreach ($var in $config["environment"].keys) {
        $Layer = $Layer -ireplace [regex]::Escape($var), $var
    }

    return $Layer -ireplace "pshome", "bshome"
}

# ensures no file name collision
function GetTmpFilePath {

    $done = $false
    $fileName = ""

    while (!$done) {
        $fileName = [System.IO.Path]::GetTempPath() + [GUID]::NewGuid().ToString() + ".txt";
        if (!(Test-Path $fileName)) {
            $done = $true
        }
    }

    return $fileName
}

$encodedScript = (Get-Content $InFile -ErrorAction Stop | Out-String)

# record original encoded script, start building JSON for actions
"{`"EncodedScript`": " | Out-File $OutFile
$encodedScript.Trim() | ConvertTo-Json | Out-File -Append $OutFile
",`"Actions`": [" | Out-File -Append $OutFile

$layersFilePath = GetTmpFilePath
$layers = New-Object System.Collections.Queue
$layers.Enqueue($encodedScript)

$baseDecoder = BuildBaseDecoder $OutFile $layersFilePath

while ($layers.Count -gt 0) {

    $layer = $layers.Dequeue()
    $layer = EnvReplacement $layer
    $layer = SplitReplacement $layer
    $layer = SeparateLines $layer

    $decoder = $baseDecoder + "`r`n`r`n" + $layer
    $decoder | Out-File ./decoder.txt

    $tmpFile = GetTmpFilePath
    $decoder | Out-File -FilePath $tmpFile
    (timeout 5 pwsh -noni $tmpFile 2> $null)
    Remove-Item -Path $tmpFile

    foreach ($newLayer in ReadNewLayers($layersFilePath)) {
        if ($null -ne $newLayer) {
            $layers.Enqueue($newLayer)
        }
    }

    Remove-Item $layersFilePath -ErrorAction SilentlyContinue
}

# trim ending comma, add ending braces, prettify JSON, rewrite
(Get-Content -Raw $OutFile).Trim("`r`n,") + "]}" | ConvertFrom-Json | ConvertTo-Json -Depth 10 | 
    Out-File $OutFile
