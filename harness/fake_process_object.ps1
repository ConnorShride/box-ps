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
([StubbedProcess]::new())
