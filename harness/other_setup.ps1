# sc alias does not exist in powershell core
Set-Alias -Name sc -Value Set-Content

# redirect common paths to our override for powershell.exe (case insensitive)
Set-Alias -Name powershell -Value powershell.exe
Set-Alias -Name "C:\WINDOWS\syswow64\WindowsPowershell\v1.0\powershell.exe" -Value powershell.exe
Set-Alias -Name "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -Value powershell.exe
Set-Alias -Name "C:\WINDOWS\syswow64\WindowsPowershell\v1.0\powershell" -Value powershell.exe
Set-Alias -Name "C:\Windows\System32\WindowsPowerShell\v1.0\powershell" -Value powershell.exe

# Default ls command name is case sensitive. For some reason this kind
# of fixes that.
Set-Alias -Name ls -Value Get-ChildItem

# Override cmd.exe. Spaces matter in alias name :(.
Set-Alias -Name "cmd.exe" -Value fakecmdexe
Set-Alias -Name "cmd.exe " -Value fakecmdexe
Set-Alias -Name "cmd.exe  " -Value fakecmdexe
Set-Alias -Name "cmd.exe   " -Value fakecmdexe
Set-Alias -Name "cmd.exe    " -Value fakecmdexe
Set-Alias -Name "cmd.exe     " -Value fakecmdexe
Set-Alias -Name " cmd.exe" -Value fakecmdexe
Set-Alias -Name "  cmd.exe " -Value fakecmdexe
Set-Alias -Name "   cmd.exe  " -Value fakecmdexe
Set-Alias -Name "    cmd.exe   " -Value fakecmdexe
Set-Alias -Name "     cmd.exe    " -Value fakecmdexe
Set-Alias -Name "      cmd.exe     " -Value fakecmdexe
Set-Alias -Name "cmd" -Value fakecmdexe

# Don't want to actually move files.
Set-Alias -Name "mv" -Value fakemv
Set-Alias -Name "Move-Item" -Value fakemv

# Override mshta.exe. Spaces matter in alias name :(.
Set-Alias -Name "mshta.exe" -Value mshta
Set-Alias -Name "mshta.exe " -Value mshta
Set-Alias -Name "mshta.exe  " -Value mshta
Set-Alias -Name "mshta.exe   " -Value mshta
Set-Alias -Name "mshta.exe    " -Value mshta
Set-Alias -Name "mshta.exe     " -Value mshta
Set-Alias -Name " mshta.exe" -Value mshta
Set-Alias -Name "  mshta.exe " -Value mshta
Set-Alias -Name "   mshta.exe  " -Value mshta
Set-Alias -Name "    mshta.exe   " -Value mshta
Set-Alias -Name "     mshta.exe    " -Value mshta
# Spaces matter in alias name :(.
Set-Alias -Name "curl.exe" -Value fakecurl
Set-Alias -Name "curl.exe " -Value fakecurl
Set-Alias -Name "curl.exe  " -Value fakecurl
Set-Alias -Name "curl.exe   " -Value fakecurl
Set-Alias -Name "curl.exe    " -Value fakecurl
Set-Alias -Name "curl.exe     " -Value fakecurl
Set-Alias -Name " curl.exe " -Value fakecurl
Set-Alias -Name "  curl.exe  " -Value fakecurl
Set-Alias -Name "   curl.exe   " -Value fakecurl
Set-Alias -Name "    curl.exe    " -Value fakecurl
Set-Alias -Name "     curl.exe     " -Value fakecurl
Set-Alias -Name "curl" -Value fakecurl

# Override exit (no exits).
Set-Alias -Name "exit" -Value noop

# Track schtasks.
Set-Alias -Name "schtasks" -Value fakeschtasks

# Set some environment variables.
$env:computername = "LEGITMACHINE01"
$env:username = "LEGITUSER"
