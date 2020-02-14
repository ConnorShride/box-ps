$utils = Microsoft.PowerShell.Core\Import-Module -Name ./Utils.psm1 -AsCustomObject -Scope Local
$config = Microsoft.PowerShell.Management\Get-Content $PSScriptRoot\config.json | 
    Microsoft.PowerShell.Utility\ConvertFrom-Json -AsHashtable

function ReplaceStaticNamespaces {

    param(
        [string] $Script
    )

    $boxStaticsClass = "BoxPSStatics"
    $functions = Microsoft.PowerShell.Utility\New-Object System.Collections.ArrayList

    # get all the static functions names we care about
    foreach ($behavior in $config["Statics"].keys) {
        foreach ($function in $config["Statics"][$behavior].keys) {
            $functions.Add([string]($function)) | Out-Null
        }
    }

    # find an instance of a static method invocation we care about 
    # remove the method from the list 
    while ($functions.Count -gt 0) {

        $shortName = $utils.GetUnqualifiedName($functions[0])
        $match = $Script | Microsoft.Powershell.Utility\Select-String -Pattern $("\[[\w\.]+(?<!$boxStaticsClass)\]::$shortName\(")
        $match = $match.Matches

        # remove the namespace
        if ($match) {

            $namespaceStart = $Script.LastIndexOf("[", $match.Index)
            $namespaceEnd = $Script.IndexOf(']', $namespaceStart)
    
            $Script = $Script.Remove($namespaceStart + 1, $namespaceEnd - $namespaceStart - 1)
            $Script = $Script.Insert($namespaceStart + 1, $boxStaticsClass)
        }
        # don't look for matches on that cmdlet anymore
        else {
            $functions.Remove($functions[0])
        }
    }

    return $Script
}

function ScrubCmdletNamespaces {

    param(
        [string] $Script
    )

    $cmdlets = Microsoft.Powershell.Utility\New-Object System.Collections.ArrayList

    # get all the auto-override cmdlets we care about
    foreach ($behavior in $config["Cmdlets"].keys) {
        foreach ($cmdlet in $config["Cmdlets"][$behavior].keys) {
            $cmdlets.Add([string]($cmdlet)) | Out-Null
        }
    }

    # get all the manual-override cmdlets we care about
    foreach ($cmdlet in $config["Manuals"]["Cmdlets"]) {
        $cmdlets.Add([string]($cmdlet)) | Out-Null
    }

    # find an instance of cmdlet invocation by full namespace
    # remove the cmdlet from the list when there are no matches for it anymore
    while ($cmdlets.Count -gt 0) {

        $pat = [Regex]::Escape($cmdlets[0])
        $match = $Script | Microsoft.Powershell.Utility\Select-String -Pattern $("$pat ")
        $match = $match.Matches

        # remove the namespace
        if ($match) {

            $namespaceLen = $Script.IndexOf("\", $match.Index) - $match.Index + 1
            $Script = $Script.Remove($match.Index, $namespaceLen)
        }
        # don't look for matches on that cmdlet anymore
        else {
            $cmdlets.Remove($cmdlets[0])
        }
    }

    return $Script
}

# find and remove fully qualified namespace from cmdlet and function calls
# ensures that our overrides are called instead of the real ones
function HandleNamespaces {

    param(
        [string] $Script
    )

    $Script = ReplaceStaticNamespaces $Script
    $Script = ScrubCmdletNamespaces $Script

    return $Script
}

# look for environment variables and coerce them to be lowercase
function EnvReplacement {

    param(
        [String] $Script
    )

    foreach ($var in $config["Environment"].keys) {
        $Script = $Script -ireplace [regex]::Escape($var), $var
    }

    return $Script -ireplace "pshome", "bshome"
}

function BoxifyScript {

    param(
        [String] $Script
    )
    
    $Script = EnvReplacement($Script)
    $Script = $utils.SeparateLines($Script)
    $Script = HandleNamespaces($Script)

    return $Script
}

Export-ModuleMember -Function BoxifyScript