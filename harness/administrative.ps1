# using namespaces to find the necessary types of the parameters generated for the overrides
using namespace System.Management.Automation
using namespace System.Management.Automation.Runspaces
using namespace System.IO
using namespace System.Text
using namespace Microsoft.PowerShell.Commands
using namespace System.Diagnostics
using namespace System.Collections
using namespace Microsoft.PowerShell
using namespace System

$workingDir = "./working"

class Action <# lawsuit... I'll be here all week #> {

    [String[]] $Behaviors
    [String] $Actor
    [String] $FullActor
    [String] $Line
    [hashtable] $BehaviorProps
    [hashtable] $Parameters

    Action ([String[]] $Behaviors, [String] $FullActor, [hashtable] $BehaviorProps,
        [InvocationInfo] $Invocation) {

        $this.Behaviors = $Behaviors
        $this.FullActor = $FullActor
        $this.Actor = $this.GetShortActor($FullActor)
        $this.BehaviorProps = $BehaviorProps
        $this.Line = $Invocation.Line.Trim()

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
    Action ([String[]] $Behaviors, [String] $FullActor, [hashtable] $BehaviorProps, 
        [hashtable] $BoundParams, [String] $Line) {

        $this.Behaviors = $Behaviors
        $this.FullActor = $FullActor
        $this.Actor = $this.GetShortActor($FullActor)
        $this.BehaviorProps = $BehaviorProps
        $this.Parameters = $BoundParams
        $this.Line = $Line.Trim()
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
    ($json + ",") | Out-File -Append "$workingDir/actions.json"
}

function RedirectObjectCreation {

    param(
        [string] $TypeName
    )

    return Microsoft.PowerShell.Utility\New-Object -TypeName "BoxPS$($TypeName.Split(".")[-1])"
}

function GetOverridedClasses {
    $config = Microsoft.PowerShell.Management\Get-Content "./config.json" | ConvertFrom-Json -AsHashtable
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