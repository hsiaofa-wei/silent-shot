#Requires -Version 5.1
<#
.SYNOPSIS
    把 SilentShot.cs 编译成无窗口后台程序 SilentShot.exe。
.DESCRIPTION
    关键点：用 /target:winexe（GUI 子系统）而非 /target:exe（控制台子系统），
    这样进程根本不分配控制台窗口，屏幕上没有任何可被误关的窗口。
    依赖 System.Windows.Forms 和 System.Drawing 两个程序集（截图 + 隐藏窗体 + 热键消息循环）。
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File build.ps1
#>
param(
    [string]$Source = (Join-Path $PSScriptRoot 'SilentShot.cs'),
    [string]$Output = (Join-Path $PSScriptRoot 'SilentShot.exe')
)

$ErrorActionPreference = 'Stop'

# 定位 .NET Framework 自带的 C# 编译器 csc.exe（Windows 上 PowerShell 5.1 默认有）
$cscCandidates = @(
    "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
    "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe"
)
$csc = $cscCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $csc) { throw "找不到 csc.exe，请确认已安装 .NET Framework 4.x。候选路径：`n$($cscCandidates -join "`n")" }

Write-Host "使用编译器: $csc"
Write-Host "源文件:     $Source"
Write-Host "输出:       $Output"

& $csc /nologo /target:winexe /out:"$Output" `
    /reference:System.Windows.Forms.dll `
    /reference:System.Drawing.dll `
    "$Source"

if ($LASTEXITCODE -ne 0) { throw "编译失败，退出码 $LASTEXITCODE。" }
Write-Host "`n✅ 编译完成: $Output" -ForegroundColor Green
