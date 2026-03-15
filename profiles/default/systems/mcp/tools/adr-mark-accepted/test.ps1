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

# ── Setup: Create a proposed ADR ──
Write-Host "Setup: Creating proposed ADR for acceptance test" -ForegroundColor DarkGray
$response = Send-McpRequest -Process $Process -Request @{
    jsonrpc = '2.0'
    id = 100
    method = 'tools/call'
    params = @{
        name = 'adr_create'
        arguments = @{
            title = 'Accept Test ADR'
            context = 'Testing the accept transition.'
            decision = 'This ADR will be accepted.'
            status = 'proposed'
        }
    }
}
$created = $response.result.content[0].text | ConvertFrom-Json
$testAdrId = $created.adr_id
Write-Host "  Created $testAdrId (proposed)" -ForegroundColor DarkGray

# ── Test 1: Accept a proposed ADR ──
Write-Host "`nTest: Accept a proposed ADR" -ForegroundColor Yellow
$response = Send-McpRequest -Process $Process -Request @{
    jsonrpc = '2.0'
    id = 1
    method = 'tools/call'
    params = @{
        name = 'adr_mark_accepted'
        arguments = @{
            adr_id = $testAdrId
        }
    }
}
$result = $response.result.content[0].text | ConvertFrom-Json
if (-not $result.success) { throw "Expected success=true" }
if ($result.file_path -notlike '*accepted*') { throw "Expected file moved to accepted directory" }
Write-Host "✓ ADR accepted, file moved to accepted/" -ForegroundColor Green

# ── Test 2: Verify status updated in frontmatter ──
Write-Host "`nTest: Verify status is accepted in frontmatter" -ForegroundColor Yellow
$response = Send-McpRequest -Process $Process -Request @{
    jsonrpc = '2.0'
    id = 2
    method = 'tools/call'
    params = @{
        name = 'adr_get'
        arguments = @{ adr_id = $testAdrId }
    }
}
$fetched = $response.result.content[0].text | ConvertFrom-Json
if ($fetched.status -ne 'accepted') { throw "Expected status=accepted, got $($fetched.status)" }
Write-Host "✓ Status is accepted" -ForegroundColor Green

# ── Test 3: Accept already-accepted ADR is idempotent ──
Write-Host "`nTest: Accept already-accepted ADR" -ForegroundColor Yellow
$response = Send-McpRequest -Process $Process -Request @{
    jsonrpc = '2.0'
    id = 3
    method = 'tools/call'
    params = @{
        name = 'adr_mark_accepted'
        arguments = @{
            adr_id = $testAdrId
        }
    }
}
$result = $response.result.content[0].text | ConvertFrom-Json
if (-not $result.success) { throw "Expected success=true for idempotent accept" }
if ($result.message -notmatch 'already accepted') { throw "Expected 'already accepted' message" }
Write-Host "✓ Already-accepted ADR handled gracefully" -ForegroundColor Green

# ── Test 4: Accept non-existent ADR should fail ──
Write-Host "`nTest: Accept non-existent ADR should fail" -ForegroundColor Yellow
$response = Send-McpRequest -Process $Process -Request @{
    jsonrpc = '2.0'
    id = 4
    method = 'tools/call'
    params = @{
        name = 'adr_mark_accepted'
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

# ── Test 5: Original file no longer exists in proposed/ ──
Write-Host "`nTest: Original file removed from proposed/" -ForegroundColor Yellow
$proposedPath = $created.file_path
if (Test-Path $proposedPath) {
    throw "Original file should have been removed from proposed/"
}
Write-Host "✓ Original file cleaned up from proposed/" -ForegroundColor Green
