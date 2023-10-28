# HarnessBuilder will prepend a variable named $routineArg that contains the value of the byte array
# we want to scrape through

$ascii = $null

# it's an int array
if ($routineArg.GetType() -eq [System.Int64[]] -or $routineArg.GetType() -eq [System.Int32[]] -or $routineArg.GetType() -eq [System.Int16[]]) {
    $ascii = [char[]]$routineArg -join ''
}
# it's a byte array
elseif ($routineArg.GetType() -eq [byte[]]) {
    $ascii = [System.Text.Encoding]::ASCII.GetString($routineArg)
}
# it's a char array
elseif ($routineArg.GetType() -eq [char[]]) {
    $ascii = $routineArg -join ''
}

ScrapeNetworkIOCs -Aggressive $ascii | Microsoft.PowerShell.Utility\Out-File -Append "$WORK_DIR/scraped_network.txt"

$routineReturn = $ascii
