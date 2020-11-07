# avoid that terrible Test-Path bug
if ($MyInvocation.InvocationName -ne "Test-Path") {

    $networkIOCs = @()
    $fileSystemIOCs = @()
    $environmentProbes = @()
    
    # get the variables present in the scope of the script
    $parentVars = Microsoft.PowerShell.Utility\Get-Variable -Scope 1
        
    # get the variables present in this scope (overrided function)
    $localVars = Microsoft.PowerShell.Utility\Get-Variable -Scope 0
    $localVarNames = Microsoft.PowerShell.Utility\New-Object System.Collections.ArrayList
    $localVars | ForEach-Object { $localVarNames.Add($_.Name) > $null }
        
    # filter out built-in variables and variables we declare to leave only user declared vars
    $declaredVars = $parentVars | Microsoft.PowerShell.Core\Where-object { 
        $localVarNames -notcontains $_.Name
    }
    $excluded = Microsoft.PowerShell.Management\Get-Content $CODE_DIR/iocs_ignore_vars.txt
    $declaredVars = $declaredVars | Where-Object { $excluded -notcontains $_.Name }
    
    $declaredVars | ForEach-Object {
        $_.Value | Out-String -Stream | ForEach-Object { 
            $networkIOCs += ScrapeNetworkIOCs $_
        }
        $_.Value | Out-String -Stream | ForEach-Object { 
            $fileSystemIOCs += ScrapeFilePaths $_
        }
        $_.Value | Out-String -Stream | ForEach-Object {
            $environmentProbes += ScrapeEnvironmentProbes -Variable $_
        }
    }

    $networkIOCs | Microsoft.PowerShell.Utility\Out-File -Append "$WORK_DIR/scraped_network.txt"
    $fileSystemIOCs | Microsoft.PowerShell.Utility\Out-File -Append "$WORK_DIR/scraped_paths.txt"
    $environmentProbes | Microsoft.PowerShell.Utility\Out-File -Append "$WORK_DIR/scraped_probes.txt"
}