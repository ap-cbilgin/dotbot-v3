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

# ── Setup: Create an ADR to test against ──
Write-Host "Setup: Creating test ADR" -ForegroundColor DarkGray
$response = Send-McpRequest -Process $Process -Request @{
    jsonrpc = '2.0'
    id = 100
    method = 'tools/call'
    params = @{
        name = 'adr_create'
        arguments = @{
            title = "Use Docker: It's the team's choice"
            context = 'Need containerization for deployment.'
            decision = 'Use Docker for all services.'
            rationale = 'Docker provides consistent environments.'
            consequences = 'Team must learn Docker basics.'
            alternatives_considered = 'Podman, bare metal.'
            source = "architect's review"
        }
    }
}
$created = $response.result.content[0].text | ConvertFrom-Json
$testAdrId = $created.adr_id
Write-Host "  Created $testAdrId" -ForegroundColor DarkGray

# ── Test 1: Get ADR by ID ──
Write-Host "`nTest: Get ADR by ID" -ForegroundColor Yellow
$response = Send-McpRequest -Process $Process -Request @{
    jsonrpc = '2.0'
    id = 1
    method = 'tools/call'
    params = @{
        name = 'adr_get'
        arguments = @{
            adr_id = $testAdrId
        }
    }
}
$result = $response.result.content[0].text | ConvertFrom-Json
if (-not $result.success) { throw "Expected success=true" }
if ($result.id -ne $testAdrId) { throw "Expected id=$testAdrId, got $($result.id)" }
if ($result.status -ne 'proposed') { throw "Expected status=proposed" }
Write-Host "✓ ADR retrieved successfully" -ForegroundColor Green

# ── Test 2: YAML single-quoted title is correctly unquoted on read ──
Write-Host "`nTest: YAML quoted title is correctly parsed" -ForegroundColor Yellow
if ($result.title -ne "Use Docker: It's the team's choice") {
    throw "Expected unquoted title 'Use Docker: It''s the team''s choice', got '$($result.title)'"
}
Write-Host "✓ Title with quotes correctly round-tripped" -ForegroundColor Green

# ── Test 3: YAML quoted source is correctly unquoted on read ──
Write-Host "`nTest: YAML quoted source is correctly parsed" -ForegroundColor Yellow
if ($result.source -ne "architect's review") {
    throw "Expected unquoted source 'architect''s review', got '$($result.source)'"
}
Write-Host "✓ Source with quotes correctly round-tripped" -ForegroundColor Green

# ── Test 4: Sections are parsed ──
Write-Host "`nTest: Body sections are parsed" -ForegroundColor Yellow
if (-not $result.sections) { throw "Expected sections to be populated" }
if (-not $result.sections.Context) { throw "Expected Context section" }
if (-not $result.sections.Decision) { throw "Expected Decision section" }
if (-not $result.sections.Rationale) { throw "Expected Rationale section" }
if (-not $result.sections.Consequences) { throw "Expected Consequences section" }
if (-not $result.sections.'Alternatives Considered') { throw "Expected Alternatives Considered section" }
Write-Host "✓ All sections parsed correctly" -ForegroundColor Green

# ── Test 5: Get non-existent ADR should fail ──
Write-Host "`nTest: Get non-existent ADR should fail" -ForegroundColor Yellow
$response = Send-McpRequest -Process $Process -Request @{
    jsonrpc = '2.0'
    id = 5
    method = 'tools/call'
    params = @{
        name = 'adr_get'
        arguments = @{
            adr_id = 'adr-999'
        }
    }
}
$errorMsg = if ($response.error) { $response.error.message } else { $response.result.content[0].text }
if ($errorMsg -notmatch 'not found') {
    throw "Expected 'not found' error, got: $errorMsg"
}
Write-Host "✓ Non-existent ADR correctly returns error" -ForegroundColor Green

# ── Test 6: Get ADR without adr_id should fail ──
Write-Host "`nTest: Get ADR without adr_id should fail" -ForegroundColor Yellow
$response = Send-McpRequest -Process $Process -Request @{
    jsonrpc = '2.0'
    id = 6
    method = 'tools/call'
    params = @{
        name = 'adr_get'
        arguments = @{}
    }
}
$errorMsg = if ($response.error) { $response.error.message } else { $response.result.content[0].text }
if ($errorMsg -notmatch 'required') {
    throw "Expected 'required' error, got: $errorMsg"
}
Write-Host "✓ Missing adr_id correctly rejected" -ForegroundColor Green
