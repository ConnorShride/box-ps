# routineArg should be either a string or array of strings containing paths

$routineArg = @($routineArg)
$pretendPaths = Microsoft.PowerShell.Management\Get-Content $CODE_DIR/pretend_paths.txt
$exists = $true

foreach ($checkedPath in $routineArg) {

    # avoid stupid Test-Path bug
    if ($checkedPath -ne "env:__SuppressAnsiEscapeSequences" -and $pretendPaths -notcontains $checkedPath) {
        $exists = $false
        break
    }
}

$exists
