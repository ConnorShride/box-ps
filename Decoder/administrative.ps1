class Action <# lawsuit... I'll be here all week #> {

    [String[]] $Behaviors
    [String] $Actor
    [String] $FullActor
    [String] $Line
    [hashtable] $BehaviorProps
    [hashtable] $BoundParams
    [String[]] $UnboundParams
    [String[]] $Switches

    Action ([String[]] $Behaviors, [String] $Actor, [String] $FullActor, [hashtable] $BehaviorProps,
        [System.Management.Automation.InvocationInfo] $Invocation) {

        $this.Behaviors = $Behaviors
        $this.Actor = $Actor
        $this.FullActor = $FullActor
        $this.BehaviorProps = $BehaviorProps
        $this.Line = $Invocation.Line.Trim()

        $paramsSplit = $this.SplitParams($Invocation)

        $this.BoundParams = $paramsSplit["bound"]
        $this.UnboundParams = $paramsSplit["unbound"]
        $this.Switches = $paramsSplit["switches"]
    }

    # for class members
    #   These are guaranteed not to have unbound or switches, and the MyInvocation variable does not
    #   contain boundparameters, so callers need to be able to pass the PSBoundParameters variable
    # e.g. System.Net.WebClient.DownloadFile
    Action ([String[]] $Behaviors, [String] $Actor, [String] $FullActor, [hashtable] $BehaviorProps,
        [hashtable] $BoundParams, [String] $Line) {

        $this.Behaviors = $Behaviors
        $this.FullActor = $FullActor
        $this.Actor = $Actor
        $this.BehaviorProps = $BehaviorProps
        $this.BoundParams = $BoundParams
        $this.Line = $Line.Trim()
        $this.UnboundParams = @()
        $this.Switches = @()
    }

    <#
    linear walk through all parameters rebuilding bound params and switches. Unbound arguments are, 
    for some reason, not present in MyCommand.Parameters (thanks for the help, pwsh)
    #>
    [hashtable] SplitParams([System.Management.Automation.InvocationInfo] $Invocation) {

        $allParams = $Invocation.MyCommand.Parameters

        $bound = @{}
        $localSwitches = @() # not allowed to name this $switches (thanks for the help, pwsh)
        
        foreach ($paramName in $allParams.Keys) {

            <#
            for some reason, all common parameters are in MyCommand.Parameters even if they are not
            given explicitely and don't even have default values (thanks for the help, pwsh)
            #>
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
            "unbound" = $Invocation.UnboundArguments;
            "switches" = $localSwitches
        }
    }
}


# Write out JSON representation of the arguments this function is given to the output file
# ACTIONS_OUTFILE_PLACEHOLDER will be replaced with the real value by box-ps.ps1
function RecordAction {

    param(
        [Action] $Action
    )

    $actionsOutFile = "ACTIONS_OUTFILE_PLACEHOLDER"

    $json = $Action | ConvertTo-Json -Depth 10
    ($json + ",") | Out-File -Append $actionsOutFile
}

# placeholder will be replaced with the real value by box-ps.ps1
function RecordLayer {
    param(
        [String]$layer
    )

    $layersOutFile = "LAYERS_OUTFILE_PLACEHOLDER"

    $output = ("LAYERDELIM" + $layer + "LAYERDELIM")
    $output | Out-File -Append $layersOutFile
}
