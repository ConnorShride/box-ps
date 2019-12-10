# not fully implemented
function Invoke-WebRequest {
    
    param(
        [Uri] $Uri,
        [String] $OutFile,
        [String] $UserAgent
    )

    $behaviorProps = @{
        "uri" = $Uri
    }

    RecordAction $([Action]::new(@("network"), "[Microsoft.PowerShell.Utility] Invoke-WebRequest", `
        $behaviorProps, $MyInvocation))
}

# not fully implemented
function Invoke-RestMethod {

    param(
        [Uri] $Uri
    )

    $behaviorProps = @{
        "uri" = $Uri
    }

    RecordAction $([Action]::new(@("network"), "[Microsoft.PowerShell.Utility] Invoke-RestMethod", `
        $behaviorProps, $MyInvocation))
}