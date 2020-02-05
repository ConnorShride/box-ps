$config = Get-Content $PSScriptRoot\config.json | ConvertFrom-Json -AsHashtable
$utils = Import-Module -Name ./Utils.psm1 -AsCustomObject -Scope Local


function ReplaceStaticNamespaces {

    param(
        [string] $Script
    )

    $boxStaticsClass = "BoxPSStatics"
    $functions = New-Object System.Collections.ArrayList

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
        $match = $Script | Select-String -Pattern $("\[[\w\.]+(?<!$boxStaticsClass)\]::$shortName\(")
        $match = $match.Matches

        # remove the namespace
        if ($match) {

            $namespaceStart = $Script.LastIndexOf("[", $match.Index)
            $namespaceEnd = $Script.IndexOf(']', $namespaceStart)
    
            $Script = $Script.Remove($namespaceStart + 1, $namespaceEnd - $namespaceStart - 1)
            $Script = $Script.Insert($namespaceStart + 1, $staticsClass)
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

    $cmdlets = New-Object System.Collections.ArrayList

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
        $match = $Script | Select-String -Pattern $("$pat ")
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

function SplitReplacement {

    param(
        [String] $Script
    )

    if (($Script -is [String]) -and ($Script -Like "*.split(*")) {

        $start = $Script.IndexOf(".split(", [System.StringComparison]::CurrentCultureIgnoreCase)
        $end = $Script.IndexOf(")", $start)
        $split1 = $Script.Substring($start, $end - $start + 1)
        $split2 = $split1
        if (($split1.Length -gt 11) -and (-not ($split1 -Like "*[char[]]*"))) {
            $start = $split1.IndexOf("(") + 1
            $end = $split1.IndexOf(")") - 1
            $chars = $split1.Substring($start, $end - $start + 1).Trim()
            $split2 = ".Split([char[]]" + $chars + ")"
        }
        $Script = $Script.Replace($split1, $split2)
    }    

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

Export-ModuleMember -Function EnvReplacement
Export-ModuleMember -Function HandleNamespaces
Export-ModuleMember -Function SplitReplacement