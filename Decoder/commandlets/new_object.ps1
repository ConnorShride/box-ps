# ADVANCED FUNCTION ALL PARAMETERS BOUND
function New-Object {

    param(
        [parameter(Position=1)][Alias("Args")][Object[]] $ArgumentList,
        [Alias("COM")][String] $COMObject,
        [parameter(Position=0)][String] $TypeName,
        [System.Collections.IDictionary] $Property,
        [Switch] $Strict
    )

    $behaviorProps = @{ }

    if ($PSBoundParameters.ContainsKey("COMObject")) {
        $behaviorProps["object"] = $COMObject.ToLower()
    }
    elseif ($PSBoundParameters.ContainsKey("TypeName")) {
        $behaviorProps["object"] = $TypeName.ToLower()
    }

    RecordAction $([Action]::new(@("new_object"), "New-Object", 
        "Microsoft.PowerShell.Utility\New-Object", $behaviorProps, $MyInvocation))

    # redirect object creation to our own webclient implementation
    if ($TypeName.tolower() -like "*net.webclient") {
        return [BoxPSWebClient]::new()
    }

    # COMObject not implemented in core
    if (!$PSBoundParameters.ContainsKey("COMObject")) {
        return Microsoft.PowerShell.Utility\New-Object @PSBoundParameters
    }
}