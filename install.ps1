# Unpilot installer - https://github.com/awnsh/unpilot
# Not affiliated with Microsoft or Anthropic.
#
#   irm https://raw.githubusercontent.com/awnsh/unpilot/main/install.ps1 | iex
#
# To make the key do something else, build a command at https://awnsh.github.io/unpilot
# (it sets $env:COPILOT_KEY first). Installs per-user only (no admin): copies the script to
# %LOCALAPPDATA%\Unpilot, adds a launcher to your Startup folder, and starts it.

$ErrorActionPreference = 'Stop'
$RawBase = 'https://raw.githubusercontent.com/awnsh/unpilot/main'
$InstallDir = Join-Path $env:LOCALAPPDATA 'Unpilot'
$Target = Join-Path $InstallDir 'unpilot.ps1'
$Startup = [Environment]::GetFolderPath('Startup')
$Launcher = Join-Path $Startup 'Unpilot.vbs'
$OldDir = Join-Path $env:LOCALAPPDATA 'QuickClaude'      # from before the rename

function Say($msg, $color = 'Gray') { Write-Host $msg -ForegroundColor $color }

if ($env:OS -ne 'Windows_NT') { throw 'Unpilot only runs on Windows.' }
Say ''
Say '  Unpilot' 'White'
Say '  Make the Copilot key do anything' 'DarkGray'
Say ''

# 1. Stop a running copy so the file can be replaced (including the old Quick Claude name)
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*unpilot.ps1*' -or $_.CommandLine -like '*quick-claude.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

# 2. Copy (from a cloned repo) or download the script
New-Item -ItemType Directory -Force $InstallDir | Out-Null
if ((Test-Path $OldDir) -and -not (Test-Path (Join-Path $InstallDir 'config.json')) -and (Test-Path (Join-Path $OldDir 'config.json'))) {
    Copy-Item (Join-Path $OldDir 'config.json') $InstallDir    # keep your old choice
}
Remove-Item (Join-Path $Startup 'QuickClaude.vbs') -Force -ErrorAction SilentlyContinue
Remove-Item $OldDir -Recurse -Force -ErrorAction SilentlyContinue
$local = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'src\unpilot.ps1' } else { $null }
if ($local -and (Test-Path $local)) {
    $text = [IO.File]::ReadAllText($local, [Text.Encoding]::UTF8)
    Say '  - Using the copy in this folder'
} else {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $text = (New-Object Net.WebClient -Property @{ Encoding = [Text.Encoding]::UTF8 }).DownloadString("$RawBase/src/unpilot.ps1")
    Say '  - Downloaded the latest version'
}
# Windows PowerShell 5.1 needs a UTF-8 BOM to read the script's symbols correctly
[IO.File]::WriteAllText($Target, $text, (New-Object Text.UTF8Encoding($true)))
Say "  - Installed to $InstallDir"

# 2b. What should the key do? The website passes a choice in $env:COPILOT_KEY (base64 JSON).
#     No choice and no saved config = the Claude popup. Re-running without one keeps your current setup.
$ConfigPath = Join-Path $InstallDir 'config.json'
$valid = 'claude', 'remap', 'app', 'url', 'keys', 'text', 'command'
if ($env:COPILOT_KEY) {
    try {
        $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($env:COPILOT_KEY.Trim()))
        $cfg = $json | ConvertFrom-Json
        if ($valid -notcontains [string]$cfg.action) { throw "unknown action '$($cfg.action)'" }
        [IO.File]::WriteAllText($ConfigPath, $json, (New-Object Text.UTF8Encoding($false)))
    } catch {
        Say "  ! Couldn't read your key choice ($($_.Exception.Message)). Keeping the current setup." 'Yellow'
    }
    Remove-Item Env:COPILOT_KEY -ErrorAction SilentlyContinue
}
if (-not (Test-Path $ConfigPath)) {
    [IO.File]::WriteAllText($ConfigPath, '{"action":"claude","target":"","label":"Open the Claude popup"}', (New-Object Text.UTF8Encoding($false)))
}
$cfg = [IO.File]::ReadAllText($ConfigPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
$label = if ($cfg.label) { $cfg.label } else { "$($cfg.action) $($cfg.target)".Trim() }
Say "  - Copilot key will: $label"

# 3. Start at sign-in, silently
$vbs = @'
' Unpilot - starts the Copilot key remap silently at sign-in.
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & sh.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\Unpilot\unpilot.ps1""", 0, False
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
if ($cfg.action -ne 'claude') {
    Say "  Ready. Press your Copilot key: it will $($label.Substring(0,1).ToLower() + $label.Substring(1))." 'Green'
    Say ''
    return
}
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
