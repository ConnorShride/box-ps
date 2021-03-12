# sc alias does not exist in powershell core
Set-Alias -Name sc -Value Set-Content

# redirect common paths to our override for powershell.exe (case insensitive)
Set-Alias -Name powershell -Value powershell.exe
Set-Alias -Name "C:\WINDOWS\syswow64\WindowsPowershell\v1.0\powershell.exe" -Value powershell.exe
Set-Alias -Name "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -Value powershell.exe
Set-Alias -Name "C:\WINDOWS\syswow64\WindowsPowershell\v1.0\powershell" -Value powershell.exe
Set-Alias -Name "C:\Windows\System32\WindowsPowerShell\v1.0\powershell" -Value powershell.exe