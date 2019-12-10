function Add-Type {

    param(
        [String] $TypeDefinition
    )

    $behaviorProps = @{
        "code" = $TypeDefinition
    }

    <#
    de-conflict the carat character, which we will squash after this returns as a potential 
    escape character for CMD commands. Since we know this code will not be CMD, we can 
    safely keep it as an XOR operator
    #>
    $TypeDefinition = ($TypeDefinition.Replace("^", "SAVECARET"))

    RecordAction $([Action]::new(@("code_import"), "[Microsoft.PowerShell.Utility] Add-Type", `
        $behaviorProps, $MyInvocation))
}