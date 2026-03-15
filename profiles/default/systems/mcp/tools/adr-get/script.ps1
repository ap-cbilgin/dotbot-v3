function Invoke-AdrGet {
    param(
        [hashtable]$Arguments
    )

    $adrId       = $Arguments['adr_id']
    if (-not $adrId) { throw "adr_id is required" }
    if ($adrId -notmatch '^adr-\d{3,}$') { throw "Invalid adr_id format '$adrId'. Expected: adr-NNN" }

    $adrsBaseDir = Join-Path $global:DotbotProjectRoot ".bot\workspace\adrs"
    $allStatuses = @('proposed', 'accepted', 'deprecated', 'superseded')

    $found = $null
    foreach ($statusDir in $allStatuses) {
        $dirPath = Join-Path $adrsBaseDir $statusDir
        if (-not (Test-Path $dirPath)) { continue }

        $files = @(Get-ChildItem -LiteralPath $dirPath -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "$adrId-*.md" -or $_.Name -eq "$adrId.md" })
        if ($files.Count -gt 0) {
            $found = @{ file = $files[0]; status = $statusDir }
            break
        }
    }

    if (-not $found) {
        throw "ADR '$adrId' not found"
    }

    $raw = Get-Content -Path $found.file.FullName -Raw

    # Parse frontmatter
    $frontmatter = @{}
    $body = $raw
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
    }

    # Extract named sections from body
    $sections = @{}
    $currentSection = $null
    $currentLines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in ($body -split '\r?\n')) {
        if ($line -match '^## (.+)$') {
            if ($currentSection) {
                $sections[$currentSection] = ($currentLines -join "`n").Trim()
            }
            $currentSection = $Matches[1].Trim()
            $currentLines = [System.Collections.Generic.List[string]]::new()
        } else {
            $currentLines.Add($line)
        }
    }
    if ($currentSection) {
        $sections[$currentSection] = ($currentLines -join "`n").Trim()
    }

    return @{
        success      = $true
        id           = $frontmatter['id']
        title        = $frontmatter['title']
        status       = $found.status
        created_at   = $frontmatter['created_at']
        updated_at   = $frontmatter['updated_at']
        source       = $frontmatter['source']
        superseded_by = $frontmatter['superseded_by']
        file_path    = $found.file.FullName
        content      = $raw
        sections     = $sections
    }
}
