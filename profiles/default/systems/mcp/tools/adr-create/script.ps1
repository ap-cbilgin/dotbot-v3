function Invoke-AdrCreate {
    param(
        [hashtable]$Arguments
    )

    $title                 = $Arguments['title']
    $context               = $Arguments['context']
    $decision              = $Arguments['decision']
    $rationale             = $Arguments['rationale'] ?? ''
    $consequences          = $Arguments['consequences'] ?? ''
    $alternativesConsidered = $Arguments['alternatives_considered'] ?? ''
    $status                = $Arguments['status'] ?? 'proposed'
    $source                = $Arguments['source'] ?? 'manual'
    $relatedAdrsRaw        = $Arguments['related_adrs'] ?? @()

    # Validate related_adrs to strict ADR ID format to prevent YAML injection
    $relatedAdrs = @($relatedAdrsRaw | Where-Object { $_ -match '^adr-\d{3,}$' })

    if (-not $title)    { throw "ADR title is required" }
    if (-not $context)  { throw "ADR context is required" }
    if (-not $decision) { throw "ADR decision is required" }

    $validStatuses = @('proposed', 'accepted')
    if ($status -notin $validStatuses) {
        throw "Invalid status '$status'. Must be one of: $($validStatuses -join ', ')"
    }

    $adrsBaseDir = Join-Path $global:DotbotProjectRoot ".bot\workspace\adrs"

    # Determine next ADR number by scanning all statuses
    $allDirs = @('proposed', 'accepted', 'deprecated', 'superseded')
    $maxNum = 0
    foreach ($dir in $allDirs) {
        $dirPath = Join-Path $adrsBaseDir $dir
        if (Test-Path $dirPath) {
            $files = Get-ChildItem -Path $dirPath -Filter "adr-*.md" -File -ErrorAction SilentlyContinue
            foreach ($f in $files) {
                if ($f.Name -match '^adr-(\d+)(?=\D)') {
                    $num = [int]$Matches[1]
                    if ($num -gt $maxNum) { $maxNum = $num }
                }
            }
        }
    }
    $nextNum = $maxNum + 1
    $id = "adr-{0:D3}" -f $nextNum

    # Build slug from title
    $slug = ($title -replace '[^\w\s-]', '' -replace '\s+', '-').ToLower()
    if ($slug.Length -gt 60) { $slug = $slug.Substring(0, 60).TrimEnd('-') }

    $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")

    # Build related_adrs YAML inline
    $relatedYaml = if ($relatedAdrs -and $relatedAdrs.Count -gt 0) {
        "[" + (($relatedAdrs | ForEach-Object { "`"$_`"" }) -join ", ") + "]"
    } else { "[]" }

    # Build markdown content (quote user-provided scalars for YAML safety)
    $safeTitle  = ConvertTo-YamlScalar $title
    $safeSource = ConvertTo-YamlScalar $source

    $content = @"
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

$alternativesConsidered
"@

    $targetDir = Join-Path $adrsBaseDir $status
    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
    }

    $fileName = "$id-$slug.md"
    $filePath = Join-Path $targetDir $fileName

    $content | Set-Content -Path $filePath -Encoding UTF8

    return @{
        success  = $true
        adr_id   = $id
        status   = $status
        file_path = $filePath
        message  = "ADR '$title' created as $id ($status)"
    }
}
