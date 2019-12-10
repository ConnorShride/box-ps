# not fully implemented
function Set-ExecutionPolicy {

    $behaviorProps = @{}

    RecordAction $([Action]::new(@("other"), "[Microsoft.PowerShell.Security] Set-ExecutionPolicy", `
        $behaviorProps, $MyInvocation))
}

