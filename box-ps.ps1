<# known issues 
    Overrides do not support wildcard arguments, so if the malicious powershell uses wildcards and the
    override goes ahead and executes the function because it's safe, it may error out (which is fine)
#>

param (
    [parameter(Position=0, Mandatory=$true)][String]$InFile,
    [parameter(Position=1, Mandatory=$true)][String]$OutFile
)

if (!(Test-Path $InFile)) {
    Write-Host "[-] input file does not exist. exiting."
    exit -1
}

<###################################################################################################
TODO

    -Output each layer's stderr as a possible canary?
    -Have the "Line" field split by semicolons and show just the statement?
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
    -script argument validation and useful error message
    -separate out namespace from Actor (have a field with just the commandlet)

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

####################################################################################################
function BuildBaseDecoder {

    param(
        [String] $ActionFilePath,
        [String] $LayersFilePath
    )

    $decoderPath = "$PSScriptRoot/Decoder"
    $baseDecoder = ""

    $baseDecoder += [IO.File]::ReadAllText("$decoderPath/administrative.ps1") + "`n`n"

    $baseDecoder = $baseDecoder.Replace("ACTIONS_OUTFILE_PLACEHOLDER", $ActionFilePath)
    $baseDecoder = $baseDecoder.Replace("LAYERS_OUTFILE_PLACEHOLDER", $LayersFilePath)

    $baseDecoder += [IO.File]::ReadAllText("$decoderPath/classes.ps1") + "`n`n"

    foreach ($decoderFile in Get-ChildItem -Path $decoderPath/commandlets | Select-Object FullName) {
        $baseDecoder += [IO.File]::ReadAllText($decoderFile.FullName) + "`n`n"
    }

    $baseDecoder += [IO.File]::ReadAllText("$decoderPath/environment.ps1") + "`n`n"
    $baseDecoder += [IO.File]::ReadAllText("$decoderPath/initial_setup.ps1") + "`n`n"

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

    $knownVars = @(
        "`$env:allusersprofile",
        "`$env:allusersprofile",
        "`$env:appdata",
        "`$env:commonprogramfiles",
        "`${env:commonprogramfiles}",
        "`$env:commonprogramw6432",
        "`$env:computername",
        "`$env:comspec",
        "`$env:homedrive",
        "`$env:homepath",
        "`$env:localappdata",
        "`$env:logonserver",
        "`$env:path",
        "`$env:programdata",
        "`$env:programfiles",
        "`${env:programfiles(x86)}",
        "`$env:program6432",
        "`$env:psmodulepath",
        "`$env:public",
        "`$env:systemdrive",
        "`$env:systemroot",
        "`$env:temp",
        "`$env:tmp",
        "`$env:userdomain",
        "`$env:username",
        "`$env:userprofile",
        "`$env:windir",
        "`$maximumdrivecount",
        "`$pshome",
        "`$pshome1"
    )

    foreach ($var in $knownVars) {
        $Layer = $Layer -ireplace [regex]::Escape($var), $var
    }

    return $Layer -replace "pshome", "bshome"
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

    $decoder = $baseDecoder + "`r`n`r`n" + $layer

    Write-Host $decoder
    Read-Host

    $tmpFile = GetTmpFilePath
    $decoder | Out-File -FilePath $tmpFile
    (timeout 5 pwsh -noni $tmpFile 2> 'stderr.txt')
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
