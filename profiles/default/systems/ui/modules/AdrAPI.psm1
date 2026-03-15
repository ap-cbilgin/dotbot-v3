<#
.SYNOPSIS
Architecture Decision Record API module

.DESCRIPTION
Provides ADR listing, retrieval, creation, status transitions, and updates.
Extracted as a standalone module following the existing API module pattern.
#>

$script:Config = @{
    BotRoot = $null
}

function ConvertTo-YamlScalar {
    param([string]$Value)
    if ($null -eq $Value -or $Value -eq '') { return "''" }
    $sanitized = $Value -replace '(\r\n|\r|\n)', ' '
    $escaped   = $sanitized -replace "'", "''"
    return "'$escaped'"
}

function Initialize-AdrAPI {
    param(
        [Parameter(Mandatory)] [string]$BotRoot
    )
    $script:Config.BotRoot = $BotRoot
}

function Get-AdrsBaseDir {
    return (Join-Path $script:Config.BotRoot "workspace\adrs")
}

function Read-AdrFrontmatter {
    param([string]$Raw)
    $fm = @{}
    if ($Raw -match '(?s)^---\r?\n(.+?)\r?\n---') {
        foreach ($line in ($Matches[1] -split '\r?\n')) {
            if ($line -match '^(\w[\w_-]*):\s*(.*)$') {
                $val = $Matches[2].Trim()
                # Strip YAML single-quoted scalars: 'value''s here' -> value's here
                if ($val.Length -ge 2 -and $val[0] -eq "'" -and $val[-1] -eq "'") {
                    $val = $val.Substring(1, $val.Length - 2) -replace "''", "'"
                }
                $fm[$Matches[1]] = $val
            }
        }
    }
    return $fm
}

function Read-AdrSections {
    param([string]$Raw)
    $sections = @{}
    $body = ''
    if ($Raw -match '(?s)^---\r?\n.+?\r?\n---\r?\n(.*)$') {
        $body = $Matches[1].Trim()
    }
    $curSection = $null
    $curLines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in ($body -split '\r?\n')) {
        if ($line -match '^## (.+)$') {
            if ($curSection) { $sections[$curSection] = ($curLines -join "`n").Trim() }
            $curSection = $Matches[1].Trim()
            $curLines = [System.Collections.Generic.List[string]]::new()
        } else {
            $curLines.Add($line)
        }
    }
    if ($curSection) { $sections[$curSection] = ($curLines -join "`n").Trim() }
    return $sections
}

function Test-AdrIdFormat([string]$Id) {
    return $Id -match '^adr-\d{3,}$'
}

function Assert-ValidRelatedAdrs {
    <#
    .SYNOPSIS
    Validates and filters related_adrs to strict ADR ID format.
    Rejects any value that doesn't match adr-NNN to prevent YAML injection.
    #>
    param([array]$Items)
    $valid = @()
    foreach ($item in $Items) {
        if ($item -and $item -match '^adr-\d{3,}$') {
            $valid += $item
        }
    }
    return $valid
}

function Format-RelatedAdrsYaml {
    <#
    .SYNOPSIS
    Formats validated related_adrs as a YAML inline list.
    Items must be pre-validated via Assert-ValidRelatedAdrs.
    #>
    param([array]$Items)
    if ($Items.Count -gt 0) {
        return "[" + (($Items | ForEach-Object { "`"$_`"" }) -join ", ") + "]"
    }
    return "[]"
}

function Find-AdrFile {
    param([string]$AdrId, [string[]]$Statuses)
    if (-not (Test-AdrIdFormat $AdrId)) { return $null }
    $base = Get-AdrsBaseDir
    foreach ($s in $Statuses) {
        $dir = Join-Path $base $s
        if (-not (Test-Path $dir)) { continue }
        # Use -LiteralPath with Where-Object to avoid wildcard expansion in AdrId
        $files = Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "$AdrId-*.md" -or $_.Name -eq "$AdrId.md" }
        if ($files.Count -gt 0) { return @{ file = @($files)[0]; status = $s } }
    }
    return $null
}

# ── List ──────────────────────────────────────────────────────────────────────

function Get-AdrList {
    param([string]$StatusFilter)
    $base         = Get-AdrsBaseDir
    $allStatuses  = @('proposed', 'accepted', 'deprecated', 'superseded')
    if ($StatusFilter -and $StatusFilter -notin $allStatuses) {
        return @{ _statusCode = 400; success = $false; error = "Invalid status filter '$StatusFilter'. Must be one of: $($allStatuses -join ', ')" }
    }
    $searchDirs   = if ($StatusFilter) { @($StatusFilter) } else { $allStatuses }
    $adrs = @()

    foreach ($s in $searchDirs) {
        $dir = Join-Path $base $s
        if (-not (Test-Path $dir)) { continue }
        $files = Get-ChildItem -Path $dir -Filter "adr-*.md" -File -ErrorAction SilentlyContinue
        foreach ($f in $files) {
            try {
                $raw = Get-Content -Path $f.FullName -Raw
                $fm  = Read-AdrFrontmatter $raw
                $adrs += @{
                    id           = $fm['id']
                    title        = $fm['title']
                    status       = $s
                    created_at   = $fm['created_at']
                    updated_at   = $fm['updated_at']
                    source       = $fm['source']
                    superseded_by = $fm['superseded_by']
                    related_adrs = $fm['related_adrs']
                    file_name    = $f.Name
                }
            } catch { }
        }
    }

    $adrs = @($adrs | Sort-Object { $_.id })
    return @{ success = $true; count = $adrs.Count; adrs = $adrs }
}

# ── Get ───────────────────────────────────────────────────────────────────────

function Get-AdrDetail {
    param([string]$AdrId)
    $found = Find-AdrFile -AdrId $AdrId -Statuses @('proposed', 'accepted', 'deprecated', 'superseded')
    if (-not $found) { return @{ _statusCode = 404; success = $false; error = "ADR '$AdrId' not found" } }

    $raw      = Get-Content -Path $found.file.FullName -Raw
    $fm       = Read-AdrFrontmatter $raw
    $sections = Read-AdrSections $raw

    return @{
        success       = $true
        id            = $fm['id']
        title         = $fm['title']
        status        = $found.status
        created_at    = $fm['created_at']
        updated_at    = $fm['updated_at']
        source        = $fm['source']
        superseded_by = $fm['superseded_by']
        related_adrs  = $fm['related_adrs']
        sections      = $sections
        raw           = $raw
    }
}

# ── Create ────────────────────────────────────────────────────────────────────

function New-Adr {
    param([hashtable]$Body)

    $title       = $Body['title']
    $context     = $Body['context']
    $decision    = $Body['decision']
    $rationale   = $Body['rationale'] ?? ''
    $consequences = $Body['consequences'] ?? ''
    $alternatives = $Body['alternatives_considered'] ?? ''
    $status      = $Body['status'] ?? 'proposed'
    $source      = $Body['source'] ?? 'manual'
    $relatedAdrs = Assert-ValidRelatedAdrs @($Body['related_adrs'] | Where-Object { $_ })

    if (-not $title -or -not $context -or -not $decision) {
        return @{ _statusCode = 400; success = $false; error = "title, context, and decision are required" }
    }
    if ($status -notin @('proposed', 'accepted')) {
        return @{ _statusCode = 400; success = $false; error = "status must be proposed or accepted" }
    }

    $base = Get-AdrsBaseDir
    $allDirs = @('proposed', 'accepted', 'deprecated', 'superseded')
    $maxNum  = 0
    foreach ($d in $allDirs) {
        $dp = Join-Path $base $d
        if (-not (Test-Path $dp)) { continue }
        Get-ChildItem -Path $dp -Filter "adr-*.md" -File -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.Name -match '^adr-(\d+)(?=\D)') { $n = [int]$Matches[1]; if ($n -gt $maxNum) { $maxNum = $n } }
        }
    }
    $id   = "adr-{0:D3}" -f ($maxNum + 1)
    $slug = ($title -replace '[^\w\s-]', '' -replace '\s+', '-').ToLower()
    if ($slug.Length -gt 60) { $slug = $slug.Substring(0, 60).TrimEnd('-') }

    $now        = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
    $relatedYaml = Format-RelatedAdrsYaml $relatedAdrs

    $safeTitle  = ConvertTo-YamlScalar $title
    $safeSource = ConvertTo-YamlScalar $source

    $fileContent = @"
---
id: $id
title: $safeTitle
status: $status
created_at: $now
updated_at: $now
source: $safeSource
related_adrs: $relatedYaml
superseded_by: null
---

## Context

$context

## Decision

$decision

## Rationale

$rationale

## Consequences

$consequences

## Alternatives Considered

$alternatives
"@

    $targetDir = Join-Path $base $status
    if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Force -Path $targetDir | Out-Null }
    $filePath = Join-Path $targetDir "$id-$slug.md"
    $fileContent | Set-Content -Path $filePath -Encoding UTF8

    return @{ success = $true; adr_id = $id; status = $status; file_path = $filePath; message = "ADR '$title' created as $id" }
}

# ── Update ────────────────────────────────────────────────────────────────────

function Update-Adr {
    param([string]$AdrId, [hashtable]$Body)

    $found = Find-AdrFile -AdrId $AdrId -Statuses @('proposed', 'accepted', 'deprecated', 'superseded')
    if (-not $found) { return @{ _statusCode = 404; success = $false; error = "ADR '$AdrId' not found" } }

    $raw = Get-Content -Path $found.file.FullName -Raw
    $fm  = Read-AdrFrontmatter $raw

    $sectionsMap = [ordered]@{}
    if ($raw -match '(?s)^---\r?\n.+?\r?\n---\r?\n(.*)$') {
        $mdBody = $Matches[1].Trim()
        $curSection = $null; $curLines = [System.Collections.Generic.List[string]]::new()
        foreach ($line in ($mdBody -split '\r?\n')) {
            if ($line -match '^## (.+)$') {
                if ($curSection) { $sectionsMap[$curSection] = ($curLines -join "`n").Trim() }
                $curSection = $Matches[1].Trim(); $curLines = [System.Collections.Generic.List[string]]::new()
            } else { $curLines.Add($line) }
        }
        if ($curSection) { $sectionsMap[$curSection] = ($curLines -join "`n").Trim() }
    }

    $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
    $fm['updated_at'] = $now
    if ($Body['title'])        { $fm['title'] = $Body['title'] }
    if ($Body['related_adrs']) {
        $rel = Assert-ValidRelatedAdrs @($Body['related_adrs'] | Where-Object { $_ })
        $fm['related_adrs'] = Format-RelatedAdrsYaml $rel
    }

    $sectionKeyMap = @{
        'context'                = 'Context'
        'decision'               = 'Decision'
        'rationale'              = 'Rationale'
        'consequences'           = 'Consequences'
        'alternatives_considered' = 'Alternatives Considered'
    }
    foreach ($k in $sectionKeyMap.Keys) {
        if ($Body.ContainsKey($k)) { $sectionsMap[$sectionKeyMap[$k]] = $Body[$k] }
    }

    $yamlQuotedKeys = @('title', 'source')
    $fmLines = @(); foreach ($k in $fm.Keys) {
        if ($k -in $yamlQuotedKeys) { $fmLines += "$($k): $(ConvertTo-YamlScalar $fm[$k])" }
        else { $fmLines += "$($k): $($fm[$k])" }
    }
    $order   = @('Context', 'Decision', 'Rationale', 'Consequences', 'Alternatives Considered')
    $parts   = @()
    foreach ($s in $order) { if ($sectionsMap.Contains($s)) { $parts += "## $s`n`n$($sectionsMap[$s])" } }
    foreach ($s in $sectionsMap.Keys) { if ($s -notin $order) { $parts += "## $s`n`n$($sectionsMap[$s])" } }

    $newContent = "---`n" + ($fmLines -join "`n") + "`n---`n`n" + ($parts -join "`n`n") + "`n"
    Set-Content -Path $found.file.FullName -Value $newContent -Encoding UTF8

    return @{ success = $true; adr_id = $AdrId; message = "ADR '$AdrId' updated" }
}

# ── Status transitions ────────────────────────────────────────────────────────

function Set-AdrStatus {
    param([string]$AdrId, [string]$NewStatus, [string]$SupersededBy, [string]$Reason)

    $allStatuses = @('proposed', 'accepted', 'deprecated', 'superseded')
    if ($NewStatus -notin $allStatuses) {
        return @{ _statusCode = 400; success = $false; error = "Invalid status '$NewStatus'. Must be one of: $($allStatuses -join ', ')" }
    }
    if (-not (Test-AdrIdFormat $AdrId)) {
        return @{ _statusCode = 400; success = $false; error = "Invalid ADR ID format '$AdrId'. Expected: adr-NNN" }
    }
    if ($NewStatus -eq 'superseded') {
        if (-not $SupersededBy) {
            return @{ _statusCode = 400; success = $false; error = "superseded_by is required when transitioning to superseded" }
        }
        if (-not (Test-AdrIdFormat $SupersededBy)) {
            return @{ _statusCode = 400; success = $false; error = "Invalid superseded_by format '$SupersededBy'. Expected: adr-NNN" }
        }
    }

    $validSources = @('proposed', 'accepted')
    $found = Find-AdrFile -AdrId $AdrId -Statuses $validSources
    if (-not $found) {
        # Check if already at target
        $existing = Find-AdrFile -AdrId $AdrId -Statuses @($NewStatus)
        if ($existing) { return @{ success = $true; adr_id = $AdrId; message = "ADR '$AdrId' is already $NewStatus" } }
        return @{ _statusCode = 404; success = $false; error = "ADR '$AdrId' not found in proposed or accepted" }
    }

    # Idempotency: already at target status — no file move needed
    if ($found.status -eq $NewStatus) {
        return @{ success = $true; adr_id = $AdrId; status = $NewStatus; file_path = $found.file.FullName; message = "ADR '$AdrId' is already $NewStatus" }
    }

    $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
    $raw = Get-Content -Path $found.file.FullName -Raw

    # Update only frontmatter, not the body
    if ($raw -match '(?s)^(---\r?\n)(.+?\r?\n)(---\r?\n)(.*)$') {
        $fmOpen  = $Matches[1]
        $fm      = $Matches[2]
        $fmClose = $Matches[3]
        $body    = $Matches[4]
        $fm = $fm -replace '(?m)^status:.*$',     "status: $NewStatus"
        $fm = $fm -replace '(?m)^updated_at:.*$', "updated_at: $now"
        if ($NewStatus -eq 'superseded' -and $SupersededBy) {
            $fm = $fm -replace '(?m)^superseded_by:.*$', "superseded_by: $SupersededBy"
        }
        $raw = $fmOpen + $fm + $fmClose + $body
    }

    if ($Reason) {
        $raw = $raw.TrimEnd() + "`n`n## Deprecation Note`n`n$Reason`n"
    }

    $base      = Get-AdrsBaseDir
    $targetDir = Join-Path $base $NewStatus
    if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Force -Path $targetDir | Out-Null }
    $targetPath = Join-Path $targetDir $found.file.Name
    $raw | Set-Content -Path $targetPath -Encoding UTF8
    Remove-Item -Path $found.file.FullName -Force

    return @{ success = $true; adr_id = $AdrId; status = $NewStatus; file_path = $targetPath; message = "ADR '$AdrId' is now $NewStatus" }
}

Export-ModuleMember -Function @(
    'Initialize-AdrAPI',
    'Get-AdrList',
    'Get-AdrDetail',
    'New-Adr',
    'Update-Adr',
    'Set-AdrStatus'
)
