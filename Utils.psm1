# ensures no file name collision
function GetTmpFilePath {

    $done = $false
    $fileName = ""

    while (!$done) {
        $fileName = [System.IO.Path]::GetTempPath() + [GUID]::NewGuid().ToString() + ".txt";
        if (!(Test-Path $fileName)) {
            $done = $true
        }
    }

    return $fileName
}

function TabPad {
    
    param (
        [string] $block
    )

    $newBlock = ""

    foreach ($line in $block.Split("`r`n")) {
        $newBlock += "`t" + $line + "`r`n"
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

function SeparateLines
{
    param(
        [char[]]$Script
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

Export-ModuleMember -Function *