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

    - make new-object a manual (make sure we document the config file first tho)

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
        - otherwise, probably can just add a function that's named the same?

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

function OutputLayers {
    param(
        [String]$LayersFilePath
    )

    # layer file may not have been created if there were no layering commands
    $layersContent = Get-Content $LayersFilePath -Raw -ErrorAction SilentlyContinue

    if ($null -ne $layersContent) {

        $layers = $layersContent.Split("LAYERDELIM")

        $layers | Where-Object { $_.Trim() –ne "" } | ForEach-Object {

            $str = "**********************************************`r`n"
            $str += $_ + "`r`n"
            $str += "**********************************************"
            $str | Out-File -Append "debug/layers.ps1"
        }
    }
}

if (!(Test-Path $InFile)) {
    Write-Host "[-] input file does not exist. exiting."
    exit -1
}


# DEBUG
if (Test-Path ./debug) {
    Remove-Item -Force ./debug/*
    Write-Host "[+] cleared directory debug"
}
else {
    mkdir ./debug
    Write-Host "[+] created directory debug"
}

$harnessBuilder = Import-Module -Name ./HarnessBuilder.psm1 -AsCustomObject -Scope Local
$scriptInspector = Import-Module -Name ./ScriptInspector.psm1 -AsCustomObject -Scope Local
$utils = Import-Module -Name ./Utils.psm1 -AsCustomObject -Scope Local

$script = (Get-Content $InFile -ErrorAction Stop | Out-String)

# record original encoded script, start building JSON for actions
"{`"Script`": " | Out-File $OutFile
$script.Trim() | ConvertTo-Json | Out-File -Append $OutFile
",`"Actions`": [" | Out-File -Append $OutFile

$layersFilePath = $utils.GetTmpFilePath()
$baseHarness = $harnessBuilder.Build($OutFile, $layersFilePath)

# DEBUG
$baseHarness | Out-File ./debug/harness.ps1

$script = $scriptInspector.EnvReplacement($script)
$script = $scriptInspector.SplitReplacement($script)
$script = $utils.SeparateLines($script)
$script = $scriptInspector.HandleNamespaces($script)

$harness = $baseHarness + "`r`n`r`n" + $script

# DEBUG
$script | Out-File ./debug/script.ps1

$harnessedScriptPath = $utils.GetTmpFilePath()
$harness | Out-File -FilePath $harnessedScriptPath

(timeout 5 pwsh -noni $harnessedScriptPath 2> "debug/error.txt")

OutputLayers $layersFilePath

# trim ending comma, add ending braces, prettify JSON, rewrite
(Get-Content -Raw $OutFile).Trim("`r`n,") + "]}" | ConvertFrom-Json | ConvertTo-Json -Depth 10 | 
    Out-File $OutFile

# clean up
Remove-Module HarnessBuilder
Remove-Module ScriptInspector
Remove-Module Utils