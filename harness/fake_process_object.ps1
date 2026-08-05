# Make a fake object for Start-Process that always claims it
# succeeded.
class StubbedProcess {
    $ExitCode
    $Name
    StubbedProcess() {
	    $this.ExitCode = 0
        $this.Name = "explorer"
    }
    WaitForExit() {}
}

# Some malware gates based on whether a certain process is
# running. Return an empty list in those cases.
$r = ([StubbedProcess]::new())
$gateProcs = @("aspnet_compiler")
foreach ($gateProc in $gateProcs) {
    if ($routineArg -eq $gateProc) {
        $r = @()
    }
}

$r
