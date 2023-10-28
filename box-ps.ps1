<# known issues
    Overrides do not support wildcard arguments, so if the malicious powershell uses wildcards and the
    override goes ahead and executes the function because it's safe, it may error out (which is fine)
#>

[CmdletBinding(DefaultParameterSetName='IncludeArtifacts')]
param (
    [switch] $Docker,
    [parameter(ParameterSetName="ReportOnly", Mandatory=$true)]
    [switch] $ReportOnly,
    [parameter(Position=0)]
    [String] $InFile,
    [parameter(ValueFromPipeline=$true)]
    [String] $ScriptContent,
    [String] $EnvVar,
    [String] $EnvFile,
    [parameter(ParameterSetName="ReportOnly", Mandatory=$true)]
    [parameter(ParameterSetName="IncludeArtifacts")]
    [parameter(Position=1)]
    [String] $OutFile,
    [parameter(ParameterSetName="IncludeArtifacts")]
    [string] $OutDir,
    [switch] $NoCleanUp,
    [string] $Timeout
)

# can't give both InFile and script content
if ($ScriptContent -and $InFile) {
    [Console]::Error.WriteLine("[-] can't give both an input file and script contents")
    exit 1
}

# must give either script content or InFile
if (!$ScriptContent -and !$InFile) {
    [Console]::Error.WriteLine("[-] must give either script contents or input file")
    exit 1
}

# input file must exist if given
if ($InFile -and !(Test-Path $InFile)) {
    [Console]::Error.WriteLine("[-] input file does not exist")
    exit 3
}

# input file must be a file
if ($InFile -and (Get-Item $InFile) -is [System.IO.DirectoryInfo]) {
    [Console]::Error.WriteLine("[-] input file cannot be a directory")
    exit 3
}

# can't give both options
if ($EnvVar -and $EnvFile) {
    [Console]::Error.WriteLine("[-] can't give both a string and a file for environment variable input")
    exit 1
}

# give OutDir a default value if the user hasn't specified they don't want artifacts
if (!$ReportOnly -and !$OutDir) {

    if ($ScriptContent) {
        $OutDir = "./script.boxed"
    }
    else {
        # by default named <script>.boxed in the current working directory
        $OutDir = "./$($InFile.Substring($InFile.LastIndexOf("/") + 1)).boxed"
    }
}

$utils = Import-Module -Name $PSScriptRoot/Utils.psm1 -AsCustomObject -Scope Local

class Report {

    [object[]] $Actions
    [object] $PotentialIndicators
    [object] $EnvironmentProbes
    [hashtable] $Artifacts
    [string[]] $PotentialArtifacts
    [string] $WorkingDir

    Report([object[]] $actions, [string[]] $scrapedNetwork, [string[]] $scrapedPaths,
           [string[]] $scrapedEnvProbes, [hashtable] $artifactMap, [string[]] $potentialArtifacts,
           [string] $workingDir) {

        if ($null -eq $actions) {
            $this.Actions = @()
        }
        else {
            $this.Actions = $actions
        }

        $this.PotentialIndicators = $this.CombineScrapedIOCs($scrapedNetwork, $scrapedPaths)
        $this.EnvironmentProbes = $this.GenerateEnvProbeReport($scrapedEnvProbes)
        $this.Artifacts = $artifactMap
        $this.PotentialArtifacts = $potentialArtifacts
        $this.WorkingDir = $workingDir
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
                if ($_.SubBehaviors.Contains("probe_language")) {
                    AddListItem $envReport "Language" "Actors" $_.Actor
                }
                elseif ($_.SubBehaviors.Contains("probe_host")) {
                    AddListItem $envReport "Host" "Actors" $_.Actor
                }
                elseif ($_.SubBehaviors.Contains("probe_date")) {
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

# Isolates the script being executed in a powershell invocation. It may be written to be interpreted
# with a cmd.exe shell and therefore does not play well with our PowerShell-interpreted
# powershell.exe override (unquoted for the -Command flag or even cmd.exe obfuscation). Records the
# initial action as a script execution of the code we come up with here (decoded if it was b64
# encoded).
function HandleCmdInvocation {

    param(
        [string] $OrigScript
    )

    $OrigScript = $OrigScript.Trim()

    # matches if the powershell.exe call is right up front and it's all on a single line
    $cmdInvokePat = "^\s*[Pp][Oo][Ww][Ee][Rr][Ss][Hh][Ee][Ll][Ll](\.exe)?\s+.+$"
    if (!($OrigScript | Select-String -Pattern $cmdInvokePat)) {
        return $OrigScript
    }

    $invokedScript = $null

    # if the invocation uses an encoded command, we need to decode that
    # is encoded if there's an "-e" or "-en" and there's a base64 string in the invocation, but not
    # one of the other flags that also start with EN
    if ($OrigScript -match ".*\-[Ee][Nn]?[^qQnXxPp].*") {

        $match = [Regex]::Match($OrigScript, ".*?([A-Za-z0-9+/=]{40,}).*").captures
        if ($match -ne $null) {
            $invokedScript = [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String($match.groups[1]))
        }
    }
    else {

        # see if the script was given with the -Command option explicitely. (Must be the last argument)
        $match = ($OrigScript | Select-String -Pattern "^\s*[Pp][Oo][Ww][Ee][Rr][Ss][Hh][Ee][Ll][Ll](?:\.exe)?\s+.*?-[Cc][Oo]?[Mm]?[Mm]?[Aa]?[Nn]?[Dd]?\s+(.+)$")
        if ($match) {
            $invokedScript = $match.Matches[0].Groups[1].Value
        }
        # the command used the -Command option implicitely. Scrub anything that looks like an argument
        # flag to leave only the command
        else {
            $invokedScript = $OrigScript -replace "^\s*[Pp][Oo][Ww][Ee][Rr][Ss][Hh][Ee][Ll][Ll](\.exe)?\s+((-[\w``]+\s+([\w\d``]+ )?)?)*"
        }

        # trim whitespace and unwrap any quotes around the command
        $invokedScript = $invokedScript.Trim()
        if (($invokedScript.StartsWith("`"") -and $invokedScript.EndsWith("`"")) -or
            ($invokedScript.StartsWith("'") -and $invokedScript.EndsWith("'"))) {
            $invokedScript = $invokedScript.SubString(1,$invokedScript.Length-2)
        }

        # remove wrapping curly braces just in case this script was meant to be executed under
        # PowerShell and is interpreting a scriptblock
        if ($invokedScript.StartsWith("{") -and $invokedScript.EndsWith("}")) {
            $invokedScript = $invokedScript.SubString(1,$invokedScript.Length-2)
        }
    }

    # TODO import administrative or something so we don't have duplicate code here it bites me every time
    # TODO parse out flags used to put them in arguments
    [hashtable] $action = @{
        "Behaviors" = @("script_exec")
        "SubBehaviors" = @("start_process")
        "Actor" = "powershell.exe"
        "Line" = ""
        "ExtraInfo" = ""
        "BehaviorProps" = @{
            "script" = $invokedScript
        }
        "Parameters" = @{}
        "Id" = 0
    }

    $hashed = "powershell.exe$invokedScript"

    $stringStream = [System.IO.MemoryStream]::new()
    $streamWriter = [System.IO.StreamWriter]::new($stringStream)
    $streamWriter.write($hashed)
    $streamWriter.Flush()
    $stringStream.Position = 0

    $action["BehaviorId"] = (Get-FileHash -InputStream $stringStream -Algorithm SHA256).Hash

    $json = $action | ConvertTo-Json -Depth 10
    ($json + ",") | Out-File -Append "$WORK_DIR/actions.json"

    return $invokedScript
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

    $behaviorMap = @{
        "write_to_memory" = "bytes";
        "file_write" = "content";
        "binary_import" = "bytes";
    }

    $supportedBehaviors = $behaviorMap.Keys

    $artifactMap = @{}

    New-Item -Path $WORK_DIR/artifacts -ItemType "directory" > /dev/null 2>&1
    $outDir = $WORK_DIR + "/artifacts/"

    # go through actions looking for behaviors that would give artifacts
    foreach ($action in $Actions) {

        $actionBehaviors = $action.Behaviors + $action.SubBehaviors
        $behaviors = $utils.ListIntersection($supportedBehaviors, $actionBehaviors)

        # go through behavior properties for those behaviors
        foreach ($behavior in $behaviors) {

            $artifactProperty = $behaviorMap[$behavior]

            $artifactContent = $action.BehaviorProps."$artifactProperty"

            if ($null -eq $artifactContent) {
                continue
            }

            $artifactIsArray = $artifactContent.GetType().BaseType.Name -eq "Array"
            $actionId = ($action.Id | Out-String).Trim()
            $fileType = "unknown"

            # basic check to see if this may be interesting
            if ($artifactContent.Length -gt 10) {

                # write content and compute sha256
                $outPath = $outDir + "tmp.bin"

                try {
                    # array content means bytes, assuming we'll never have an array of chars
                    if ($artifactIsArray) {
                        [System.IO.File]::WriteAllBytes($outPath, $artifactContent)
                    }
                    # content is just text
                    else {
                        $artifactContent | Out-File $outPath
                    }
                }
                catch {
                    [Console]::Error.WriteLine("[-] error writing artifact to disk from action ID $actionId : $($_.Exception)")
                    continue
                }

                # compute sha256 hash, move to artifact directory
                $sha256 = $(Get-FileHash -Path $outPath -Algorithm SHA256).Hash
                Move-Item -Path $outPath -Destination ($outDir + $sha256) -Force

                # check if the bytes indicate a PE file
                if ($artifactIsArray -and $artifactContent[0] -eq 77 -and $artifactContent[1] -eq 90) {
                    $fileType = "PE"
                }

                if (!$artifactMap.Contains($actionId)) {
                    $artifactMap[$actionId] = @()
                }

                $artifactMap[$actionId] += @{
                    "sha256" = $sha256;
                    "fileType" = $fileType
                }
            }
        }
    }

    return $artifactMap
}

# clean up working directory if desired, remove imported modules, and exit with a code
function CleanExit {

    param(
        [bool] $NoCleanUp,
        [int] $ExitCode,
        [string] $WorkDir
    )

    if (!$NoCleanUp) {
        Remove-Item -Recurse $WorkDir -ErrorAction SilentlyContinue
    }

    Remove-Module HarnessBuilder -ErrorAction SilentlyContinue
    Remove-Module ScriptInspector -ErrorAction SilentlyContinue
    Remove-Module Utils -ErrorAction SilentlyContinue

    exit $ExitCode
}

# Use the current PID to give each box-ps run a unique working directory.
# This allows multiple box-ps instances to analyze samples in the same directory.
$WORK_DIR = "./working_" + $PID

# pull down the box-ps docker container and run it in there
if ($Docker) {

    # test to see if docker is installed. EXIT IF NOT
    try {
        $output = docker ps 2>&1
    }
    catch [System.Management.Automation.CommandNotFoundException] {
        [Console]::Error.WriteLine("[-] docker is not installed. install it and add your user to the docker group")
        exit 2
    }

    # some other error with docker. EXIT
    if ($output -and $output.GetType().Name -eq "ErrorRecord") {
        $msg = $output.Exception.Message
        if ($msg.Contains("Got permission denied")) {
            [Console]::Error.WriteLine("[-] permissions incorrect. add your user to the docker group")
        }
        [Console]::Error.WriteLine("[-] there's a problem with your docker environment...")
        [Console]::Error.WriteLine($msg)
        exit 2
    }

    # validate that the input environment variable file exists if given
    if ($EnvFile -and !(Test-Path $EnvFile)) {
        [Console]::Error.WriteLine("[-] input environment variable file doesn't exist. exiting.")
        exit 3
    }

    Write-Host "[+] pulling latest docker image"
    docker pull connorshride/box-ps:latest > $null
    #docker pull connorshride/box-ps:develop > $null
    Write-Host "[+] starting docker container"
    docker run -td --network none connorshride/box-ps:latest > $null
    #docker run -td --network none connorshride/box-ps:develop > $null

    # get the ID of the container we just started
    $psOutput = docker ps -f status=running -f ancestor=connorshride/box-ps -l
    #$psOutput=$(docker ps -f status=running -f ancestor=connorshride/box-ps:develop -l)

    $idMatch = $psOutput | Select-String -Pattern "[\w]+_[\w]+"
    $containerId = $idMatch.Matches.Value

    # modify args to those that the container should receive

    $PSBoundParameters.Remove("Docker") > $null

    # copy the input file into the container
    $PSBoundParameters["InFile"] = "./infile.ps1"
    if ($InFile) {
        docker cp $InFile "$containerId`:/opt/box-ps/infile.ps1"
    }
    # given script contents instead
    else {

        # pipe the script contents into a file in the container
        $ScriptContent | docker exec -i $containerId /bin/bash -c "cat - > /opt/box-ps/infile.ps1"
        $PSBoundParameters.Remove("ScriptContent") > $null
    }

    # TODO same error handling as below so we pass through return codes

    # just keep all the input/output files in the box-ps dir in the container
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
            [Console]::Error.WriteLine("[-] no output directory produced in container")
        }
    }

    # clean up
    docker kill $containerId > $null
}
# do sandboxing
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

    # init working directory files
    "1" | Out-File $WORK_DIR/action_id.txt
    New-Item $WORK_DIR/actions.json > $null

    Import-Module -Name $PSScriptRoot/HarnessBuilder.psm1
    Import-Module -Name $PSScriptRoot/ScriptInspector.psm1

    # read script content from the input file
    if ($InFile) {
        Write-Host -NoNewLine "[+] reading script..."
        $ScriptContent = (Get-Content $InFile -ErrorAction Stop | Out-String)
        $ScriptContent = HandleCmdInvocation $ScriptContent
        Write-Host " done"
    }

    # write out string environment variable to JSON for harness builder
    if ($EnvVar) {

        # validate that it's in the right form <var_name>=<var_value>
        if (!$EnvVar.Contains("=")) {
            [Console]::Error.WriteLine("[-] no equals sign in environment variable string")
            [Console]::Error.WriteLine("[-] USAGE <var_name>=<value>")
            CleanExit -NoCleanUp $NoCleanUp -WorkDir $WORK_DIR -ExitCode 1
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
            [Console]::Error.WriteLine("[-] input environment variable file doesn't exist. exiting.")
            CleanExit -NoCleanUp $NoCleanUp -WorkDir $WORK_DIR -ExitCode 3
        }
        else {

            # validate it's in valid JSON
            $envFileContent = Get-Content $EnvFile -Raw
            try {
                $envFileContent | ConvertFrom-Json | Out-Null
            }
            catch {
                [Console]::Error.WriteLine("[-] input environment variable file is not formatted in valid JSON. exiting")
                CleanExit -NoCleanUp $NoCleanUp -WorkDir $WORK_DIR -ExitCode 1
            }

            $envFileContent | Out-File $WORK_DIR/input_env.json
        }
    }

    Write-Host -NoNewLine "[+] building script harness..."

    # build harness and integrate script with it
    $harness = (BuildHarness).Replace("<CODE_DIR>", $PSScriptRoot).Replace("<PID>", $PID)
    $ScriptContent = PreProcessScript $ScriptContent $PID

    # attach the harness to the script
    $harnessedScript = $harness + "`r`n`r`n" + $ScriptContent
    $harnessedScript | Out-File -FilePath $harnessedScriptPath

    Write-Host " done"
    Write-Host -NoNewLine "[+] sandboxing harnessed script..."

    # run it in another shell
    if ($Timeout) {
        (timeout --foreground $Timeout pwsh -noni $harnessedScriptPath 2> $stderrPath 1> $stdoutPath)
    }
    else {
        pwsh -noni $harnessedScriptPath 2> $stderrPath 1> $stdoutPath
    }

    Write-Host " done"

    # check for some indicators of sandboxing failure
    $stderr = Get-Content -Raw $stderrPath
    $fail = $false
    $errorReason = ""
    $errorCode = 4

    # detect some critical errors from the stderr of the sandbox process

    # check for timeout
    if ($LASTEXITCODE -eq 124) {
        $fail = $true
        $errorReason = "sandboxing timed out"
        $errorCode = 124
    }

    # indicates a script with invalid syntax
    if ($null -ne $stderr -and $stderr.Contains("ParserError: ")) {
        $fail = $true
        $errorReason = "invalid script syntax"
        $errorCode = 6
    }

    # print error and exit
    if ($fail) {
        [Console]::Error.WriteLine("[-] sandboxing failed: $errorReason...")
        [Console]::Error.WriteLine($stderr)
        CleanExit -NoCleanUp $NoCleanUp -WorkDir $WORK_DIR -ExitCode $errorCode
    }

    Write-Host -NoNewLine "[+] post-processing results..."

    # ingest the recorded actions
    $actionsJson = Get-Content -Raw $actionsPath
    if ($null -eq $actionsJson) {
        $actionsJson = ""
    }

    $actions = "[" + $actionsJson.TrimEnd(",`r`n") + "]" | ConvertFrom-Json
    if ($null -eq $actions) {
        $actions = @()
    }
    $actions = $(StripBugActions $actions)

    # go gather the IOCs we may have scraped
    $scrapedNetwork = Get-Content $WORK_DIR/scraped_network.txt -ErrorAction SilentlyContinue
    $scrapedPaths = Get-Content $WORK_DIR/scraped_paths.txt -ErrorAction SilentlyContinue
    $scrapedEnvProbes = Get-Content $WORK_DIR/scraped_probes.txt -ErrorAction SilentlyContinue

    # write out artifacts of the script from actions data
    $artifactMap = HarvestArtifacts $actions

    # record the PEs found from variables content
    if (Test-Path $WORK_DIR/in_mem_pes.txt) {
        $potentialArtifacts = [string[]](Get-Content $WORK_DIR/in_mem_pes.txt)
    }
    else {
        $potentialArtifacts = @()
    }

    # create the report and convert to JSON
    $report = [Report]::new($actions, $scrapedNetwork, $scrapedPaths,
        $scrapedEnvProbes, $artifactMap, $potentialArtifacts, $WORK_DIR)
    $reportJson = $report | ConvertTo-Json -Depth 10

    Write-Host " done"

    # output the JSON report where the user wants it
    if ($OutFile) {
        $reportJson | Out-File $OutFile
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

        if ($(Test-Path $WORK_DIR/artifacts) -and $(Get-ChildItem $WORK_DIR/artifacts).Length -gt 0) {
            Move-Item $WORK_DIR/artifacts $OutDir
        }

        $reportJson | Out-File $OutDir/report.json
    }

    CleanExit -NoCleanUp $NoCleanUp -WorkDir $WORK_DIR -ExitCode 0
}
