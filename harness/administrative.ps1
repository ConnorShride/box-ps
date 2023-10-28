# using namespaces to find the necessary types of the parameters generated for the overrides
using namespace System.Management.Automation
using namespace System.Management.Automation.Runspaces
using namespace System.IO
using namespace System.Text
using namespace Microsoft.PowerShell.Commands
using namespace System.Diagnostics
using namespace System.Collections
using namespace Microsoft.PowerShell
using namespace NewtonSoft.Json
using namespace System

$WORK_DIR = "./working_<PID>"
$CODE_DIR = "<CODE_DIR>"
$BOXPS_CONFIG = Microsoft.PowerShell.Management\Get-Content "$CODE_DIR/config.json" | ConvertFrom-Json -AsHashtable

class Action <# lawsuit... I'll be here all week #> {

    [String[]] $Behaviors
    [String[]] $SubBehaviors
    [String] $Actor
    [String] $Line
    [hashtable] $BehaviorProps
    [hashtable] $Parameters
    [string] $ExtraInfo
    [int] $Id
    [string] $BehaviorId

    Action ([String[]] $Behaviors, [String[]] $SubBehaviors, [String] $Actor,
        [hashtable] $BehaviorProps, [InvocationInfo] $Invocation, [string] $ExtraInfo) {

        $this.Behaviors = $Behaviors
        $this.SubBehaviors = $SubBehaviors
        $this.Actor = $Actor
        $this.BehaviorProps = $BehaviorProps
        $this.Line = $Invocation.Line.Trim()
        $this.ExtraInfo = $ExtraInfo
        $this.Id = 0
        $this.BehaviorId = $this.GetBehaviorId()


        $paramsSplit = $this.SplitParams($Invocation)
        $this.Parameters = $paramsSplit["bound"]

        if ($paramsSplit["switches"]) {
            $this.Parameters["Switches"] = $paramsSplit["switches"]
        }
    }

    # for class members
    # e.g. System.Net.WebClient.DownloadFile
    #   These are guaranteed not to have switches, and the MyInvocation variable does not
    #   contain boundparameters, so callers need to be able to pass the PSBoundParameters variable
    Action ([String[]] $Behaviors, [String[]] $SubBehaviors, [String] $Actor,
        [hashtable] $BehaviorProps, [hashtable] $BoundParams, [String] $Line, [String] $ExtraInfo) {

        $this.Behaviors = $Behaviors
        $this.SubBehaviors = $SubBehaviors
        $this.Actor = $Actor
        $this.BehaviorProps = $BehaviorProps
        $this.Parameters = $BoundParams
        $this.Line = $Line.Trim()
        $this.ExtraInfo = $ExtraInfo
        $this.Id = 0
        $this.BehaviorId = $this.GetBehaviorId()
    }

    [string] GetBehaviorId() {

        $hashed = $this.Actor
        foreach ($behaviorProp in $this.BehaviorProps.Keys) {
            $hashed += $this.BehaviorProps[$behaviorProp] | Out-String
        }

        $stringStream = [System.IO.MemoryStream]::new()
        $streamWriter = [System.IO.StreamWriter]::new($stringStream)
        $streamWriter.write($hashed)
        $streamWriter.Flush()
        $stringStream.Position = 0

        return (Get-FileHash -InputStream $stringStream -Algorithm SHA256).Hash
    }

    # linear walk through all parameters rebuilding bound params and switches
    [hashtable] SplitParams([InvocationInfo] $Invocation) {

        $allParams = $Invocation.MyCommand.Parameters

        $bound = @{}
        $localSwitches = @() # not allowed to name this $switches (thanks for the help, pwsh)

        foreach ($paramName in $allParams.Keys) {

            if ($allParams[$paramName].SwitchParameter -and $Invocation.BoundParameters.Keys -eq `
                    $paramName) {

                $localSwitches += $paramName
            }
            elseif ($Invocation.BoundParameters.Keys -eq $paramName) {
                $bound[$paramName] = $Invocation.BoundParameters[$paramName]
            }
        }

        return @{
            "bound" = $bound;
            "switches" = $localSwitches
        }
    }

    [string] GetShortActor([string] $FullActor) {

        # commandlet notation
        if ($FullActor.Contains("\")) {
            return $FullActor.Split("\")[-1]
        }
        # static function notation
        elseif ($FullActor.Contains("::")) {
            return $FullActor.Split("::")[-1]
        }
        # class member notation
        else {
            return $FullActor.Split(".")[-1]
        }
    }
}

function RecordAction {

    param(
        [Action] $Action
    )

    # read and update the running action id on disk
    $Action.Id = [int](Microsoft.PowerShell.Management\Get-Content -Raw "$WORK_DIR/action_id.txt")
    ($Action.Id + 1) | Out-File "$WORK_DIR/action_id.txt"

    $json = $Action | ConvertTo-Json -Depth 5
    ($json + ",") | Out-File -Append "$WORK_DIR/actions.json"
}

function RedirectObjectCreation {

    param(
        [string] $TypeName,
        [object[]] $ArgumentList
    )

    return Microsoft.PowerShell.Utility\New-Object -TypeName "BoxPS$($TypeName.Split(".")[-1])" -ArgumentList $ArgumentList
}

function GetOverridedClasses {
    return $BOXPS_CONFIG["Classes"].Keys | ForEach-Object { $_.ToLower() -replace "^system." }
}

<#
process objects make the output huge and it's not that useful
just keep the string representation
#>
function FlattenProcessObjects {

    param(
        [System.Diagnostics.Process[]] $ProcessList
    )

    $strings = @()

    $count = 0;
    while ($count -lt $ProcessList.Count) {
        $strings += $ProcessList[$count].ProcessName
        $count++
    }

    return $strings
}

Microsoft.PowerShell.Core\Import-Module -Name $CODE_DIR/ScriptInspector.psm1
Microsoft.PowerShell.Core\Import-Module -Name $CODE_DIR/HarnessBuilder.psm1
