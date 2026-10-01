# ===== AI CLI setup (Claude / Codex / Gemini) =====
$AIRoot = 'E:\AI'
# WezTerm (inside WezTerm $env:WEZTERM_PANE is set -> ai3 / aiall open panes/tabs there instead of Windows Terminal)
$WezExe = 'C:\Program Files\WezTerm\wezterm.exe'

# Codex: run without background daemon so it also works in an Administrator terminal
function codex { codex.cmd --no-daemon @args }

# ai3 [path] [-Yolo] : open 3 side-by-side panes Claude | Codex | Gemini in a folder
#   -Yolo : let all 3 AIs run commands without asking for approval
function ai3 {
    param([string]$Path = (Get-Location).Path, [switch]$Yolo)
    $p = (Resolve-Path $Path).Path
    if ($Yolo) {
        $c = 'claudeRC --dangerously-skip-permissions'
        $o = 'codex --dangerously-bypass-approvals-and-sandbox'
        $g = 'gemini --yolo'
    } else {
        $c = 'claudeRC'; $o = 'codex'; $g = 'gemini'
    }
    if ($env:WEZTERM_PANE) {
        # WezTerm: this pane becomes Claude, Codex and Gemini open as equal columns to its right
        Set-Location $p
        $mid = & $WezExe cli split-pane --pane-id $env:WEZTERM_PANE --right --percent 67 --cwd "$p" -- powershell -NoExit -Command $o
        & $WezExe cli split-pane --pane-id $mid.Trim() --right --percent 50 --cwd "$p" -- powershell -NoExit -Command $g | Out-Null
        Invoke-Expression $c
        return
    }
    wt -w 0 nt -d "$p" --title Claude powershell -NoExit -Command $c `; sp -V -s 0.66 -d "$p" --title Codex powershell -NoExit -Command $o `; sp -V -s 0.5 -d "$p" --title Gemini powershell -NoExit -Command $g
}

# ai : menu to pick which AI to start in the current folder.
#   To add a new AI, add one line to $AITools (Key = what you type, Cmd = its command).
$AITools = [ordered]@{
    '1' = @{ Name = 'Claude'; Cmd = 'claude' }
    '2' = @{ Name = 'Codex (GPT)'; Cmd = 'codex' }
    '3' = @{ Name = 'Gemini'; Cmd = 'gemini' }
    '4' = @{ Name = 'Grok'; Cmd = 'grok' }
}
function ai {
    # Step 1: pick a project (every folder in E:\AI is listed automatically)
    $projects = @(Get-ChildItem $AIRoot -Directory | Sort-Object Name)
    Write-Host ""
    Write-Host "  DU AN  (Enter = giu thu muc hien tai: $((Get-Location).Path))" -ForegroundColor Cyan
    for ($i = 0; $i -lt $projects.Count; $i++) { Write-Host ("   {0}) {1}" -f ($i + 1), $projects[$i].Name) }
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
    Write-Host "   a) Ca 3: Claude | Codex | Gemini"
    Write-Host "   0) Khong mo AI, chi dung PowerShell" -ForegroundColor DarkGray
    $c = (Read-Host "  Chon AI (Enter = Claude)").Trim().ToLower()
    if (-not $c) { $c = '1' }
    if ($c -eq '0') { return }
    if ($c -eq 'a') { ai3; return }
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
            $id = & $WezExe cli spawn --cwd "$($d.FullName)" -- powershell -NoExit -Command claudeRC
            & $WezExe cli set-tab-title --pane-id $id.Trim() $d.Name
            continue
        }
        wt -w 0 nt -d "$($d.FullName)" --title $d.Name powershell -NoExit -Command claudeRC
        Start-Sleep -Milliseconds 700
    }
}

# Project shortcuts: go to the project and start Claude.  Add -All to open Claude | Codex | Gemini instead.
function Enter-AIProject {
    param([string]$Name, [switch]$All)
    $dir = Join-Path $AIRoot $Name
    Set-Location $dir
    if ($All) { ai3 $dir } else { claudeRC }
}
function hub  { param([switch]$All) Enter-AIProject '_Hub'    -All:$All }
function sino { param([switch]$All) Enter-AIProject 'Sino'    -All:$All }
function cool { param([switch]$All) Enter-AIProject 'Coolguy' -All:$All }
function bot  { param([switch]$All) Enter-AIProject 'Chatbot' -All:$All }

# newproj <name> : create (or complete) E:\AI\<name> with git + shared AI instructions, then cd into it
#   Existing files are never overwritten; only missing ones are added.
function newproj {
    param([Parameter(Mandatory)][string]$Name)
    $dir = Join-Path $AIRoot $Name
    New-Item -ItemType Directory -Path (Join-Path $dir '.gemini') -Force | Out-Null
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
        '.gemini\settings.json' = "{ `"context`": { `"fileName`": [`"AGENTS.md`", `"GEMINI.md`"] } }`n"
        '.gitignore'            = "node_modules/`n.env`n__pycache__/`n.venv/`n.claude/settings.local.json`n"
    }
    foreach ($k in $files.Keys) {
        $f = Join-Path $dir $k
        if (Test-Path $f) { Write-Host "  keep  $k" -ForegroundColor DarkGray; continue }
        [System.IO.File]::WriteAllText($f, $files[$k], $utf8)
        Write-Host "  added $k" -ForegroundColor Green
    }
    if (-not (Test-Path (Join-Path $dir '.git'))) { git -C $dir init -q; Write-Host "  added git" -ForegroundColor Green }
    Set-Location $dir
    Write-Host "Ready: $dir  ->  run 'ai3' to open Claude | Codex | Gemini" -ForegroundColor Green
}
