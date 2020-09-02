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

$WORK_DIR = "./working"
$CODE_DIR = "<CODE_DIR>"

class Action <# lawsuit... I'll be here all week #> {

    [String[]] $Behaviors
    [String] $Actor
    [String] $Line
    [hashtable] $BehaviorProps
    [hashtable] $Parameters
    [string] $ExtraInfo

    Action ([String[]] $Behaviors, [String] $Actor, [hashtable] $BehaviorProps,
        [InvocationInfo] $Invocation, [string] $ExtraInfo) {

        $this.Behaviors = $Behaviors
        $this.Actor = $Actor
        $this.BehaviorProps = $BehaviorProps
        $this.Line = $Invocation.Line.Trim()
        $this.ExtraInfo = $ExtraInfo

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
    Action ([String[]] $Behaviors, [String] $Actor, [hashtable] $BehaviorProps, 
        [hashtable] $BoundParams, [String] $Line, [String] $ExtraInfo) {

        $this.Behaviors = $Behaviors
        $this.Actor = $Actor
        $this.BehaviorProps = $BehaviorProps
        $this.Parameters = $BoundParams
        $this.Line = $Line.Trim()
        $this.ExtraInfo = $ExtraInfo
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
    
    $json = $Action | ConvertTo-Json -Depth 10
    ($json + ",") | Out-File -Append "$WORK_DIR/actions.json"
}

function RedirectObjectCreation {

    param(
        [string] $TypeName
    )

    return Microsoft.PowerShell.Utility\New-Object -TypeName "BoxPS$($TypeName.Split(".")[-1])"
}

function GetOverridedClasses {
    $config = Microsoft.PowerShell.Management\Get-Content "$CODE_DIR/config.json" | ConvertFrom-Json -AsHashtable
    return $config["Classes"].Keys | ForEach-Object { $_.ToLower() }
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