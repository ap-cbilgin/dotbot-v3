#!/usr/bin/env pwsh
param(
    [Parameter(Mandatory)]
    [System.Diagnostics.Process]$Process
)

. "$PSScriptRoot\..\..\dotbot-mcp-helpers.ps1"

function Send-McpRequest {
    param(
        [Parameter(Mandatory)]
        [object]$Request,
        [Parameter(Mandatory)]
        [System.Diagnostics.Process]$Process
    )

    $json = $Request | ConvertTo-Json -Depth 10 -Compress
    $Process.StandardInput.WriteLine($json)
    $Process.StandardInput.Flush()
    Start-Sleep -Milliseconds 100
    $response = $Process.StandardOutput.ReadLine()

    if ($response) {
        return $response | ConvertFrom-Json
    }
    return $null
}

# ── Test 1: Create a basic ADR ──
Write-Host "Test: Create a basic ADR" -ForegroundColor Yellow
$response = Send-McpRequest -Process $Process -Request @{
    jsonrpc = '2.0'
    id = 1
    method = 'tools/call'
    params = @{
        name = 'adr_create'
        arguments = @{
            title = 'Use PostgreSQL for Primary Storage'
            context = 'We need a reliable relational database for our core data model.'
            decision = 'Use PostgreSQL 15+ as our primary data store.'
            rationale = 'PostgreSQL offers strong ACID compliance and rich JSON support.'
            consequences = 'Team needs PostgreSQL expertise. Migration from SQLite required.'
            alternatives_considered = 'MySQL, MongoDB, SQLite were evaluated but lacked required features.'
            status = 'proposed'
            source = 'manual'
        }
    }
}
$result = $response.result.content[0].text | ConvertFrom-Json
if (-not $result.success) { throw "Expected success=true" }
if ($result.status -ne 'proposed') { throw "Expected status=proposed, got $($result.status)" }
if (-not $result.adr_id) { throw "Expected adr_id to be set" }
Write-Host "✓ ADR created: $($result.adr_id)" -ForegroundColor Green

# ── Test 2: Create ADR with special characters in title (YAML safety) ──
Write-Host "`nTest: Create ADR with special characters in title" -ForegroundColor Yellow
$response = Send-McpRequest -Process $Process -Request @{
    jsonrpc = '2.0'
    id = 2
    method = 'tools/call'
    params = @{
        name = 'adr_create'
        arguments = @{
            title = "Use Node.js: It's fast & reliable"
            context = 'Need a runtime for our API server.'
            decision = 'Adopt Node.js for all backend services.'
            source = "engineer's recommendation"
        }
    }
}
$result = $response.result.content[0].text | ConvertFrom-Json
if (-not $result.success) { throw "Expected success=true" }

# Verify the file was written with proper YAML quoting
$fileContent = Get-Content -Path $result.file_path -Raw
if ($fileContent -notmatch "title: '") {
    throw "Expected title to be YAML single-quoted, got: $fileContent"
}
if ($fileContent -notmatch "source: '") {
    throw "Expected source to be YAML single-quoted"
}
Write-Host "✓ ADR with special chars created, YAML quoting verified" -ForegroundColor Green

# ── Test 3: Create ADR with accepted status ──
Write-Host "`nTest: Create ADR with accepted status" -ForegroundColor Yellow
$response = Send-McpRequest -Process $Process -Request @{
    jsonrpc = '2.0'
    id = 3
    method = 'tools/call'
    params = @{
        name = 'adr_create'
        arguments = @{
            title = 'Use REST over GraphQL'
            context = 'Choosing an API paradigm.'
            decision = 'Use REST for all public APIs.'
            status = 'accepted'
        }
    }
}
$result = $response.result.content[0].text | ConvertFrom-Json
if (-not $result.success) { throw "Expected success=true" }
if ($result.status -ne 'accepted') { throw "Expected status=accepted, got $($result.status)" }
if ($result.file_path -notlike '*accepted*') { throw "Expected file in accepted directory" }
Write-Host "✓ ADR created directly as accepted" -ForegroundColor Green

# ── Test 4: Create ADR with related_adrs ──
Write-Host "`nTest: Create ADR with related ADRs" -ForegroundColor Yellow
$response = Send-McpRequest -Process $Process -Request @{
    jsonrpc = '2.0'
    id = 4
    method = 'tools/call'
    params = @{
        name = 'adr_create'
        arguments = @{
            title = 'Use Redis for Caching'
            context = 'Need a caching layer.'
            decision = 'Use Redis for application-level caching.'
            related_adrs = @('adr-001', 'adr-002')
        }
    }
}
$result = $response.result.content[0].text | ConvertFrom-Json
if (-not $result.success) { throw "Expected success=true" }

# Verify related_adrs in file
$fileContent = Get-Content -Path $result.file_path -Raw
if ($fileContent -notmatch 'related_adrs:.*adr-001') {
    throw "Expected related_adrs to contain adr-001"
}
Write-Host "✓ ADR with related ADRs created" -ForegroundColor Green

# ── Test 5: Create ADR missing required fields should fail ──
Write-Host "`nTest: Create ADR without required fields should fail" -ForegroundColor Yellow
$response = Send-McpRequest -Process $Process -Request @{
    jsonrpc = '2.0'
    id = 5
    method = 'tools/call'
    params = @{
        name = 'adr_create'
        arguments = @{
            title = 'Missing context and decision'
        }
    }
}
$errorMsg = if ($response.error) { $response.error.message } else { $response.result.content[0].text }
if ($errorMsg -notmatch 'required') {
    throw "Expected error about required fields, got: $errorMsg"
}
Write-Host "✓ Missing required fields correctly rejected" -ForegroundColor Green

# ── Test 6: Create ADR with invalid status should fail ──
Write-Host "`nTest: Create ADR with invalid status should fail" -ForegroundColor Yellow
$response = Send-McpRequest -Process $Process -Request @{
    jsonrpc = '2.0'
    id = 6
    method = 'tools/call'
    params = @{
        name = 'adr_create'
        arguments = @{
            title = 'Bad Status'
            context = 'Testing invalid status.'
            decision = 'Should not be created.'
            status = 'rejected'
        }
    }
}
$errorMsg = if ($response.error) { $response.error.message } else { $response.result.content[0].text }
if ($errorMsg -notmatch '(?i)invalid status') {
    throw "Expected error about invalid status, got: $errorMsg"
}
Write-Host "✓ Invalid status correctly rejected" -ForegroundColor Green
