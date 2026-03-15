function Invoke-AdrMarkSuperseded {
    param(
        [hashtable]$Arguments
    )

    $adrId       = $Arguments['adr_id']
    $supersededBy = $Arguments['superseded_by']
    if (-not $adrId)        { throw "adr_id is required" }
    if ($adrId -notmatch '^adr-\d{3,}$') { throw "Invalid adr_id format '$adrId'. Expected: adr-NNN" }
    if (-not $supersededBy) { throw "superseded_by is required" }
    if ($supersededBy -notmatch '^adr-\d{3,}$') { throw "Invalid superseded_by format '$supersededBy'. Expected: adr-NNN" }

    $adrsBaseDir = Join-Path $global:DotbotProjectRoot ".bot\workspace\adrs"
    $allStatuses = @('proposed', 'accepted')

    $found = $null
    foreach ($statusDir in $allStatuses) {
        $dirPath = Join-Path $adrsBaseDir $statusDir
        if (-not (Test-Path $dirPath)) { continue }
        $files = @(Get-ChildItem -LiteralPath $dirPath -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "$adrId-*.md" -or $_.Name -eq "$adrId.md" })
        if ($files.Count -gt 0) { $found = @{ file = $files[0]; status = $statusDir }; break }
    }

    if (-not $found) { throw "ADR '$adrId' not found in proposed or accepted" }

    $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
    $raw = Get-Content -Path $found.file.FullName -Raw

    # Update only frontmatter, not the body
    if ($raw -match '(?s)^(---\r?\n)(.+?\r?\n)(---\r?\n)(.*)$') {
        $fmOpen  = $Matches[1]
        $fm      = $Matches[2]
        $fmClose = $Matches[3]
        $body    = $Matches[4]
        $fm = $fm -replace '(?m)^status:.*$',        'status: superseded'
        $fm = $fm -replace '(?m)^updated_at:.*$',    "updated_at: $now"
        $fm = $fm -replace '(?m)^superseded_by:.*$', "superseded_by: $supersededBy"
        $raw = $fmOpen + $fm + $fmClose + $body
    }

    $targetDir = Join-Path $adrsBaseDir "superseded"
    if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Force -Path $targetDir | Out-Null }

    $targetPath = Join-Path $targetDir $found.file.Name
    $raw | Set-Content -Path $targetPath -Encoding UTF8
    Remove-Item -Path $found.file.FullName -Force

    return @{
        success       = $true
        adr_id        = $adrId
        superseded_by = $supersededBy
        message       = "ADR '$adrId' superseded by $supersededBy"
        file_path     = $targetPath
    }
}
