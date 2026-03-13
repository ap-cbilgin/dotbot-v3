#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Package .bot framework files back to the dotbot source repo's profiles/default directory.

.DESCRIPTION
    When developing dotbot within a project, changes accumulate in the local .bot/ directory.
    This script copies framework files back to the dotbot source repo's profiles/default/
    directory, which is the template used by 'dotbot init' to initialize new projects.

    The mapping is:
      .bot/{path}  -->  {target}/profiles/default/{path}

    Framework files (systems, prompts, hooks, defaults, root scripts) are copied.
    Workspace content (tasks, ADRs, sessions, plans, product docs) is excluded — only
    the empty directory structure in profiles/default/workspace/ is preserved.

    Optionally syncs IDE-side agent/skill edits back into .bot/prompts/ first (-SyncFromIDE).

.PARAMETER Target
    Path to the dotbot source repo root (e.g., C:\dotbot-install).
    Must contain a profiles/default/ directory.

.PARAMETER Archive
    Create a .zip archive instead of copying to a directory.

.PARAMETER SyncFromIDE
    Before packaging, sync any agent/skill changes from .claude/ back into .bot/prompts/.
    Useful if agents or skills were edited directly in the IDE directory.

.PARAMETER DryRun
    Show what would be copied without actually copying anything.

.PARAMETER Force
    Overwrite all files without checking hashes.

.EXAMPLE
    # Package back to dotbot source repo
    .bot\package.ps1 -Target C:\dotbot-install

.EXAMPLE
    # Preview changes
    .bot\package.ps1 -Target C:\dotbot-install -DryRun

.EXAMPLE
    # Sync IDE changes first, then package
    .bot\package.ps1 -Target C:\dotbot-install -SyncFromIDE

.EXAMPLE
    # Create a distributable archive
    .bot\package.ps1 -Archive
#>

[CmdletBinding(DefaultParameterSetName = 'Directory')]
param(
    [Parameter(Position = 0, ParameterSetName = 'Directory')]
    [string]$Target,

    [Parameter(ParameterSetName = 'Archive')]
    [switch]$Archive,

    [switch]$SyncFromIDE,
    [switch]$DryRun,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$BotDir = $PSScriptRoot
$ProjectRoot = Split-Path -Parent $BotDir

# --- Configuration ---

# Framework directories to INCLUDE (copied to profiles/default/)
$FrameworkDirs = @(
    "systems"
    "prompts"
    "hooks"
    "defaults"
)

# Root-level framework files to INCLUDE
$FrameworkRootFiles = @(
    "go.ps1"
    "init.ps1"
    "package.ps1"
    "README.md"
    ".gitignore"
)

# Workspace directories to preserve as empty structure (with .gitkeep)
$WorkspaceStructure = @(
    "workspace\adrs\accepted"
    "workspace\adrs\deprecated"
    "workspace\adrs\proposed"
    "workspace\adrs\superseded"
    "workspace\feedback\pending"
    "workspace\feedback\applied"
    "workspace\feedback\archived"
    "workspace\pilot"
    "workspace\plans"
    "workspace\product"
    "workspace\reports"
    "workspace\sessions\runs"
    "workspace\sessions\history"
    "workspace\tasks\todo"
    "workspace\tasks\analysing"
    "workspace\tasks\analysed"
    "workspace\tasks\needs-input"
    "workspace\tasks\in-progress"
    "workspace\tasks\done"
    "workspace\tasks\split"
    "workspace\tasks\skipped"
    "workspace\tasks\cancelled"
)

# Workspace files to include (templates, samples, etc.)
$WorkspaceIncludePatterns = @(
    "workspace\feedback\TEMPLATE.json"
    "workspace\tasks\samples\*"
)

# File patterns to always EXCLUDE
$ExcludeFilePatterns = @(
    "*.log"
    "*.jsonl"
    "*.tmp"
)

# ---

function Write-Status {
    param([string]$Message, [string]$Color = "Cyan")
    Write-Host "  $Message" -ForegroundColor $Color
}

# --- Sync from IDE ---

if ($SyncFromIDE) {
    Write-Host ""
    Write-Status "Syncing IDE agent/skill changes back to .bot/prompts/..." "Yellow"

    $claudeDir = Join-Path $ProjectRoot ".claude"
    $sourceAgents = Join-Path $BotDir "prompts\agents"
    $sourceSkills = Join-Path $BotDir "prompts\skills"

    $syncCount = 0

    if (Test-Path (Join-Path $claudeDir "agents")) {
        Get-ChildItem (Join-Path $claudeDir "agents") -Directory | ForEach-Object {
            $agentMd = Join-Path $_.FullName "AGENT.md"
            $targetMd = Join-Path $sourceAgents "$($_.Name)\AGENT.md"

            if ((Test-Path $agentMd) -and (Test-Path $targetMd)) {
                $ideContent = Get-Content $agentMd -Raw
                $srcContent = Get-Content $targetMd -Raw

                if ($ideContent -ne $srcContent) {
                    if ($DryRun) {
                        Write-Host "    [SYNC] agent: $($_.Name)" -ForegroundColor Yellow
                    } else {
                        Copy-Item -Path $agentMd -Destination $targetMd -Force
                        Write-Host "    Synced agent: $($_.Name)" -ForegroundColor Green
                    }
                    $syncCount++
                }
            }
        }
    }

    if (Test-Path (Join-Path $claudeDir "skills")) {
        Get-ChildItem (Join-Path $claudeDir "skills") -Directory | ForEach-Object {
            $skillMd = Join-Path $_.FullName "SKILL.md"
            $targetMd = Join-Path $sourceSkills "$($_.Name)\SKILL.md"

            if ((Test-Path $skillMd) -and (Test-Path $targetMd)) {
                $ideContent = Get-Content $skillMd -Raw
                $srcContent = Get-Content $targetMd -Raw

                if ($ideContent -ne $srcContent) {
                    if ($DryRun) {
                        Write-Host "    [SYNC] skill: $($_.Name)" -ForegroundColor Yellow
                    } else {
                        Copy-Item -Path $skillMd -Destination $targetMd -Force
                        Write-Host "    Synced skill: $($_.Name)" -ForegroundColor Green
                    }
                    $syncCount++
                }
            }
        }
    }

    if ($syncCount -eq 0) {
        Write-Status "  No IDE changes to sync" "DarkGray"
    }
    Write-Host ""
}

# --- Collect framework files ---

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Blue
Write-Host ""
Write-Host "    D O T B O T   v3" -ForegroundColor Blue
Write-Host "    Package Framework Files" -ForegroundColor Yellow
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Blue
Write-Host ""

Write-Status "Collecting framework files from .bot/..."

$frameworkFiles = @()

# Collect files from framework directories
foreach ($dir in $FrameworkDirs) {
    $dirPath = Join-Path $BotDir $dir
    if (Test-Path $dirPath) {
        Get-ChildItem -Path $dirPath -Recurse -File | ForEach-Object {
            $excluded = $false
            foreach ($pattern in $ExcludeFilePatterns) {
                if ($_.Name -like $pattern) { $excluded = $true; break }
            }
            if (-not $excluded) {
                $frameworkFiles += $_
            }
        }
    }
}

# Collect root-level framework files
foreach ($fileName in $FrameworkRootFiles) {
    $filePath = Join-Path $BotDir $fileName
    if (Test-Path $filePath) {
        $frameworkFiles += Get-Item $filePath
    }
}

# Collect workspace template/sample files
foreach ($pattern in $WorkspaceIncludePatterns) {
    $fullPattern = Join-Path $BotDir $pattern
    $matched = Get-Item $fullPattern -ErrorAction SilentlyContinue
    if ($matched) {
        $frameworkFiles += @($matched | Where-Object { -not $_.PSIsContainer })
    }
}

$fileCount = $frameworkFiles.Count
Write-Status "Found $fileCount framework files" "White"
Write-Host ""

# --- Package ---

if ($Archive) {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $archiveName = "dotbot-package-$timestamp.zip"
    $archivePath = Join-Path $ProjectRoot $archiveName

    if ($DryRun) {
        Write-Status "Would create archive: $archiveName" "Yellow"
        Write-Status "Contents ($fileCount files):" "White"
        $frameworkFiles | ForEach-Object {
            $rel = $_.FullName.Substring($BotDir.Length + 1).Replace("\", "/")
            Write-Host "    profiles/default/$rel" -ForegroundColor DarkGray
        }
    } else {
        $stagingDir = Join-Path ([System.IO.Path]::GetTempPath()) "dotbot-package-$timestamp"
        $stagingProfileDir = Join-Path $stagingDir "profiles\default"

        try {
            # Copy framework files
            foreach ($file in $frameworkFiles) {
                $relativePath = $file.FullName.Substring($BotDir.Length + 1)
                $destFile = Join-Path $stagingProfileDir $relativePath
                $destDir = Split-Path -Parent $destFile

                if (-not (Test-Path $destDir)) {
                    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                }
                Copy-Item -Path $file.FullName -Destination $destFile -Force
            }

            # Create empty workspace structure
            foreach ($wsDir in $WorkspaceStructure) {
                $destDir = Join-Path $stagingProfileDir $wsDir
                if (-not (Test-Path $destDir)) {
                    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                }
            }

            # Create zip
            if (Test-Path $archivePath) { Remove-Item $archivePath -Force }
            Compress-Archive -Path "$stagingDir\*" -DestinationPath $archivePath -Force

            Write-Host ""
            Write-Status "Archive created: $archiveName" "Green"
            Write-Status "Size: $([math]::Round((Get-Item $archivePath).Length / 1KB, 1)) KB" "White"
        } finally {
            if (Test-Path $stagingDir) {
                Remove-Item -Path $stagingDir -Recurse -Force
            }
        }
    }
} else {
    # Directory mode: copy to target's profiles/default/
    if (-not $Target) {
        Write-Host "  ERROR: -Target directory is required (or use -Archive for zip output)" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Usage:" -ForegroundColor White
        Write-Host "    .bot\package.ps1 -Target C:\dotbot-install" -ForegroundColor DarkGray
        Write-Host "    .bot\package.ps1 -Target C:\dotbot-install -DryRun" -ForegroundColor DarkGray
        Write-Host "    .bot\package.ps1 -Archive" -ForegroundColor DarkGray
        Write-Host ""
        exit 1
    }

    # Validate target is a dotbot source repo
    $targetProfileDir = Join-Path $Target "profiles\default"
    if (-not (Test-Path (Join-Path $Target "profiles"))) {
        Write-Host "  ERROR: Target does not look like a dotbot source repo" -ForegroundColor Red
        Write-Host "  Expected to find: $Target\profiles\" -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }

    if (-not (Test-Path $targetProfileDir)) {
        if ($DryRun) {
            Write-Status "Would create: $targetProfileDir" "Yellow"
        } else {
            New-Item -ItemType Directory -Path $targetProfileDir -Force | Out-Null
        }
    }

    # Track stats
    $copied = 0
    $skipped = 0
    $updated = 0

    if ($DryRun) {
        Write-Status "Dry run — changes that would be applied:" "Yellow"
    } else {
        Write-Status "Copying to: $targetProfileDir" "White"
    }
    Write-Host ""

    foreach ($file in $frameworkFiles) {
        $relativePath = $file.FullName.Substring($BotDir.Length + 1)
        $destFile = Join-Path $targetProfileDir $relativePath
        $destDir = Split-Path -Parent $destFile
        $displayPath = "profiles/default/$($relativePath.Replace('\', '/'))"

        if ($DryRun) {
            if (Test-Path $destFile) {
                $srcHash = (Get-FileHash $file.FullName -Algorithm MD5).Hash
                $dstHash = (Get-FileHash $destFile -Algorithm MD5).Hash
                if ($srcHash -ne $dstHash) {
                    Write-Host "    [UPDATE] " -ForegroundColor Yellow -NoNewline
                    Write-Host $displayPath -ForegroundColor White
                    $updated++
                } else {
                    $skipped++
                }
            } else {
                Write-Host "    [NEW]    " -ForegroundColor Green -NoNewline
                Write-Host $displayPath -ForegroundColor White
                $copied++
            }
        } else {
            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }

            $shouldCopy = $true
            if ((Test-Path $destFile) -and -not $Force) {
                $srcHash = (Get-FileHash $file.FullName -Algorithm MD5).Hash
                $dstHash = (Get-FileHash $destFile -Algorithm MD5).Hash
                if ($srcHash -eq $dstHash) {
                    $shouldCopy = $false
                    $skipped++
                } else {
                    $updated++
                }
            } else {
                $copied++
            }

            if ($shouldCopy) {
                Copy-Item -Path $file.FullName -Destination $destFile -Force
            }
        }
    }

    # Ensure empty workspace directories exist in target
    $wsCreated = 0
    foreach ($wsDir in $WorkspaceStructure) {
        $destDir = Join-Path $targetProfileDir $wsDir
        if (-not (Test-Path $destDir)) {
            if (-not $DryRun) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
            $wsCreated++
        }
    }

    # Detect files in target that no longer exist in source (stale files)
    $staleFiles = @()
    foreach ($dir in $FrameworkDirs) {
        $targetDir = Join-Path $targetProfileDir $dir
        if (Test-Path $targetDir) {
            Get-ChildItem -Path $targetDir -Recurse -File | ForEach-Object {
                $targetRelPath = $_.FullName.Substring($targetProfileDir.Length + 1)
                $sourceFile = Join-Path $BotDir $targetRelPath
                if (-not (Test-Path $sourceFile)) {
                    $staleFiles += $targetRelPath
                }
            }
        }
    }

    Write-Host ""
    Write-Host "  ─────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    Write-Status "SUMMARY" "Blue"
    Write-Host ""
    if ($copied -gt 0)    { Write-Status "  New files:     $copied" "Green" }
    if ($updated -gt 0)   { Write-Status "  Updated:       $updated" "Yellow" }
    if ($skipped -gt 0)   { Write-Status "  Unchanged:     $skipped" "DarkGray" }
    if ($wsCreated -gt 0) { Write-Status "  Dirs created:  $wsCreated" "Green" }
    Write-Status "  Total files:   $fileCount" "White"

    if ($staleFiles.Count -gt 0) {
        Write-Host ""
        Write-Status "STALE FILES (in target but not in source):" "DarkYellow"
        foreach ($stale in $staleFiles) {
            Write-Host "    profiles/default/$($stale.Replace('\', '/'))" -ForegroundColor DarkYellow
        }
        Write-Status "These may need manual removal from the source repo." "DarkYellow"
    }
}

Write-Host ""
Write-Status "Done." "Green"
Write-Host ""
