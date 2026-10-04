# ===== AI CLI setup (Claude / Codex) — Gemini removed 2026-10-02 =====
$AIRoot = 'E:\AI'
# WezTerm (inside WezTerm $env:WEZTERM_PANE is set -> ai2 / aiall open panes/tabs there instead of Windows Terminal)
$WezExe = 'C:\Program Files\WezTerm\wezterm.exe'
# Machine-wide settings written by khoi-phuc.ps1: ~\.wez-ai.json = { aiRoot, wezterm } (other drive / install folder)
if (Test-Path "$HOME\.wez-ai.json") {
    $wezCfg = Get-Content "$HOME\.wez-ai.json" -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($wezCfg.aiRoot) { $AIRoot = $wezCfg.aiRoot }
    if ($wezCfg.wezterm) { $WezExe = $wezCfg.wezterm }
}

# Codex accounts: one ChatGPT account per project (own CODEX_HOME), table in ~\.codex-tai-khoan.json.
#   `codex` picks the account of the project you are in (E:\AI\<project>\...); other folders use the default ~\.codex.
#   Log in an account: cd into its project, then `codex login`.
function Get-CodexAccount {
    $f = "$HOME\.codex-tai-khoan.json"
    if (-not (Test-Path $f)) { return $null }
    $cfg = Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json
    $here = (Get-Location).Path
    if (-not $here.StartsWith($AIRoot, [StringComparison]::OrdinalIgnoreCase)) { return $null }
    $proj = ($here.Substring($AIRoot.Length).TrimStart('\') -split '\\')[0]
    $so = $cfg.duAn.$proj
    if (-not $so) { return $null }
    $cfg.taiKhoan | Where-Object { $_.so -eq $so } | Select-Object -First 1
}
# Codex: run without background daemon so it also works in an Administrator terminal
function codex {
    $tk = Get-CodexAccount
    if (-not $tk) { codex.cmd --no-daemon @args; return }
    $old = $env:CODEX_HOME
    try { $env:CODEX_HOME = $tk.thuMuc; Write-Host "  Codex: $($tk.ten) ($($tk.gmail))" -ForegroundColor DarkGray; codex.cmd --no-daemon @args }
    finally { $env:CODEX_HOME = $old }
}
# codextk : show the Codex account table (project -> account, logged in or not)
function codextk {
    $f = "$HOME\.codex-tai-khoan.json"
    if (-not (Test-Path $f)) { Write-Host 'Chua co ~\.codex-tai-khoan.json' -ForegroundColor Yellow; return }
    $cfg = Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($t in $cfg.taiKhoan) {
        $proj = ($cfg.duAn.PSObject.Properties | Where-Object { $_.Value -eq $t.so }).Name -join ', '
        $ok = if (Test-Path (Join-Path $t.thuMuc 'auth.json')) { 'da dang nhap' } else { 'CHUA dang nhap' }
        Write-Host ("  {0}) {1,-28} {2,-26} du an: {3,-10} {4}" -f $t.so, $t.ten, $t.gmail, $proj, $ok)
    }
    Write-Host '  Dang nhap lai: vao thu muc du an (vd cd E:\AI\Sino) roi go: codex login' -ForegroundColor DarkGray
}

# deepseek [args] : Claude Code running on DeepSeek (04/10/2026). Key = user env var DEEPSEEK_API_KEY (never stored in a file).
#   Model names per api-docs.deepseek.com/quick_start/agent_integrations/claude_code. Env vars are restored after exit.
function deepseek {
    $k = [Environment]::GetEnvironmentVariable('DEEPSEEK_API_KEY', 'User')
    if (-not $k) { Write-Host 'Chua co DEEPSEEK_API_KEY (xem huong dan trong So tay / hoi Tong quan)' -ForegroundColor Yellow; return }
    $vars = [ordered]@{
        ANTHROPIC_BASE_URL = 'https://api.deepseek.com/anthropic'; ANTHROPIC_AUTH_TOKEN = $k; ANTHROPIC_API_KEY = $null
        ANTHROPIC_MODEL = 'deepseek-flash[1m]'; ANTHROPIC_DEFAULT_OPUS_MODEL = 'deepseek-flash[1m]'; ANTHROPIC_DEFAULT_SONNET_MODEL = 'deepseek-flash[1m]'
        ANTHROPIC_DEFAULT_HAIKU_MODEL = 'deepseek-flash'; CLAUDE_CODE_SUBAGENT_MODEL = 'deepseek-flash'; CLAUDE_CODE_AUTO_COMPACT_WINDOW = '786432'
    }
    $old = @{}
    foreach ($n in $vars.Keys) { $old[$n] = [Environment]::GetEnvironmentVariable($n, 'Process'); [Environment]::SetEnvironmentVariable($n, $vars[$n], 'Process') }
    try { Write-Host '  Claude Code · DeepSeek (deepseek-flash)' -ForegroundColor DarkGray; claude @args }
    finally { foreach ($n in $old.Keys) { [Environment]::SetEnvironmentVariable($n, $old[$n], 'Process') } }
}

# ai2 [path] [-Yolo] : open 2 side-by-side panes Claude | Codex in a folder  (ai3 = old name, still works)
#   -Yolo : let both AIs run commands without asking for approval
function ai2 {
    param([string]$Path = (Get-Location).Path, [switch]$Yolo)
    $p = (Resolve-Path $Path).Path
    if ($Yolo) {
        $c = 'claudeRC --dangerously-skip-permissions'
        $o = 'codex --dangerously-bypass-approvals-and-sandbox'
    } else {
        $c = 'claudeRC'; $o = 'codex'
    }
    if ($env:WEZTERM_PANE) {
        # WezTerm: this pane becomes Claude, Codex opens as an equal column to its right
        Set-Location $p
        & $WezExe cli --no-auto-start split-pane --pane-id $env:WEZTERM_PANE --right --percent 50 --cwd "$p" -- powershell -NoExit -Command $o | Out-Null
        Invoke-Expression $c
        return
    }
    wt -w 0 nt -d "$p" --title Claude powershell -NoExit -Command $c `; sp -V -s 0.5 -d "$p" --title Codex powershell -NoExit -Command $o
}
Set-Alias ai3 ai2

# ai : menu to pick which AI to start in the current folder.
#   To add a new AI, add one line to $AITools (Key = what you type, Cmd = its command).
$AITools = [ordered]@{
    '1' = @{ Name = 'Claude'; Cmd = 'claude' }
    '2' = @{ Name = 'Codex (GPT)'; Cmd = 'codex' }
    '3' = @{ Name = 'Grok'; Cmd = 'grok' }
}
# Get-AIProjects : folders in E:\AI ordered as the agent-team tree in Hion\cay-du-an.json
#   (Tong quan -> PM du an -> cong cu); folders not in the tree go last, under "Khac".
function Get-AIProjects {
    $dirs = @(Get-ChildItem $AIRoot -Directory | Sort-Object Name)
    $tree = @()
    $f = Join-Path $AIRoot 'Hion\cay-du-an.json'
    if (Test-Path $f) { try { $tree = @((Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json).cay) } catch {} }
    $out = @()
    foreach ($n in $tree) {
        $d = $dirs | Where-Object { $_.Name -eq $n.ten } | Select-Object -First 1
        if ($d) { $out += [pscustomobject]@{ Dir = $d; Level = [int]$n.cap; Label = $n.nhan } }
    }
    foreach ($d in $dirs) {
        if ($out.Dir.Name -notcontains $d.Name) { $out += [pscustomobject]@{ Dir = $d; Level = -1; Label = '' } }
    }
    $out
}
function ai {
    # Step 0 (chi trong WezTerm, khi co bo cuc da luu): menu cu hay mo lai tat ca phien dang lam do
    $saved = @('bo-cuc-phien-truoc.json', 'bo-cuc-luu.json', 'bo-cuc-tu-luu.json') |
        ForEach-Object { Join-Path $env:LOCALAPPDATA "wez-ai\$_" } | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($env:WEZTERM_PANE -and $saved) {
        $info = ''
        try {
            $d = Get-Content $saved -Raw -Encoding UTF8 | ConvertFrom-Json
            $n = 0; foreach ($t in $d.tabs) { $n += @($t.panes).Count }
            $info = "  ({0} tab, {1} o - luu luc {2})" -f @($d.tabs).Count, $n, ([DateTimeOffset]::FromUnixTimeSeconds([int64]$d.t).LocalDateTime.ToString('HH:mm dd/MM'))
        } catch {}
        Write-Host ""
        Write-Host "  BAT DAU" -ForegroundColor Cyan
        Write-Host "   1) Chon du an + AI (menu nhu cu)"
        Write-Host "   2) Mo lai tat ca phien dang lam do$info" -ForegroundColor Green
        $s = (Read-Host "  Chon (Enter = 1)").Trim()
        if ($s -eq '2') {
            # bao WezTerm (su kien user-var-changed trong ~\.wezterm.lua) mo lai bo cuc, roi dong o nay
            $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('mo-lai'))
            [Console]::Write("$([char]27)]1337;SetUserVar=wez_ai=$b64$([char]7)")
            Write-Host "  Dang mo lai cac phien..." -ForegroundColor Green
            return
        }
    }

    # Step 1: pick a project (every folder in E:\AI, in agent-team tree order)
    $items = @(Get-AIProjects)
    $projects = @($items.Dir)
    Write-Host ""
    Write-Host "  DU AN  (Enter = giu thu muc hien tai: $((Get-Location).Path))" -ForegroundColor Cyan
    $other = $false
    for ($i = 0; $i -lt $items.Count; $i++) {
        $it = $items[$i]
        $num = "{0,2})" -f ($i + 1)
        $isLastChild = $it.Level -eq 1 -and ($i -eq $items.Count - 1 -or $items[$i + 1].Level -ne 1)
        switch ($it.Level) {
            0 { Write-Host ("  {0} {1,-12} {2}" -f $num, $it.Dir.Name, $it.Label) -ForegroundColor Yellow }
            1 { $branch = if ($isLastChild) { '`--' } else { '|--' }
                Write-Host ("      {0} {1} {2,-10} {3}" -f $branch, $num, $it.Dir.Name, $it.Label) }
            default { if (-not $other) { Write-Host "  Khac:" -ForegroundColor DarkGray; $other = $true }
                      Write-Host ("  {0} {1}" -f $num, $it.Dir.Name) -ForegroundColor DarkGray }
        }
    }
    $p = (Read-Host "  Chon du an").Trim()
    if ($p) {
        $n = 0
        if ([int]::TryParse($p, [ref]$n) -and $n -ge 1 -and $n -le $projects.Count) {
            Set-Location $projects[$n - 1].FullName
        } else { Write-Host "  Khong co du an '$p'" -ForegroundColor Yellow; return }
    }

    # Step 2: pick an AI
    Write-Host ""
    Write-Host "  AI  -  $((Get-Location).Path)" -ForegroundColor Cyan
    foreach ($k in $AITools.Keys) {
        $t = $AITools[$k]
        if (Get-Command $t.Cmd -ErrorAction SilentlyContinue) {
            Write-Host "   $k) $($t.Name)"
        } else {
            Write-Host "   $k) $($t.Name)  (chua cai)" -ForegroundColor DarkGray
        }
    }
    Write-Host "   a) Ca 2: Claude | Codex"
    Write-Host "   0) Khong mo AI, chi dung PowerShell" -ForegroundColor DarkGray
    $c = (Read-Host "  Chon AI (Enter = Claude)").Trim().ToLower()
    if (-not $c) { $c = '1' }
    if ($c -eq '0') { return }
    if ($c -eq 'a') { ai2; return }
    if (-not $AITools.Contains($c)) { Write-Host "  Khong co lua chon '$c'" -ForegroundColor Yellow; return }
    $t = $AITools[$c]
    if (-not (Get-Command $t.Cmd -ErrorAction SilentlyContinue)) {
        Write-Host "  $($t.Name) chua duoc cai. Hoi Claude de cai them." -ForegroundColor Yellow
        return
    }
    if ($t.Cmd -eq 'claude') { claudeRC } else { & $t.Cmd }
}

# claudeRC : start Claude with Remote Control on, session named after the current folder
#   (so it shows up by project name in the Claude phone app / claude.ai)
function claudeRC { claude --remote-control (Split-Path -Leaf (Get-Location).Path) @args }

# aiall : open one tab per project in E:\AI, each running Claude with Remote Control
#   -> on the phone you can switch between all projects
function aiall {
    foreach ($d in Get-ChildItem $AIRoot -Directory | Sort-Object Name) {
        if ($env:WEZTERM_PANE) {
            # WezTerm: one new tab per project, tab titled with the project name
            $id = & $WezExe cli --no-auto-start spawn --cwd "$($d.FullName)" -- powershell -NoExit -Command claudeRC
            & $WezExe cli set-tab-title --pane-id $id.Trim() $d.Name
            continue
        }
        wt -w 0 nt -d "$($d.FullName)" --title $d.Name powershell -NoExit -Command claudeRC
        Start-Sleep -Milliseconds 700
    }
}

# Project shortcuts: go to the project and start Claude.  Add -All to open Claude | Codex instead.
function Enter-AIProject {
    param([string]$Name, [switch]$All)
    $dir = Join-Path $AIRoot $Name
    Set-Location $dir
    if ($All) { ai2 $dir } else { claudeRC }
}
function hion { param([switch]$All) Enter-AIProject 'Hion'    -All:$All }
function sino { param([switch]$All) Enter-AIProject 'Sino'    -All:$All }
function cool { param([switch]$All) Enter-AIProject 'Coolguy' -All:$All }
function bot  { param([switch]$All) Enter-AIProject 'Chatbot' -All:$All }

# newproj <name> : create (or complete) E:\AI\<name> with git + shared AI instructions, then cd into it
#   Existing files are never overwritten; only missing ones are added.
function newproj {
    param([Parameter(Mandatory)][string]$Name)
    $dir = Join-Path $AIRoot $Name
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $utf8 = New-Object System.Text.UTF8Encoding $false
    $files = @{
        'AGENTS.md' = @"
# $Name

## Overview
<What this project does>

## Commands
- Run:  <command>
- Test: <command>

## Conventions
- Reply to the user in Vietnamese.
- Keep changes small; do not touch files outside this folder.
"@
        'CLAUDE.md'             = "@AGENTS.md`n"
        '.gitignore'            = "node_modules/`n.env`n__pycache__/`n.venv/`n.claude/settings.local.json`n"
    }
    # Có bộ mẫu của wezterm-ai thì dùng: AGENTS.md ghi sẵn vai Manager + file tiến độ để bàn giao
    $mau = Join-Path $AIRoot 'Hion\cai-dat\mau\du-an'
    if (Test-Path "$mau\AGENTS.md") {
        $thay = { param($s) $s.Replace('{{TEN}}', $Name).Replace('{{ten}}', $Name.ToLower()).Replace('{{AIROOT}}', $AIRoot) }
        $files['AGENTS.md'] = & $thay (Get-Content "$mau\AGENTS.md" -Raw -Encoding UTF8)
        $files["tien-do-$($Name.ToLower()).md"] = & $thay (Get-Content "$mau\tien-do.md" -Raw -Encoding UTF8)
    }
    foreach ($k in $files.Keys) {
        $f = Join-Path $dir $k
        if (Test-Path $f) { Write-Host "  keep  $k" -ForegroundColor DarkGray; continue }
        [System.IO.File]::WriteAllText($f, $files[$k], $utf8)
        Write-Host "  added $k" -ForegroundColor Green
    }
    if (-not (Test-Path (Join-Path $dir '.git'))) { git -C $dir init -q; Write-Host "  added git" -ForegroundColor Green }
    Set-Location $dir
    Write-Host "Ready: $dir  ->  run 'ai2' to open Claude | Codex" -ForegroundColor Green
}
