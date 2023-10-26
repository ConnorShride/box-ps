using namespace System.Collections

function TabPad {

    param (
        [string] $block
    )

    $newBlock = ""

    foreach ($line in $block.Split("`n")) {
        $newBlock += "`t" + $line + "`n"
    }

    return $newBlock
}

function GetUnqualifiedName {

    param(
        [string] $FullyQualified
    )

    $unqualified = ""

    if ($FullyQualified.Contains("\")) {
        $unqualified = $FullyQualified.Split("\")[1]
    }
    elseif ($FullyQualified.Contains("::")) {
        $unqualified = $FullyQualified.Split("::")[1]
    }
    else {
        $unqualified = $FullyQualified
    }

    return $unqualified
}

function SquashStaticName {

    param(
        [string] $StaticName
    )
    return $StaticName -replace "[\[\]:\.]",""
}

function SeparateLines
{
    param(
        [char[]] $Script
    )

    $prevChar = ''
    $separated = ''
    $inLiteral = $false
    $inParentheses = $false
    $quotingChar = ''
    $quotes = '"', "'"
    $whitespace = ''

    foreach ($char in $Script) {

        # if the character is not inside a string literal or parentheses
        if (!$inLiteral -and !$inParentheses) {

            # if this is the start of a string literal, record the quote used to start it
            if ($char -contains $quotes) {
                $quotingChar = $char
                $inLiteral = $true
            }
            elseif ($char -eq '(') {
                $inParentheses = $true
            }
            elseif ($char -eq ';') { $whitespace = "`r`n" }
        }
        # otherwise if it's the ending quote of a string literal
        elseif ($char -contains $quotes -and $quotingChar -eq $char -and $prevChar -ne '`') {
            $quotingChar = ''
            $inLiteral = $false
        }
        #otherwise if it's an ending parentheses
        elseif ($char -eq ')') {
            $inParentheses = $false
        }

        $separated += $char + $whitespace
        $prevChar = $char
        $whitespace = ''
    }

    return $separated
}

function ListIntersection {

    param(
        [ArrayList] $list1,
        [ArrayList] $list2
    )

    return @($list1 | Microsoft.PowerShell.Core\Where-object { $list2 -contains $_ })
}

function ListDifference {

    param(
        [ArrayList] $list1,
        [ArrayList] $list2
    )

    return $list1 | Microsoft.PowerShell.Core\Where-object { $list2 -notcontains $_ }
}

# Functions for rewriting powershell code prior to sandboxing.

function StripWindowsPrincipal {

    # WindowsPrincipal class only really supported under Windows, not
    # linux, so strip it if possible.

    param (
        [String] $code
    )

    ForEach ($line in $code.Split("`n")) {
        If ($line.Contains("Security.Principal.WindowsPrincipal")) {
            continue
        }
        $r += $line + "`n"
    }

    # Done. Return the modified code.
    $r
}

function RewriteCode {

    # Top level function for all code rewrites. Add additional calls
    # to specific code rewriting functions here.

    param (
        [String] $code
    )

    $r = StripWindowsPrincipal($code)
    $r
}

Export-ModuleMember -Function *
