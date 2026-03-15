function Invoke-TaskGetContext {
    param(
        [hashtable]$Arguments
    )

    # Extract arguments
    $taskId = $Arguments['task_id']

    # Validate required fields
    if (-not $taskId) {
        throw "Task ID is required"
    }

    # Define tasks directories
    $tasksBaseDir = Join-Path $global:DotbotProjectRoot ".bot\workspace\tasks"
    $analysedDir = Join-Path $tasksBaseDir "analysed"
    $inProgressDir = Join-Path $tasksBaseDir "in-progress"

    # Find the task file (can be in analysed or in-progress)
    $taskFile = $null
    $currentStatus = $null

    foreach ($searchDir in @($analysedDir, $inProgressDir)) {
        if (Test-Path $searchDir) {
            $files = Get-ChildItem -Path $searchDir -Filter "*.json" -File
            foreach ($file in $files) {
                try {
                    $content = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
                    if ($content.id -eq $taskId) {
                        $taskFile = $file
                        $currentStatus = if ($searchDir -eq $analysedDir) { 'analysed' } else { 'in-progress' }
                        break
                    }
                } catch {
                    # Continue searching
                }
            }
            if ($taskFile) { break }
        }
    }

    if (-not $taskFile) {
        throw "Task with ID '$taskId' not found in analysed or in-progress status"
    }

    # Read task content
    $taskContent = Get-Content -Path $taskFile.FullName -Raw | ConvertFrom-Json

    # Check if task has analysis data
    $hasAnalysis = $taskContent.PSObject.Properties['analysis'] -and $taskContent.analysis

    if (-not $hasAnalysis) {
        # Task doesn't have pre-flight analysis - return minimal context
        return @{
            success = $true
            has_analysis = $false
            task_id = $taskId
            task_name = $taskContent.name
            status = $currentStatus
            message = "Task has no pre-flight analysis data. Use standard exploration."
            task = @{
                id = $taskContent.id
                name = $taskContent.name
                description = $taskContent.description
                category = $taskContent.category
                priority = $taskContent.priority
                effort = $taskContent.effort
                acceptance_criteria = $taskContent.acceptance_criteria
                steps = $taskContent.steps
                dependencies = $taskContent.dependencies
                applicable_agents = $taskContent.applicable_agents
                applicable_standards = $taskContent.applicable_standards
                applicable_adrs = $taskContent.applicable_adrs
            }
        }
    }

    # Return full analysis context
    $analysis = $taskContent.analysis

    # Resolve ADR content from applicable_adrs list
    $adrContent = @()
    $adrIds = @($taskContent.applicable_adrs | Where-Object { $_ -match '^adr-\d{3,}$' })
    if ($adrIds.Count -gt 0) {
        $adrsBaseDir = Join-Path $global:DotbotProjectRoot ".bot\workspace\adrs"
        $adrStatuses = @('accepted', 'proposed', 'deprecated', 'superseded')
        foreach ($adrId in $adrIds) {
            $adrFound = $false
            foreach ($statusDir in $adrStatuses) {
                $dirPath = Join-Path $adrsBaseDir $statusDir
                if (-not (Test-Path $dirPath)) { continue }
                $files = @(Get-ChildItem -LiteralPath $dirPath -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -like "$adrId-*.md" -or $_.Name -eq "$adrId.md" })
                if ($files.Count -gt 0) {
                    try {
                        $raw = Get-Content -Path $files[0].FullName -Raw
                        $sections = @{}
                        $frontmatter = @{}
                        if ($raw -match '(?s)^---\r?\n(.+?)\r?\n---\r?\n(.*)$') {
                            $fm = $Matches[1]; $body = $Matches[2].Trim()
                            foreach ($line in ($fm -split '\r?\n')) {
                                if ($line -match '^(\w[\w_-]*):\s*(.*)$') {
                                    $fmVal = $Matches[2].Trim()
                                    if ($fmVal.Length -ge 2 -and $fmVal[0] -eq "'" -and $fmVal[-1] -eq "'") {
                                        $fmVal = $fmVal.Substring(1, $fmVal.Length - 2) -replace "''", "'"
                                    }
                                    $frontmatter[$Matches[1]] = $fmVal
                                }
                            }
                            $curSection = $null; $curLines = [System.Collections.Generic.List[string]]::new()
                            foreach ($line in ($body -split '\r?\n')) {
                                if ($line -match '^## (.+)$') {
                                    if ($curSection) { $sections[$curSection] = ($curLines -join "`n").Trim() }
                                    $curSection = $Matches[1].Trim(); $curLines = [System.Collections.Generic.List[string]]::new()
                                } else { $curLines.Add($line) }
                            }
                            if ($curSection) { $sections[$curSection] = ($curLines -join "`n").Trim() }
                        }
                        $adrContent += @{
                            id                       = $adrId
                            title                    = $frontmatter['title']
                            status                   = $statusDir
                            context                  = $sections['Context']
                            decision                 = $sections['Decision']
                            rationale                = $sections['Rationale']
                            consequences             = $sections['Consequences']
                            alternatives_considered  = $sections['Alternatives Considered']
                        }
                        $adrFound = $true
                    } catch { }
                    break
                }
            }
            if (-not $adrFound) {
                $adrContent += @{ id = $adrId; title = $null; status = 'not-found'; context = $null; decision = $null; rationale = $null; consequences = $null; alternatives_considered = $null }
            }
        }
    }

    return @{
        success = $true
        has_analysis = $true
        task_id = $taskId
        task_name = $taskContent.name
        status = $currentStatus
        message = "Pre-flight analysis available - use packaged context"

        # Core task info
        task = @{
            id = $taskContent.id
            name = $taskContent.name
            description = $taskContent.description
            category = $taskContent.category
            priority = $taskContent.priority
            effort = $taskContent.effort
            acceptance_criteria = $taskContent.acceptance_criteria
            steps = $taskContent.steps
            dependencies = $taskContent.dependencies
            applicable_agents = $taskContent.applicable_agents
            applicable_standards = $taskContent.applicable_standards
            applicable_adrs = $taskContent.applicable_adrs
        }

        # Pre-flight analysis
        analysis = @{
            analysed_at = $analysis.analysed_at
            analysed_by = $analysis.analysed_by
            
            # Entity context
            entities = $analysis.entities
            
            # Files to work with
            files = $analysis.files
            
            # Dependencies checked
            dependencies = $analysis.dependencies
            
            # Standards to follow
            standards = $analysis.standards
            
            # Product context (already extracted)
            product_context = $analysis.product_context
            
            # Implementation guidance
            implementation = $analysis.implementation
            
            # Questions that were resolved
            questions_resolved = $analysis.questions_resolved

            # Applicable ADRs with content
            adrs = $adrContent
        }
    }
}
