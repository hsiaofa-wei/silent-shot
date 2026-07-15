#Requires -Version 5.1
<#
.SYNOPSIS
    Compile SilentShot.cs into SilentShot.exe (windowless winexe).
.DESCRIPTION
    Uses /target:winexe (GUI subsystem) so no console window is allocated.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File build.ps1
#>
param(
    [string]$Source = (Join-Path $PSScriptRoot 'SilentShot.cs'),
    [string]$Output = (Join-Path $PSScriptRoot 'SilentShot.exe')
)

$ErrorActionPreference = 'Stop'

$cscCandidates = @(
    "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
    "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe"
)
$csc = $cscCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $csc) {
    throw "csc.exe not found. Install .NET Framework 4.x.`n$($cscCandidates -join "`n")"
}

Write-Host "Compiler: $csc"
Write-Host "Source:   $Source"
Write-Host "Output:   $Output"

& $csc /nologo /target:winexe /out:"$Output" `
    /reference:System.Windows.Forms.dll `
    /reference:System.Drawing.dll `
    "$Source"

if ($LASTEXITCODE -ne 0) { throw "Build failed, exit code $LASTEXITCODE." }
Write-Host ""
Write-Host "OK: $Output" -ForegroundColor Green