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

        -add in properties for overrided classes (ex. Headers property for webclient) 
        (see iranianshit.ps1)

        -Faking it...
        -framework for allowing functions to execute under certain circumstances
        -ex. Get-ChildItem all the time, Invoke-WebRequest in dangerous mode
        -Have webclient methods return dummy data to keep the script from erroring out?
        -danger level option...
            when there's a download being fed into an IEX, actually do the download because it's 
            another script

        -commenting, style (variable/funciton names), readme, other documentation?

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
    and process objects)

    -add some static deob for scrubbing explicit namespaces?
        - string deob could be really easy... just detect if it's being done (like a bunch of formatting)
          and run powershell on the string (see iranianshit.ps1)

    -catch commands run like schtasks.exe
        See if hook is available in powershell to do something every time an executable that is not 
        .Net executes List of aliases to override (pointing straight to linux binaries)

    -Find a way to preserve script action order when there are IEX. Right now the actions from that next
        layer are after the current layer, when in reality they are right in the middle

    -show enum name when it's an argument? 
        -ex. [BoxPSStatics]::GetFolderPath([System.Environment+SpecialFolder]::Desktop) gives
        argument value of 0

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
if (Test-Path ./dbgdecoder) {
    Remove-Item -Force ./dbgdecoder/*
    Write-Host "[+] cleared directory dbgdecoder"
}

$decoderBuilder = Import-Module -Name ./DecoderBuilder.psm1 -AsCustomObject -Scope Local
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
 
$baseDecoder = $decoderBuilder.Build($OutFile, $layersFilePath)

while ($layers.Count -gt 0) {
    
    $layer = $layers.Dequeue()
    $layer = $layerInspector.EnvReplacement($layer)
    $layer = $layerInspector.SplitReplacement($layer)
    $layer = $utils.SeparateLines($layer)
    $layer = $layerInspector.HandleNamespaces($layer)

    $decoder = $baseDecoder + "`r`n`r`n" + $layer
    $decoder | Out-File ./dbgdecoder/decoder$($layerCount).txt

    $tmpFile = $utils.GetTmpFilePath()
    $decoder | Out-File -FilePath $tmpFile

    if ($ErrorDir) {
        (timeout 5 pwsh -noni $tmpFile 2> "$ErrorDir/layer$($layerCount)error.txt")
    }
    else {
        (timeout 5 pwsh -noni $tmpFile 2> $null)
    }

    Remove-Item -Path $tmpFile

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

Remove-Module DecoderBuilder
Remove-Module LayerInspector
Remove-Module Utils