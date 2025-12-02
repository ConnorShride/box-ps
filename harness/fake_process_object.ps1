# Make a fake object for Start-Process that always claims it
# succeeded.
class StubbedProcess {
    $ExitCode
    StubbedProcess() {
	$this.ExitCode = 0
    }
    WaitForExit() {}
}
([StubbedProcess]::new())
