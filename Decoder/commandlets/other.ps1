# not fully implemented
function Set-ExecutionPolicy {

    $behaviorProps = @{}

    RecordAction $([Action]::new(@("other"), "Set-ExecutionPolicy", 
        "Microsoft.PowerShell.Security\Set-ExecutionPolicy", $behaviorProps, $MyInvocation))
}

