<# known issues 
    Overrides do not support wildcard arguments, so if the malicious powershell uses wildcards and the
    override goes ahead and executes the function because it's safe, it may error out (which is fine)

    liable to have AmbiguousParameterSet errors...
        - Get-Help doesn't say whether or not the param is required differently accross parameter sets,
            so if it's required in one but not the other, we may get this error
        -Maybe just on New-Object so far? There was weird discrepancies between the linux Get-Help and the
            windows one
#>

<###################################################################################################
TODO

    Before open source..

        -Find a way to preserve script action order when there are IEX. Right now the actions from 
        that next layer are after the current layer, when in reality they are right in the middle

        -always allow for known-safe functions right now. Not making the framework for levels
        of safety yet

        -commenting, style (variable/funciton names), readme, other documentation?
            - get rid of "Code" at the end of functions in HarnessBuilder

        -investigate SplitReplacement and see what it does (hopefully remove it)

        -generalize stuff into the utils class (configs access is pretty repeated throughout)

        To Sandbox...
        
            Get-Date
            Get-WmiObject
            Get-Host
            Class System.Net.WebRequest

        After inspection/replacement...

            [Environment]::GetFolderPath
            [IO.File]::WriteAllBytes
            [Diagnostics.Process]::Start


    -commandlets that may fit into two behaviors (upload/download) like Invoke-WebRequest or
        Invoke-RestMethod. maybe back off the specificity and just go network behavior

    -add type goverernor (or something named like that), so we can add entries in the config file that
    determine which member of an object to use as it's representation in the output file (encoding
    and process objects) (hopefully replacing FlattenProcessObjects)

    -add some static deob for scrubbing explicit namespaces?
        - string deob could be really easy... just detect if it's being done (like a bunch of formatting)
          and run powershell on the string (see iranianshit.ps1)

    -Add support for automated building of all constructors of an object, not just the default one
        -[type].GetConstructors() | ForEach-Object { $_.GetParameters() }

    -catch commands run like schtasks.exe
        See if hook is available in powershell to do something every time an executable that is not 
        .Net executes List of aliases to override (pointing straight to linux binaries)

    -show enum name when it's an argument? 
        -ex. [BoxPSStatics]::GetFolderPath([System.Environment+SpecialFolder]::Desktop) gives
        argument value of 0

    -object properties that we care about tracking? (ex. User-agent strings)

    -get rid of rewriting the JSON file to make it look pretty. For big scripts this is going to kill

    -Faking it...
        -Have webclient methods return dummy data in safe mode to keep the script from erroring out?
        -framework for allowing functions to execute under certain circumstances
            -Invoke-WebRequest in semi-safe mode 
            -inspect downloaded content to see if it's more powershell and allow it to execute

        -another docker container in tandem that is receiving the web requests box-ps makes, and 
        sending them through TOR guard
    
    -configreader module that ingests the config file into easy to work with objects

###################################################################################################>

param (
    [parameter(Position=0, Mandatory=$true)][String] $InFile,
    [parameter(Position=1, Mandatory=$true)][String] $OutFile,
    [parameter(Position=2)][String] $ErrorDir
)

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

if (!(Test-Path $InFile)) {
    Write-Host "[-] input file does not exist. exiting."
    exit -1
}

if ($PSBoundParameters.ContainsKey("ErrorDir")) {

    if (!(Test-Path $ErrorDir)) {
        New-Item -ItemType "directory" -Path $ErrorDir > $null
        Write-Host "[+] created directory $ErrorDir"
    }
    else {
        Write-Host "[+] error directory $ErrorDir already exists"
        Remove-Item -Force $ErrorDir/*
        Write-Host "[+] cleared contents of directory $ErrorDir"
    }
}

# DEBUG
if (Test-Path ./dbgharness) {
    Remove-Item -Force ./dbgharness/*
    Write-Host "[+] cleared directory dbgharness"
}

$harnessBuilder = Import-Module -Name ./HarnessBuilder.psm1 -AsCustomObject -Scope Local
$layerInspector = Import-Module -Name ./LayerInspector.psm1 -AsCustomObject -Scope Local
$utils = Import-Module -Name ./Utils.psm1 -AsCustomObject -Scope Local

$encodedScript = (Get-Content $InFile -ErrorAction Stop | Out-String)

# record original encoded script, start building JSON for actions
"{`"Script`": " | Out-File $OutFile
$encodedScript.Trim() | ConvertTo-Json | Out-File -Append $OutFile
",`"Actions`": [" | Out-File -Append $OutFile

$layersFilePath = $utils.GetTmpFilePath()
$layers = New-Object System.Collections.Queue
$layers.Enqueue($encodedScript)
$layerCount = 1
 
$baseHarness = $harnessBuilder.Build($OutFile, $layersFilePath)
$baseHarness | Out-File ./dbgharness/harness.txt

while ($layers.Count -gt 0) {

    $layer = $layers.Dequeue()
    $layer = $layerInspector.EnvReplacement($layer)
    $layer = $layerInspector.SplitReplacement($layer)
    $layer = $utils.SeparateLines($layer)
    $layer = $layerInspector.HandleNamespaces($layer)

    $harness = $baseHarness + "`r`n`r`n" + $layer
    $layer | Out-File ./dbgharness/layer$($layerCount).txt

    $harnessedScriptPath = $utils.GetTmpFilePath()
    Write-Host $harnessedScriptPath
    $harness | Out-File -FilePath $harnessedScriptPath

    Read-Host "enter to run layer"

    if ($ErrorDir) {
        (timeout 5 pwsh -noni $harnessedScriptPath 2> "$ErrorDir/layer$($layerCount)error.txt")
    }
    else {
        (timeout 5 pwsh -noni $harnessedScriptPath 2> $null)
    }

    Remove-Item -Path $harnessedScriptPath

    foreach ($newLayer in ReadNewLayers($layersFilePath)) {
        if ($null -ne $newLayer) {
            $layers.Enqueue($newLayer)
        }
    }

    Remove-Item $layersFilePath -ErrorAction SilentlyContinue
    $layerCount++
}

# trim ending comma, add ending braces, prettify JSON, rewrite
(Get-Content -Raw $OutFile).Trim("`r`n,") + "]}" | ConvertFrom-Json | ConvertTo-Json -Depth 10 | 
    Out-File $OutFile

Remove-Module HarnessBuilder
Remove-Module LayerInspector
Remove-Module Utils