$utils = Microsoft.PowerShell.Core\Import-Module -Name $PSScriptRoot/Utils.psm1 -AsCustomObject -Scope Local
$config = Microsoft.PowerShell.Management\Get-Content $PSScriptRoot/config.json | 
    Microsoft.PowerShell.Utility\ConvertFrom-Json -AsHashtable

$WORK_DIR = "./working"

function ReplaceStaticNamespaces {

    param(
        [string] $Script
    )

    $boxStaticsClass = "BoxPSStatics"
    $functions = Microsoft.PowerShell.Utility\New-Object System.Collections.ArrayList

    # get all the static functions names we care about

    # gather the automatic overrides
    foreach ($function in $config["Statics"].keys) {
        $functions.Add([string]($function)) | Out-Null
    }

    # gather the manual overrides
    foreach ($function in $config["Manuals"]["Statics"].Keys) {
        $functions.Add([string]($function)) | Out-Null
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
    foreach ($cmdlet in $config["Cmdlets"].keys) {
        $cmdlets.Add([string]($cmdlet)) | Out-Null
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

    $Script = $Script -ireplace "\`$pshome", "`$bshome"
    $Script = $Script -ireplace "\`$home", "`$bhome"

    return $Script
}

function ReplaceBadEscapes {

    param(
        [String] $Script
    )

    return $Script.Replace("``e", "e").Replace("``u", "u")
}

function BoxifyScript {

    param(
        [String] $Script
    )
    
    $Script = ReplaceBadEscapes($Script)
    $Script = EnvReplacement($Script)
    # too inefficient for too little benefit
    #$Script = $utils.SeparateLines($Script)
    $Script = HandleNamespaces($Script)

    return $Script
}

function ScrapeFilePaths {

    param(
        [String] $str
    )

	$paths = @()

    $regex = "((file:(\\)+)|(\\\\smb\\)|([a-zA-Z]:(\\)+)|(\.(\.)?(\\)+))([^\*```"`'\?]+((\\)+)?)*"
    $matchRes = $str | Microsoft.Powershell.Utility\Select-String -Pattern $regex -AllMatches

    if ($matchRes) {
        $matchRes.Matches | Microsoft.PowerShell.Core\ForEach-Object { $paths += $_.Value }
    }

    return $paths
}

function ScrapeNetworkIOCs {
    
    param(
        [String] $str,
        [Switch] $Aggressive
    )

    $iocs = @()

    $iocs += ScrapeUrls $str
    $iocs += ScrapeIPs $str

    if ($Aggressive) {
        $iocs += ScrapeDomains $str
    }

    return $iocs
}

function ScrapeUrls {

    param(
        [String] $str
    )

	$urls = @()

    $regex = "(http[s]?:(?:(?://)|(?:\\\\?))(([a-zA-Z0-9_\-]+\.[a-zA-Z0-9_\-\.]+(:[0-9]+)?)+([/\\]([/\\\?&\~=a-zA-Z0-9_\-\.](?!http))+)?))"
    $matchRes = $str | Microsoft.Powershell.Utility\Select-String -Pattern $regex -AllMatches

    if ($matchRes) {
        $matchRes.Matches | Microsoft.PowerShell.Core\ForEach-Object { $urls += $_.Value }
    }

    return $urls
}

function ScrapeDomains {

    param(
        [String] $str
    )

    $domains = @()
    
    $regex = "(([a-zA-Z0-9_\-]+[a-zA-Z][a-zA-Z0-9_\-]*\.){1,2}(?!(D|d)(L|l)(L|l))[a-zA-Z0-9_\-]+[a-zA-Z][a-zA-Z0-9_\-]*)"
    $matchRes = $matchRes = $str | Microsoft.Powershell.Utility\Select-String -Pattern $regex -AllMatches

    if ($matchRes) {
        $matchRes.Matches | Microsoft.PowerShell.Core\ForEach-Object { $domains += $_.Value }
    }

    return $domains
}


function ScrapeIPs {

    param(
        [String] $str
    )

    $ips = @()

    $regex = "\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}"
    
    $matchRes = $str | Microsoft.Powershell.Utility\Select-String -Pattern $regex -AllMatches

    if ($matchRes) {
        $matchRes.Matches | Microsoft.PowerShell.Core\ForEach-Object { 
            
            # validate that each octet is less than 255 (lazy regex)
            $valid = $true
            $octets = $_.Value.Split(".")
            foreach ($octet in $octets) {
                if ($octet -as [int] -gt 255) {
                    $valid = $false
                }
            }
            if ($valid) {
                $ips += $_.Value 
            }
        }
    }

    return $ips
}

# scrape out checks against known values representing truths about the environent
# Return a csv with one or more of the values "Language", "Date", "Host" followed by the value
# being checked against followed by the logical operation on the check or NULL if not found
function ScrapeEnvironmentProbes {

	param(
        [string] $Script,
        [switch] $Variable
	)

    $environmentProbes = @()
    if ($Variable) {
        $environmentProbes += ScrapeLanguageProbes -Variable $Script
    }
    else {
        $environmentProbes += ScrapeLanguageProbes $Script
    }
	return $environmentProbes
}

# scrapes the script for logical checks against known language strings indicating a gating against
# the language of the environment. Returns a list of key/value pairs mapping the display name of the
# language being checked against to the operation "eq" or "ne"
function ScrapeLanguageProbes {

	param(
		[string] $Script,
		[switch] $Variable
    )

	# look for a subset of possible languages. This routine is too slow for all of them
	$knownLanguages = @{
		"English (United States)" = @("en-US", "1033");
		"English (South Africa)" = @("en-ZA", "7177");
		"English (Netherlands)" = @("en-NL", "4096");
		"English (Germany)" = @("en-DE", "4096");
		"English" = @("en", "9");
		"German (Germany)" = @("de-DE", "1031");
		"Afrikaans (South Africa)" = @("af-ZA", "1078");
		"Zulu (South Africa)" = @("zu-ZA", "1077");
		"Chinese (Traditional)" = @("zh-Hant", "31748");
		"Chinese (Simplified)" = @("zh-Hans", "4");
		"Chinese" = @("zh", "30724");
		"Yiddish" = @("yi", "61");
		"Vietnamese" = @("vi", "42");
		"Ukrainian" = @("uk", "34");
		"Turkish" = @("tr", "31");
		"Thai (Thailand)" = @("th-TH", "1054");
		"Thai" = @("th", "30");
		"Swedish (Sweden)" = @("sv-SE", "1053");
		"Russian (Russia)" = @("ru-RU", "1049");
		"Portuguese" = @("pt", "22");
		"Dutch (Netherlands)" = @("nl-NL", "1043");
		"Italian (Italy)" = @("it-IT", "1040");
		"Italian" = @("it", "16");
		"Hindi" = @("hi", "57");
		"Hebrew (Israel)" = @("he-IL", "1037");
		"French (France)" = @("fr-FR", "1036");
		"Finnish (Finland)" = @("fi-FI", "1035");
		"Spanish (Spain)" = @("es-ES", "3082");
	}

	$probes = @()
	foreach ($languageName in $knownLanguages.Keys) {

		# for now just use display name and string code, because the integer id is not going to be a
		# unreliable indicator scraping the entire script
		$name = [Regex]::Escape($languageName)
		$code = [Regex]::Escape($knownLanguages[$languageName][0])
		$baseRegex = ""

		# check for the language code if it's a two part code (less false positives)
		if ($code.Contains("-")) {
			$baseRegex = "($name)|($code)"
		}
		else {
			$baseRegex = "($name)"
		}

		# be way less stingy with the contents of variables. They're probably only going to contain
		# the language string in isolation anyways
		if ($Variable) {
			$regex = $baseRegex
        }
        else {
            $regex = "(?<operator>-eq|-ne)?\s+(`'|`")($baseRegex)(`'|`")"
        }

		$matchRes = $Script | Microsoft.Powershell.Utility\Select-String -Pattern $regex -AllMatches
		if ($matchRes) {
			foreach ($match in $matchRes.Matches) {
				$operator = "NULL"
				if ($match.Groups["operator"].Success) {
					$operator = $match.Groups["operator"].Value.Replace("-", "")
                }
				$probes += "language,$([Regex]::Unescape($name)),$operator"
			}
		}
	}

    # each probe is a csv formatted string
	return $probes
}

# code modifications to integrate it with the overrides
# recording layer for output
# scrape potential IOCs
function PreProcessScript {

    param(
        [string] $Script
    )

    $Script = BoxifyScript $Script
    ScrapeNetworkIOCs $Script | Microsoft.PowerShell.Utility\Out-File -Append "$WORK_DIR/scraped_network.txt" 
    ScrapeFilePaths $Script | Microsoft.PowerShell.Utility\Out-File -Append "$WORK_DIR/scraped_paths.txt"
    ScrapeEnvironmentProbes $Script | Microsoft.PowerShell.Utility\Out-File -Append "$WORK_DIR/scraped_probes.txt"

    $separator = ("*" * 100 + "`r`n")
    $layerOut = $separator + $Script + "`r`n" + $separator
    $layerOut | Microsoft.PowerShell.Utility\Out-File -Append -Path $WORK_DIR/layers.ps1
    
    return $Script
}

Export-ModuleMember -Function PreProcessScript
Export-ModuleMember -Function ScrapeNetworkIOCs
Export-ModuleMember -Function ScrapeFilePaths
Export-ModuleMember -Function ScrapeEnvironmentProbes