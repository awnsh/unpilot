# Quick Claude installer - https://github.com/awnsh/quick-claude
# Unofficial. Not affiliated with or endorsed by Anthropic.
#
#   irm https://raw.githubusercontent.com/awnsh/quick-claude/main/install.ps1 | iex
#
# Installs per-user only (no admin): copies the popup to %LOCALAPPDATA%\QuickClaude,
# adds a launcher to your Startup folder, and starts it.

$ErrorActionPreference = 'Stop'
$RawBase = 'https://raw.githubusercontent.com/awnsh/quick-claude/main'
$InstallDir = Join-Path $env:LOCALAPPDATA 'QuickClaude'
$Target = Join-Path $InstallDir 'quick-claude.ps1'
$Startup = [Environment]::GetFolderPath('Startup')
$Launcher = Join-Path $Startup 'QuickClaude.vbs'

function Say($msg, $color = 'Gray') { Write-Host $msg -ForegroundColor $color }

if ($env:OS -ne 'Windows_NT') { throw 'Quick Claude only runs on Windows.' }
Say ''
Say '  Quick Claude' 'White'
Say '  Copilot key -> Claude, in a glass popup' 'DarkGray'
Say ''

# 1. Stop a running copy so the file can be replaced
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*quick-claude.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

# 2. Copy (from a cloned repo) or download the popup script
New-Item -ItemType Directory -Force $InstallDir | Out-Null
$local = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'src\quick-claude.ps1' } else { $null }
if ($local -and (Test-Path $local)) {
    $text = [IO.File]::ReadAllText($local, [Text.Encoding]::UTF8)
    Say '  - Using the copy in this folder'
} else {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $text = (New-Object Net.WebClient -Property @{ Encoding = [Text.Encoding]::UTF8 }).DownloadString("$RawBase/src/quick-claude.ps1")
    Say '  - Downloaded the latest version'
}
# Windows PowerShell 5.1 needs a UTF-8 BOM to read the script's symbols correctly
[IO.File]::WriteAllText($Target, $text, (New-Object Text.UTF8Encoding($true)))
Say "  - Installed to $InstallDir"

# 3. Start at sign-in, silently
$vbs = @'
' Quick Claude - starts the popup silently at sign-in.
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & sh.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\QuickClaude\quick-claude.ps1""", 0, False
'@
Set-Content -Path $Launcher -Value $vbs -Encoding ASCII
Say '  - Set to start when you sign in'

# 4. Start it now
Start-Process wscript.exe -ArgumentList "`"$Launcher`""
Say '  - Started'

# 5. Check for a signed-in Claude Code CLI
function Find-Claude {
    $own = Join-Path $env:USERPROFILE '.local\bin\claude.exe'
    if (Test-Path $own) { return $own }
    $onPath = Get-Command claude.exe -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    $roots = @()
    $roots += Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Claude-Data') -Directory -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'claude-code' }
    $roots += Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Packages') -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'LocalCache\Roaming\Claude\claude-code' }
    $roots += Join-Path $env:APPDATA 'Claude\claude-code'
    $best = $roots | Where-Object { Test-Path $_ } | ForEach-Object { Get-ChildItem $_ -Recurse -Filter claude.exe -ErrorAction SilentlyContinue } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($best) { return $best.FullName }
    return $null
}

Say ''
$claude = Find-Claude
if (-not $claude) {
    Say '  ! Claude Code is not installed. Install it, then sign in:' 'Yellow'
    Say '      irm https://claude.ai/install.ps1 | iex' 'White'
    Say '      claude auth login' 'White'
} else {
    $status = & $claude auth status 2>&1 | Out-String
    if ($status -match '"loggedIn"\s*:\s*true' -or $status -match 'Logged in') {
        Say '  Ready. Press your Copilot key and ask away.' 'Green'
    } else {
        Say '  ! One last step: sign Claude Code in to your Claude account:' 'Yellow'
        Say "      & '$claude' auth login" 'White'
    }
}
Say ''
Say '  Enter asks  |  Ctrl+Enter saves it to the Claude app  |  Esc closes' 'DarkGray'
Say ''
