# avoid that terrible Test-Path bug
if ($MyInvocation.InvocationName -ne "Test-Path") {

    $networkIOCs = @()
    $fileSystemIOCs = @()
    $environmentProbes = @()

    # get the variables present in the scope of the script
    try{
        $parentVars = Microsoft.PowerShell.Utility\Get-Variable -Scope 1
    }
    # if they're dot sourceing an override, there will be no parent scope
    catch
    {
        $parentVars = @()
    }

    # get the variables present in this scope
    $localVars = Microsoft.PowerShell.Utility\Get-Variable -Scope 0

    # filter out built-in variables and variables we declare to leave only user declared vars
    $localVarNames = Microsoft.PowerShell.Utility\New-Object System.Collections.ArrayList
    $localVars | ForEach-Object { $localVarNames.Add($_.Name) > $null }
    $declaredVars = $parentVars | Microsoft.PowerShell.Core\Where-object { 
        $localVarNames -notcontains $_.Name
    }

    $excluded = Microsoft.PowerShell.Management\Get-Content $CODE_DIR/iocs_ignore_vars.txt
    $declaredVars = $declaredVars | Where-Object { $excluded -notcontains $_.Name }

    foreach ($declaredVar in $declaredVars) {

        $value = $declaredVar.Value

        # ignore arrays of integers or bytes
        if ($null -eq $value -or $value.GetType() -eq [int[]] -or $value.GetType() -eq [byte[]]) {
            continue
        }

        if ($declaredVar.Value.GetType() -eq [string[]]) {
            $value = $value -join ""
        }

        $value | Out-String -Stream | ForEach-Object { 
            $networkIOCs += ScrapeNetworkIOCs $_
        }
        $value | Out-String -Stream | ForEach-Object { 
            $fileSystemIOCs += ScrapeFilePaths $_
        }
        $value | Out-String -Stream | ForEach-Object {
            $environmentProbes += ScrapeEnvironmentProbes -Variable $_
        }
    }

    $networkIOCs | Microsoft.PowerShell.Utility\Out-File -Append "$WORK_DIR/scraped_network.txt"
    $fileSystemIOCs | Microsoft.PowerShell.Utility\Out-File -Append "$WORK_DIR/scraped_paths.txt"
    $environmentProbes | Microsoft.PowerShell.Utility\Out-File -Append "$WORK_DIR/scraped_probes.txt"
}
