function Invoke-AdrUpdate {
    param(
        [hashtable]$Arguments
    )

    $adrId = $Arguments['adr_id']
    if (-not $adrId) { throw "adr_id is required" }

    $adrsBaseDir = Join-Path $global:DotbotProjectRoot ".bot\workspace\adrs"
    $allStatuses = @('proposed', 'accepted', 'deprecated', 'superseded')

    $found = $null
    foreach ($statusDir in $allStatuses) {
        $dirPath = Join-Path $adrsBaseDir $statusDir
        if (-not (Test-Path $dirPath)) { continue }
        $files = Get-ChildItem -Path $dirPath -Filter "$adrId-*.md" -File -ErrorAction SilentlyContinue
        if ($files.Count -gt 0) {
            $found = @{ file = $files[0]; status = $statusDir }
            break
        }
    }

    if (-not $found) { throw "ADR '$adrId' not found" }

    $raw = Get-Content -Path $found.file.FullName -Raw

    # Parse existing frontmatter and body sections
    $frontmatter = @{}
    $sectionsMap = [ordered]@{}
    if ($raw -match '(?s)^---\r?\n(.+?)\r?\n---\r?\n(.*)$') {
        $fm   = $Matches[1]
        $body = $Matches[2].Trim()
        foreach ($line in ($fm -split '\r?\n')) {
            if ($line -match '^(\w[\w_-]*):\s*(.*)$') {
                $val = $Matches[2].Trim()
                # Strip YAML single-quoted scalars
                if ($val.Length -ge 2 -and $val[0] -eq "'" -and $val[-1] -eq "'") {
                    $val = $val.Substring(1, $val.Length - 2) -replace "''", "'"
                }
                $frontmatter[$Matches[1]] = $val
            }
        }
        # Parse sections
        $currentSection = $null
        $currentLines   = [System.Collections.Generic.List[string]]::new()
        foreach ($line in ($body -split '\r?\n')) {
            if ($line -match '^## (.+)$') {
                if ($currentSection) {
                    $sectionsMap[$currentSection] = ($currentLines -join "`n").Trim()
                }
                $currentSection = $Matches[1].Trim()
                $currentLines   = [System.Collections.Generic.List[string]]::new()
            } else {
                $currentLines.Add($line)
            }
        }
        if ($currentSection) { $sectionsMap[$currentSection] = ($currentLines -join "`n").Trim() }
    }

    # Apply updates
    $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
    $frontmatter['updated_at'] = $now

    if ($Arguments.ContainsKey('title'))        { $frontmatter['title']  = $Arguments['title'] }
    if ($Arguments.ContainsKey('related_adrs')) {
        $relArr = @($Arguments['related_adrs'])
        $frontmatter['related_adrs'] = "[" + (($relArr | ForEach-Object { "`"$_`"" }) -join ", ") + "]"
    }

    $sectionKeyMap = @{
        'context'                = 'Context'
        'decision'               = 'Decision'
        'rationale'              = 'Rationale'
        'consequences'           = 'Consequences'
        'alternatives_considered' = 'Alternatives Considered'
    }
    foreach ($argKey in $sectionKeyMap.Keys) {
        if ($Arguments.ContainsKey($argKey)) {
            $sectionsMap[$sectionKeyMap[$argKey]] = $Arguments[$argKey]
        }
    }

    # Rebuild frontmatter block (quote user-provided scalars for YAML safety)
    $yamlQuotedKeys = @('title', 'source')
    $fmLines = @()
    foreach ($key in $frontmatter.Keys) {
        if ($key -in $yamlQuotedKeys) {
            $fmLines += "$($key): $(ConvertTo-YamlScalar $frontmatter[$key])"
        } else {
            $fmLines += "$($key): $($frontmatter[$key])"
        }
    }

    # Rebuild body
    $bodyParts = @()
    $sectionOrder = @('Context', 'Decision', 'Rationale', 'Consequences', 'Alternatives Considered')
    foreach ($sec in $sectionOrder) {
        if ($sectionsMap.Contains($sec)) {
            $bodyParts += "## $sec`n`n$($sectionsMap[$sec])"
        }
    }
    # Any extra sections not in the fixed order
    foreach ($sec in $sectionsMap.Keys) {
        if ($sec -notin $sectionOrder) {
            $bodyParts += "## $sec`n`n$($sectionsMap[$sec])"
        }
    }

    $newContent = "---`n" + ($fmLines -join "`n") + "`n---`n`n" + ($bodyParts -join "`n`n") + "`n"

    Set-Content -Path $found.file.FullName -Value $newContent -Encoding UTF8

    return @{
        success   = $true
        adr_id    = $adrId
        message   = "ADR '$adrId' updated"
        file_path = $found.file.FullName
    }
}
