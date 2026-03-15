function Invoke-AdrList {
    param(
        [hashtable]$Arguments
    )

    $filterStatus = $Arguments['status']
    $adrsBaseDir  = Join-Path $global:DotbotProjectRoot ".bot\workspace\adrs"
    $allStatuses  = @('proposed', 'accepted', 'deprecated', 'superseded')

    if ($filterStatus -and $filterStatus -notin $allStatuses) {
        throw "Invalid status filter '$filterStatus'. Must be one of: $($allStatuses -join ', ')"
    }

    $searchDirs   = if ($filterStatus) { @($filterStatus) } else { $allStatuses }

    $adrs = @()
    foreach ($statusDir in $searchDirs) {
        $dirPath = Join-Path $adrsBaseDir $statusDir
        if (-not (Test-Path $dirPath)) { continue }

        $files = Get-ChildItem -Path $dirPath -Filter "adr-*.md" -File -ErrorAction SilentlyContinue
        foreach ($file in $files) {
            try {
                $raw = Get-Content -Path $file.FullName -Raw
                $frontmatter = $null

                # Parse YAML frontmatter between --- delimiters
                if ($raw -match '(?s)^---\r?\n(.+?)\r?\n---') {
                    $fm = $Matches[1]
                    $frontmatter = @{}
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

                $adrs += @{
                    id           = if ($frontmatter) { $frontmatter['id'] } else { $null }
                    title        = if ($frontmatter) { $frontmatter['title'] } else { $file.BaseName }
                    status       = $statusDir
                    created_at   = if ($frontmatter) { $frontmatter['created_at'] } else { $null }
                    source       = if ($frontmatter) { $frontmatter['source'] } else { $null }
                    superseded_by = if ($frontmatter) { $frontmatter['superseded_by'] } else { $null }
                    file_path    = $file.FullName
                    file_name    = $file.Name
                }
            } catch {
                # Skip unreadable files
            }
        }
    }

    # Sort by id
    $adrs = @($adrs | Sort-Object { $_.id })

    return @{
        success = $true
        count   = $adrs.Count
        adrs    = $adrs
    }
}
