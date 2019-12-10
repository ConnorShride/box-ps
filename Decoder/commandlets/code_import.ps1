function Add-Type {

    param(
        [String] $TypeDefinition
    )

    $behaviorProps = @{
        "code" = $TypeDefinition
    }

    RecordAction $([Action]::new(@("code_import"), "Add-Type", 
        "Microsoft.PowerShell.Utility\Add-Type", $behaviorProps, $MyInvocation))
}