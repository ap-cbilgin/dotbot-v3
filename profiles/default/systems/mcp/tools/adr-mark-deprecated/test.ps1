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
Write-Host "Setup: Creating proposed ADR for deprecation test" -ForegroundColor DarkGray
$response = Send-McpRequest -Process $Process -Request @{
    jsonrpc = '2.0'
    id = 100
    method = 'tools/call'
    params = @{
        name = 'adr_create'
        arguments = @{
            title = 'Deprecate Test ADR'
            context = 'Testing the deprecation transition.'
            decision = 'This ADR will be deprecated.'
            status = 'proposed'
        }
    }
}
$created = $response.result.content[0].text | ConvertFrom-Json
$testAdrId = $created.adr_id
Write-Host "  Created $testAdrId (proposed)" -ForegroundColor DarkGray

# ── Test 1: Deprecate a proposed ADR ──
Write-Host "`nTest: Deprecate a proposed ADR" -ForegroundColor Yellow
$response = Send-McpRequest -Process $Process -Request @{
    jsonrpc = '2.0'
    id = 1
    method = 'tools/call'
    params = @{
        name = 'adr_mark_deprecated'
        arguments = @{
            adr_id = $testAdrId
            reason = 'Technology is no longer supported by vendor.'
        }
    }
}
$result = $response.result.content[0].text | ConvertFrom-Json
if (-not $result.success) { throw "Expected success=true" }
if ($result.file_path -notlike '*deprecated*') { throw "Expected file moved to deprecated directory" }
Write-Host "✓ ADR deprecated, file moved to deprecated/" -ForegroundColor Green

# ── Test 2: Verify status and deprecation note ──
Write-Host "`nTest: Verify deprecated status and deprecation note" -ForegroundColor Yellow
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
if ($fetched.status -ne 'deprecated') { throw "Expected status=deprecated, got $($fetched.status)" }
if (-not $fetched.sections.'Deprecation Note') {
    throw "Expected Deprecation Note section"
}
if ($fetched.sections.'Deprecation Note' -notmatch 'no longer supported') {
    throw "Deprecation note content incorrect"
}
Write-Host "✓ Status is deprecated, deprecation note present" -ForegroundColor Green

# ── Test 3: Deprecate an accepted ADR ──
Write-Host "`nTest: Deprecate an accepted ADR" -ForegroundColor Yellow

# Create accepted ADR
$response = Send-McpRequest -Process $Process -Request @{
    jsonrpc = '2.0'
    id = 101
    method = 'tools/call'
    params = @{
        name = 'adr_create'
        arguments = @{
            title = 'Accepted Then Deprecated'
            context = 'Will be accepted then deprecated.'
            decision = 'Temporary decision.'
            status = 'accepted'
        }
    }
}
$acceptedId = ($response.result.content[0].text | ConvertFrom-Json).adr_id

$response = Send-McpRequest -Process $Process -Request @{
    jsonrpc = '2.0'
    id = 31
    method = 'tools/call'
    params = @{
        name = 'adr_mark_deprecated'
        arguments = @{
            adr_id = $acceptedId
        }
    }
}
$result = $response.result.content[0].text | ConvertFrom-Json
if (-not $result.success) { throw "Expected success=true" }
if ($result.file_path -notlike '*deprecated*') { throw "Expected file moved to deprecated directory" }
Write-Host "✓ Accepted ADR deprecated successfully" -ForegroundColor Green

# ── Test 4: Original file removed from source directory ──
Write-Host "`nTest: Original file removed from proposed/" -ForegroundColor Yellow
if (Test-Path $created.file_path) {
    throw "Original file should have been removed from proposed/"
}
Write-Host "✓ Original file cleaned up" -ForegroundColor Green

# ── Test 5: Deprecate non-existent ADR should fail ──
Write-Host "`nTest: Deprecate non-existent ADR should fail" -ForegroundColor Yellow
$response = Send-McpRequest -Process $Process -Request @{
    jsonrpc = '2.0'
    id = 5
    method = 'tools/call'
    params = @{
        name = 'adr_mark_deprecated'
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
