$config = Get-Content $PSScriptRoot\config.json | ConvertFrom-Json -AsHashtable
$utils = Import-Module -Name ./Utils.psm1 -AsCustomObject -Scope Local


function ReplaceStaticNamespaces {

    param(
        [string] $Layer
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
        $match = $Layer | Select-String -Pattern $("\[[\w\.]+(?<!$boxStaticsClass)\]::$shortName\(")
        $match = $match.Matches

        # remove the namespace
        if ($match) {

            $namespaceStart = $Layer.LastIndexOf("[", $match.Index)
            $namespaceEnd = $Layer.IndexOf(']', $namespaceStart)
    
            $Layer = $Layer.Remove($namespaceStart + 1, $namespaceEnd - $namespaceStart - 1)
            $Layer = $Layer.Insert($namespaceStart + 1, $staticsClass)
        }
        # don't look for matches on that cmdlet anymore
        else {
            $functions.Remove($functions[0])
        }
    }

    return $Layer
}

function ScrubCmdletNamespaces {

    param(
        [string] $Layer
    )

    $cmdlets = New-Object System.Collections.ArrayList

    # get all the cmdlets we care about
    foreach ($behavior in $config["Cmdlets"].keys) {
        foreach ($cmdlet in $config["Cmdlets"][$behavior].keys) {
            $cmdlets.Add([string]($cmdlet)) | Out-Null
        }
    }

    # find an instance of cmdlet invocation by full namespace
    # remove the cmdlet from the list when there are no matches for it anymore
    while ($cmdlets.Count -gt 0) {

        $pat = [Regex]::Escape($cmdlets[0])
        $match = $Layer | Select-String -Pattern $("$pat ")
        $match = $match.Matches

        # remove the namespace
        if ($match) {

            $namespaceLen = $Layer.IndexOf("\", $match.Index) - $match.Index + 1
            $Layer = $Layer.Remove($match.Index, $namespaceLen)
        }
        # don't look for matches on that cmdlet anymore
        else {
            $cmdlets.Remove($cmdlets[0])
        }
    }

    return $Layer
}

# find and remove fully qualified namespace from cmdlet and function calls
# ensures that our overrides are called instead of the real ones
function HandleNamespaces {

    param(
        [string] $Layer
    )

    $Layer = ReplaceStaticNamespaces $Layer
    $Layer = ScrubCmdletNamespaces $Layer

    return $Layer
}

function SplitReplacement {

    param(
        [String] $Layer
    )

    if (($Layer -is [String]) -and ($Layer -Like "*.split(*")) {

        $start = $Layer.IndexOf(".split(", [System.StringComparison]::CurrentCultureIgnoreCase)
        $end = $Layer.IndexOf(")", $start)
        $split1 = $Layer.Substring($start, $end - $start + 1)
        $split2 = $split1
        if (($split1.Length -gt 11) -and (-not ($split1 -Like "*[char[]]*"))) {
            $start = $split1.IndexOf("(") + 1
            $end = $split1.IndexOf(")") - 1
            $chars = $split1.Substring($start, $end - $start + 1).Trim()
            $split2 = ".Split([char[]]" + $chars + ")"
        }
        $Layer = $Layer.Replace($split1, $split2)
    }    

    return $Layer
}

# look for environment variables and coerce them to be lowercase
function EnvReplacement {

    param(
        [String] $Layer
    )

    foreach ($var in $config["Environment"].keys) {
        $Layer = $Layer -ireplace [regex]::Escape($var), $var
    }

    return $Layer -ireplace "pshome", "bshome"
}

Export-ModuleMember -Function EnvReplacement
Export-ModuleMember -Function HandleNamespaces
Export-ModuleMember -Function SplitReplacement