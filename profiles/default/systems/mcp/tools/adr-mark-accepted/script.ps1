function Invoke-AdrMarkAccepted {
    param(
        [hashtable]$Arguments
    )

    $adrId = $Arguments['adr_id']
    if (-not $adrId) { throw "adr_id is required" }

    $adrsBaseDir = Join-Path $global:DotbotProjectRoot ".bot\workspace\adrs"
    $sourceDir   = Join-Path $adrsBaseDir "proposed"

    if (-not (Test-Path $sourceDir)) { throw "No proposed ADRs directory found" }

    $files = Get-ChildItem -Path $sourceDir -Filter "$adrId-*.md" -File -ErrorAction SilentlyContinue
    if ($files.Count -eq 0) {
        # Already accepted?
        $acceptedDir = Join-Path $adrsBaseDir "accepted"
        $existing = Get-ChildItem -Path $acceptedDir -Filter "$adrId-*.md" -File -ErrorAction SilentlyContinue
        if ($existing.Count -gt 0) {
            return @{ success = $true; adr_id = $adrId; message = "ADR '$adrId' is already accepted" }
        }
        throw "ADR '$adrId' not found in proposed"
    }

    $file       = $files[0]
    $targetDir  = Join-Path $adrsBaseDir "accepted"
    if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Force -Path $targetDir | Out-Null }

    # Update status in frontmatter
    $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
    $raw = Get-Content -Path $file.FullName -Raw
    $raw = $raw -replace '(?m)^status:.*$', 'status: accepted'
    $raw = $raw -replace '(?m)^updated_at:.*$', "updated_at: $now"

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
