function Invoke-AdrMarkDeprecated {
    param(
        [hashtable]$Arguments
    )

    $adrId  = $Arguments['adr_id']
    $reason = $Arguments['reason'] ?? ''
    if (-not $adrId) { throw "adr_id is required" }
    if ($adrId -notmatch '^adr-\d{3,}$') { throw "Invalid adr_id format '$adrId'. Expected: adr-NNN" }

    $adrsBaseDir  = Join-Path $global:DotbotProjectRoot ".bot\workspace\adrs"
    $allStatuses  = @('proposed', 'accepted')

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
        $fm = $fm -replace '(?m)^status:.*$',     'status: deprecated'
        $fm = $fm -replace '(?m)^updated_at:.*$', "updated_at: $now"
        $raw = $fmOpen + $fm + $fmClose + $body
    }

    if ($reason) {
        # Append deprecation note to body
        $raw = $raw.TrimEnd() + "`n`n## Deprecation Note`n`n$reason`n"
    }

    $targetDir  = Join-Path $adrsBaseDir "deprecated"
    if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Force -Path $targetDir | Out-Null }

    $targetPath = Join-Path $targetDir $found.file.Name
    $raw | Set-Content -Path $targetPath -Encoding UTF8
    Remove-Item -Path $found.file.FullName -Force

    return @{
        success   = $true
        adr_id    = $adrId
        message   = "ADR '$adrId' deprecated"
        file_path = $targetPath
    }
}
