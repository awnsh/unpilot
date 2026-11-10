# Quick Claude uninstaller - https://github.com/awnsh/quick-claude
#
#   irm https://raw.githubusercontent.com/awnsh/quick-claude/main/uninstall.ps1 | iex

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*quick-claude.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Remove-Item (Join-Path ([Environment]::GetFolderPath('Startup')) 'QuickClaude.vbs') -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $env:LOCALAPPDATA 'QuickClaude') -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host '  Quick Claude removed. Your Copilot key is back to normal.' -ForegroundColor Green
Write-Host ''
