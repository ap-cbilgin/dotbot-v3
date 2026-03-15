function Invoke-AdrMarkAccepted {
    param(
        [hashtable]$Arguments
    )

    $adrId = $Arguments['adr_id']
    if (-not $adrId) { throw "adr_id is required" }
    if ($adrId -notmatch '^adr-\d{3,}$') { throw "Invalid adr_id format '$adrId'. Expected: adr-NNN" }

    $adrsBaseDir = Join-Path $global:DotbotProjectRoot ".bot\workspace\adrs"
    $sourceDir   = Join-Path $adrsBaseDir "proposed"

    if (-not (Test-Path $sourceDir)) { throw "No proposed ADRs directory found" }

    $files = @(Get-ChildItem -LiteralPath $sourceDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "$adrId-*.md" -or $_.Name -eq "$adrId.md" })
    if ($files.Count -eq 0) {
        # Already accepted?
        $acceptedDir = Join-Path $adrsBaseDir "accepted"
        $existing = @(Get-ChildItem -LiteralPath $acceptedDir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "$adrId-*.md" -or $_.Name -eq "$adrId.md" })
        if ($existing.Count -gt 0) {
            return @{ success = $true; adr_id = $adrId; message = "ADR '$adrId' is already accepted" }
        }
        throw "ADR '$adrId' not found in proposed"
    }

    $file       = $files[0]
    $targetDir  = Join-Path $adrsBaseDir "accepted"
    if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Force -Path $targetDir | Out-Null }

    # Update only frontmatter, not the body
    $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
    $raw = Get-Content -Path $file.FullName -Raw
    if ($raw -match '(?s)^(---\r?\n)(.+?\r?\n)(---\r?\n)(.*)$') {
        $fmOpen  = $Matches[1]
        $fm      = $Matches[2]
        $fmClose = $Matches[3]
        $body    = $Matches[4]
        $fm = $fm -replace '(?m)^status:.*$', 'status: accepted'
        $fm = $fm -replace '(?m)^updated_at:.*$', "updated_at: $now"
        $raw = $fmOpen + $fm + $fmClose + $body
    }

    $targetPath = Join-Path $targetDir $file.Name
    $raw | Set-Content -Path $targetPath -Encoding UTF8
    Remove-Item -Path $file.FullName -Force

    return @{
        success   = $true
        adr_id    = $adrId
        message   = "ADR '$adrId' accepted"
        file_path = $targetPath
    }
}
