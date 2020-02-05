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

# arg validation
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

# import utility modules
$harnessBuilder = Import-Module -Name ./HarnessBuilder.psm1 -AsCustomObject -Scope Local
$scriptInspector = Import-Module -Name ./ScriptInspector.psm1 -AsCustomObject -Scope Local
$utils = Import-Module -Name ./Utils.psm1 -AsCustomObject -Scope Local

$script = (Get-Content $InFile -ErrorAction Stop | Out-String)

# record original encoded script, start building JSON for actions
"{`"Script`": " | Out-File $OutFile
$script.Trim() | ConvertTo-Json | Out-File -Append $OutFile
",`"Actions`": [" | Out-File -Append $OutFile

# build the base harness
$layersFilePath = $utils.GetTmpFilePath()
$baseHarness = $harnessBuilder.Build($OutFile, $layersFilePath)

# script modifications
$script = $scriptInspector.EnvReplacement($script)
$script = $scriptInspector.SplitReplacement($script)
$script = $utils.SeparateLines($script)
$script = $scriptInspector.HandleNamespaces($script)

$harnessedScript = $baseHarness + "`r`n`r`n" + $script
$harnessedScriptPath = $utils.GetTmpFilePath()
$harnessedScript | Out-File -FilePath $harnessedScriptPath

(timeout 5 pwsh -noni $harnessedScriptPath 2> "debug/error.txt")

# DEBUG
$script | Out-File ./debug/script.ps1
$baseHarness | Out-File ./debug/harness.ps1
OutputLayers $layersFilePath

# trim ending comma, add ending braces, prettify JSON, rewrite
(Get-Content -Raw $OutFile).Trim("`r`n,") + "]}" | ConvertFrom-Json | ConvertTo-Json -Depth 10 | 
    Out-File $OutFile

# clean up
Remove-Module HarnessBuilder
Remove-Module ScriptInspector
Remove-Module Utils