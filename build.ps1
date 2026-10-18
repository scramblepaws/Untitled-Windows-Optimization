# Compiles WinDebloat.ps1 to a double-clickable .exe using PS2EXE.
# Dependencies: tweaks.ps1 + backup.ps1 must sit next to the .exe at runtime.

param(
    [string]$OutFile = 'WinDebloat.exe'
)

if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Install-Module -Name ps2exe -Scope CurrentUser -Force -SkipPublisherCheck
}
Import-Module ps2exe

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Invoke-ps2exe -InputFile (Join-Path $here 'WinDebloat.ps1') -OutputFile (Join-Path $here $OutFile) -NoConsole

Write-Output "Built $(Join-Path $here $OutFile)"
Write-Output 'Ship it alongside tweaks.ps1 and backup.ps1.'
