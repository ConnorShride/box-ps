<# known issues
    Overrides do not support wildcard arguments, so if the malicious powershell uses wildcards and the
    override goes ahead and executes the function because it's safe, it may error out (which is fine)
#>

param (
    [switch] $Docker,
    [parameter(ParameterSetName="ReportOnly", Mandatory=$true)]
    [switch] $ReportOnly,
    [parameter(Position=0, Mandatory=$true)]
    [String] $InFile,
    [String] $EnvVar,
    [String] $EnvFile,
    [parameter(ParameterSetName="ReportOnly", Mandatory=$true)]
    [parameter(ParameterSetName="IncludeArtifacts")]
    [parameter(Position=1)]
    [String] $OutFile,
    [parameter(ParameterSetName="IncludeArtifacts")]
    [string] $OutDir,
    [switch] $NoCleanUp
)

# arg validation
if (!(Test-Path $InFile)) {
    Write-Host "[-] input file does not exist. exiting."
    return
}

# can't give both options
if ($EnvVar -and $EnvFile) {
    Write-Host "[-] can't give both a string and a file for environment variable input"
    return
}

# give OutDir a default value if the user hasn't specified they don't want artifacts 
if (!$ReportOnly -and !$OutDir) {
    # by default named <script>.boxed in the current working directory
    $OutDir = "./$($InFile.Substring($InFile.LastIndexOf("/") + 1)).boxed"
}

class Report {

    [object[]] $Actions
    [object] $PotentialIndicators
    [object] $EnvironmentProbes
    [hashtable] $Artifacts

    Report([object[]] $actions, [string[]] $scrapedNetwork, [string[]] $scrapedPaths, 
            [string[]] $scrapedEnvProbes, [hashtable] $artifactMap) {
        $this.Actions = $actions
        $this.PotentialIndicators = $this.CombineScrapedIOCs($scrapedNetwork, $scrapedPaths)
        $this.EnvironmentProbes = $this.GenerateEnvProbeReport($scrapedEnvProbes)
        $this.Artifacts = $artifactMap
    }

    [hashtable] GenerateEnvProbeReport([string[]] $scrapedEnvProbes) {

        function AddListItem {
            param(
                [hashtable] $table,
                [string] $key1,
                [string] $key2,
                [object] $obj
            )

            if (!$table.ContainsKey($key1)) {
                $table[$key1] = @{}
            }
            if (!$table[$key1].ContainsKey($key2)) {
                $table[$key1][$key2] = @()
            }
            $table[$key1][$key2] += $obj
        }

        $envReport = @{}
        $operatorMap = @{
            "NULL" = "unknown";
            "eq" = "equals";
            "ne" = "not equals"
        }

        $probesSet = New-Object System.Collections.Generic.HashSet[string]

        # first wrangle all the environment_probe actions we caught and split them by their goal
        $this.Actions | ForEach-Object {

            if ($_.Behaviors.Contains("environment_probe")) {
                if ($_.ExtraInfo -eq "language_probe") {
                    AddListItem $envReport "Language" "Actors" $_.Actor
                }
                elseif ($_.ExtraInfo -eq "host_probe") {
                    AddListItem $envReport "Host" "Actors" $_.Actor
                }
                elseif ($_.ExtraInfo -eq "date_probe") {
                    AddListItem $envReport "Date" "Actors" $_.Actor
                }
            }
        }

        # ingest the scraped environment probes and dedupe
        foreach ($probe in $scrapedEnvProbes) {
            $probesSet.Add($probe)
        }

        # split the probes out by goal and map to user-friendly representation of operator observed
        foreach ($probeStr in $probesSet) {
            $split = $probeStr.Split(",")
            $probe = @{
                "Value" = $split[1];
                "Operator" = $operatorMap[$split[2]]
            }
            if ($split[0] -eq "language") {
                AddListItem $envReport "Language" "Checks" $probe
            }
            elseif ($split[0] -eq "host") {
                AddListItem $envReport "Host" "Checks" $probe
            }
            elseif ($split[0] -eq "date") {
                AddListItem $envReport "Date" "Checks" $probe
            }
        }

        return $envReport
    }

    [hashtable] CombineScrapedIOCs([string[]] $scrapedNetwork, [string[]] $scrapedPaths) {

        $pathsSet = New-Object System.Collections.Generic.HashSet[string]
        $networkSet = New-Object System.Collections.Generic.HashSet[string]

        # gather all file paths from actions
        $this.Actions | Where-Object -Property Behaviors -contains "file_system" | ForEach-Object {
            $($_.BehaviorProps.paths | ForEach-Object { $pathsSet.Add($_) > $null })
        }

        # gather all network urls from actions 
        $this.Actions | Where-Object -Property Behaviors -contains "network" | ForEach-Object {
            $($_.BehaviorProps.uri | ForEach-Object { $networkSet.Add($_) > $null })
        }

        # add scraped paths and urls
        if ($scrapedNetwork) {
            $scrapedNetwork | ForEach-Object { $networkSet.Add($_) > $null }
        }
        if ($scrapedPaths) {
            $scrapedPaths | ForEach-Object { $pathsSet.Add($_) > $null }
        }

        $paths = [string[]]::new($pathsSet.Count)
        $network = [string[]]::new($networkSet.Count)
        $networkSet.CopyTo($network)
        $pathsSet.CopyTo($paths)

        $result = @{
            "network" = $network;
            "file_system" = $paths
        }

        return $result
    }
}

# cuts the full path from the file path to leave just the name
function GetShortFileName {
    param(
        [string] $Path
    )

    if ($Path.Contains("/")) {
        $shortName = $Path.Substring($Path.LastIndexOf("/")+1)
    }
    else {
        $shortName = $Path
    }

    return $shortName
}


# removes, if present, the invocation to Powershell that comes up front. It may be written to
# be interpreted with a cmd.exe shell, having cmd.exe obfuscation, and therefore does not play well 
# with our PowerShell interpreted powershell.exe override. Also records the initial action as a 
# script execution of the code we come up with here (decoded if it was b64 encoded).
function GetInitialScript {

    param(
        [string] $OrigScript
    )

    # make sure it starts with "powershell" so we don't waste time (the rest is not efficient)
    if (!($OrigScript -match "^[Pp][Oo][Ww][Ee][Rr][Ss][Hh][Ee][Ll][Ll].*$")) {
        return $OrigScript
    }

    # if the invocation uses an encoded command, we need to decode that
    # is encoded if there's an "-e" or "-en" and there's a base64 string in the invocation
    if ($OrigScript -match ".*\-[Ee][Nn]?[^qQnXx].*") { # excludes instances of "-eq" and "-ex"

        $match = [Regex]::Match($OrigScript, ".*?([A-Za-z0-9+/=]{40,}).*").captures
        if ($match -ne $null) {
            $encoded = $match.groups[1]
            $is_encoded = $true
        }
    }

    $scrubbed = $OrigScript -replace "^[Pp][Oo][Ww][Ee][Rr][Ss][Hh][Ee][Ll][Ll](.exe)?\s+((-[\w``]+\s+([\w\d``]+ )?)?)*"

    if ($is_encoded) {
        $decoded = [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String($encoded))
    }
    else {
        $decoded = $scrubbed
    }

    # record the script
    [hashtable] $action = @{
        "Behaviors" = @("script_exec")
        "Actor" = "powershell.exe"
        "BehaviorProps" = @{
            "script" = @($decoded)
        }
        "Id" = 0
    }

    $json = $action | ConvertTo-Json -Depth 10
    ($json + ",") | Out-File -Append "$WORK_DIR/actions.json"

    return $decoded
}

# For some reason, some piece of the powershell codebase behind the scenes is calling my Test-Path
# override and that invocation is showing up in the actions. Haven't been able to track it down.
function StripBugActions {

    param(
        [object[]] $Actions
    )

    $actions = $Actions | ForEach-Object {
        if ($_.Actor -eq "Microsoft.PowerShell.Management\Test-Path") {
            if ($_.BehaviorProps.paths -ne @("env:__SuppressAnsiEscapeSequences")) {
                $_
            }
        }
        else {
            $_
        }
    }

    return $actions
}

# runs through the actions writing artifacts we may care about to disk and returns a map of which
# actions by ID produced which artifact hash
function HarvestArtifacts {

    param(
        [object[]] $Actions
    )

    # map actors we want to harvest artifacts for to the bytes behavior property
    $overrides = @{
        "[System.Reflection.Assembly]::Load" = "code";
        "[System.Runtime.InteropServices.Marshal]::Copy" = "bytes"
    }

    $artifactMap = @{}

    New-Item -Path $WORK_DIR/artifacts -ItemType "directory" > /dev/null
    $outDir = $WORK_DIR + "/artifacts/"

    $Actions | ForEach-Object {

        if ($overrides.Keys -contains $_.Actor) {
        
            $bytes = $_.BehaviorProps.($overrides[$_.Actor])
            $actionId = ($_.Id | Out-String).Trim()
            $fileType = "unknown"

            # basic check to see if this may be interesting
            if ($bytes.Length -gt 10) {
                
                # write bytes and compute sha256
                $outPath = $outDir + "tmp.bin"
                [System.IO.File]::WriteAllBytes($outPath, $bytes)
                $sha256 = $(Get-FileHash -Path $outPath -Algorithm SHA256).Hash
                Move-Item -Path $outPath -Destination ($outDir + $sha256)

                # check if the bytes indicate a PE file
                if ($bytes[0] -eq 77 -and $bytes[1] -eq 90) {
                    $fileType = "PE"
                }

                $artifactMap[$actionId] = @{
                    "sha256" = $sha256;
                    "fileType" = $fileType
                }
            }
        }
    }

    return $artifactMap
}

# remove imported modules and clean up non-output file system artifacts
function CleanUp {

    Remove-Module HarnessBuilder -ErrorAction SilentlyContinue
    Remove-Module ScriptInspector -ErrorAction SilentlyContinue
    Remove-Module Utils -ErrorAction SilentlyContinue
    Remove-Item -Recurse $WORK_DIR
}

$WORK_DIR = "./working"

# don't run it here, pull down the box-ps docker container and run it in there
if ($Docker) {

    # test to see if docker is installed. EXIT IF NOT
    try {
        $output = docker ps 2>&1
    }
    catch [System.Management.Automation.CommandNotFoundException] {
        Write-Host "[-] docker is not installed. install it and add your user to the docker group"
        Exit(-1)
    }

    # some other error with docker. EXIT
    if ($output -and $output.GetType().Name -eq "ErrorRecord") {
        $msg = $output.Exception.Message
        if ($msg.Contains("Got permission denied")) {
            Write-Host "[-] permissions incorrect. add your user to the docker group"
            Exit(-1)
        }
        Write-Host "[-] there's a problem with your docker environment..."
        Write-Host $msg
    }

    # validate that the input environment variable file exists if given
    if ($EnvFile) {

        if (!(Test-Path $EnvFile)) {
            Write-Host "[-] input environment variable file doesn't exist. exiting."
            return
        }
    }

    Write-Host "[+] pulling latest docker image"
    docker pull connorshride/box-ps:latest > $null
    Write-Host "[+] starting docker container"
    docker run -td --network none connorshride/box-ps:latest > $null

    # get the ID of the container we just started
    $psOutput = docker ps -f status=running -f ancestor=connorshride/box-ps -l
    $idMatch = $psOutput | Select-String -Pattern "[\w]+_[\w]+"
    $containerId = $idMatch.Matches.Value

    # modify args for running in the container
    # just keep all the input/output files in the box-ps dir in the container
    $PSBoundParameters.Remove("Docker") > $null
    $PSBoundParameters["InFile"] = GetShortFileName $InFile
    docker cp $InFile "$containerId`:/opt/box-ps/"

    if ($OutFile) {
        $PSBoundParameters["OutFile"] = "./out.json"
    }

    if ($OutDir) {
        $PSBoundParameters["OutDir"] = "./outdir"
    }

    if ($EnvFile) {
        $PSBoundParameters["EnvFile"] = "./input_env.json"
        docker cp $EnvFile "$containerId`:/opt/box-ps/input_env.json"
    }

    Write-Host "[+] running box-ps in container"
    docker exec $containerId pwsh /opt/box-ps/box-ps.ps1 @PSBoundParameters

    if ($OutFile) {
        docker cp "$containerId`:/opt/box-ps/out.json" $OutFile
    }

    if ($OutDir) {

        if (Test-Path $OutDir) {
            Remove-Item -Recurse $OutDir
        }

        # attempt to copy the output dir in the container back out to the host
        $output = docker cp "$containerId`:/opt/box-ps/outdir" $OutDir 2>&1
        $output = $output | Out-String
        if ($output.Contains("Error") -and $output.Contains("No such container:path")) {
            Write-Host "[-] no output directory produced in container"
        }
    }

    # clean up
    docker kill $containerId > $null
}
# sandbox outside of container
else {

    $stderrPath = "$WORK_DIR/stderr.txt"
    $stdoutPath = "$WORK_DIR/stdout.txt"
    $actionsPath = "$WORK_DIR/actions.json"
    $harnessedScriptPath = "$WORK_DIR/harnessed_script.ps1"

    # create working directory to store
    if (Test-Path $WORK_DIR) {
        Remove-Item -Force $WORK_DIR/*
    }
    else {
        New-Item $WORK_DIR -ItemType Directory > $null
    }

    "1" | Out-File $WORK_DIR/action_id.txt

    Import-Module -Name $PSScriptRoot/HarnessBuilder.psm1
    Import-Module -Name $PSScriptRoot/ScriptInspector.psm1

    Write-Host -NoNewLine "[+] reading script..."
    $script = (Get-Content $InFile -ErrorAction Stop | Out-String)
    $script = GetInitialScript $script
    Write-Host " done"

    # write out string environment variable to JSON for harness builder
    if ($EnvVar) {

        # validate that it's in the right form <var_name>=<var_value>
        if (!$EnvVar.Contains("=")) {
            Write-Host "[-] no equals sign in environment variable string"
            Write-Host "[-] USAGE <var_name>=<value>"
            return
        }

        $name = $EnvVar[0..($EnvVar.IndexOf("="))] -join ''
        $value = $EnvVar[($EnvVar.IndexOf("=")+1)..($EnvVar.Length-1)] -join ''
        $varObj = @{
            $name = $value
        }
        $varObj | ConvertTo-Json | Out-File $WORK_DIR/input_env.json
    }
    # copy the given json file where the harness builder expects it
    elseif ($EnvFile) {

        # validate the file exists
        if (!(Test-Path $EnvFile)) {
            Write-Host "[-] input environment variable file doesn't exist. exiting."
            return
        }
        else {

            # validate it's in valid JSON
            $envFileContent = Get-Content $EnvFile -Raw
            try {
                $envFileContent | ConvertFrom-Json | Out-Null
            }
            catch {
                Write-Host "[-] input environment variable file is not formatted in valid JSON. exiting"
                return
            }

            $envFileContent | Out-File $WORK_DIR/input_env.json
        }
    }

    Write-Host -NoNewLine "[+] building script harness..."

    # build harness and integrate script with it
    $harness = (BuildHarness).Replace("<CODE_DIR>", $PSScriptRoot)
    $script = PreProcessScript $script

    # attach the harness to the script
    $harnessedScript = $harness + "`r`n`r`n" + $script
    $harnessedScript | Out-File -FilePath $harnessedScriptPath

    Write-Host " done"
    Write-Host -NoNewLine "[+] sandboxing harnessed script..."

    # run it
    (timeout 5 pwsh -noni $harnessedScriptPath 2> $stderrPath 1> $stdoutPath)

    Write-Host " done"

    # a lot of times actions.json will not be present if things go wrong
    if (!(Test-Path $actionsPath)) {
        $message = "sandboxing failed with an internal error. please post an issue on GitHub with the failing powershell"
        Write-Error -Message $message -Category NotSpecified
        if (!$NoCleanUp) {
            CleanUp
        }
        Exit(-1)
    }

    Write-Host -NoNewLine "[+] post-processing results..."

    # ingest the actions, potential IOCs, create report
    $actionsJson = Get-Content -Raw $actionsPath
    $actions = "[" + $actionsJson.TrimEnd(",`r`n") + "]" | ConvertFrom-Json

    $actions = $(StripBugActions $actions)
    
    # go gather the IOCs we may have scraped
    $scrapedNetwork = Get-Content $WORK_DIR/scraped_network.txt -ErrorAction SilentlyContinue
    $scrapedPaths = Get-Content $WORK_DIR/scraped_paths.txt -ErrorAction SilentlyContinue
    $scrapedEnvProbes = Get-Content $WORK_DIR/scraped_probes.txt -ErrorAction SilentlyContinue

    # wrangle and gather some file metadata on any artifacts of the script
    $artifactMap = HarvestArtifacts $actions

    # create the report and convert to JSON
    $report = [Report]::new($actions, $scrapedNetwork, $scrapedPaths, $scrapedEnvProbes, $artifactMap)
    $reportJson = $report | ConvertTo-Json -Depth 10

    Write-Host " done"

    # output the JSON report where the user wants it
    if ($OutFile) {
        $reportJson | Out-File $OutFile
        Write-Host "[+] wrote report to file $OutFile"
    }

    # user wants more detailed artifacts as well as the report
    if ($OutDir) {

        # overwrite output dir if it already exists
        if (Test-Path $OutDir) {
            Remove-Item -Recurse $OutDir/*
        }
        else {
            New-Item $OutDir -ItemType Directory > $null
        }

        # move some stuff from working directory here
        Move-Item $WORK_DIR/stdout.txt $OutDir/
        Move-Item $WORK_DIR/stderr.txt $OutDir/
        Move-Item $WORK_DIR/layers.ps1 $OutDir/
        if ($(Get-ChildItem $WORK_DIR/artifacts).Length -gt 0) {
            Move-Item $WORK_DIR/artifacts $OutDir
        }
        $reportJson | Out-File $OutDir/report.json

        Write-Host "[+] wrote analysis results to output directory $OutDir"
    }

    if (!$NoCleanUp) {
        CleanUp
    }
}