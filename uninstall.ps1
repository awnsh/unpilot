# Unpilot uninstaller - https://github.com/awnsh/unpilot
#
#   irm https://raw.githubusercontent.com/awnsh/unpilot/main/uninstall.ps1 | iex

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*unpilot.ps1*' -or $_.CommandLine -like '*quick-claude.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

$startup = [Environment]::GetFolderPath('Startup')
foreach ($name in 'Unpilot.vbs', 'QuickClaude.vbs') { Remove-Item (Join-Path $startup $name) -Force -ErrorAction SilentlyContinue }
foreach ($dir in 'Unpilot', 'QuickClaude') { Remove-Item (Join-Path $env:LOCALAPPDATA $dir) -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host ''
Write-Host '  Unpilot removed. Your Copilot key opens Copilot again.' -ForegroundColor Green
Write-Host ''
