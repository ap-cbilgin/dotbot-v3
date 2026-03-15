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

# ── Setup: Create ADRs in different states ──
Write-Host "Setup: Creating test ADRs" -ForegroundColor DarkGray

# Create a proposed ADR
$response = Send-McpRequest -Process $Process -Request @{
    jsonrpc = '2.0'
    id = 100
    method = 'tools/call'
    params = @{
        name = 'adr_create'
        arguments = @{
            title = 'List Test - Proposed ADR'
            context = 'Testing list functionality.'
            decision = 'Created for list test.'
            status = 'proposed'
        }
    }
}
$proposedId = ($response.result.content[0].text | ConvertFrom-Json).adr_id
Write-Host "  Created proposed: $proposedId" -ForegroundColor DarkGray

# Create an accepted ADR
$response = Send-McpRequest -Process $Process -Request @{
    jsonrpc = '2.0'
    id = 101
    method = 'tools/call'
    params = @{
        name = 'adr_create'
        arguments = @{
            title = 'List Test - Accepted ADR'
            context = 'Testing list functionality.'
            decision = 'Created for list test.'
            status = 'accepted'
        }
    }
}
$acceptedId = ($response.result.content[0].text | ConvertFrom-Json).adr_id
Write-Host "  Created accepted: $acceptedId" -ForegroundColor DarkGray

# ── Test 1: List all ADRs ──
Write-Host "`nTest: List all ADRs" -ForegroundColor Yellow
$response = Send-McpRequest -Process $Process -Request @{
    jsonrpc = '2.0'
    id = 1
    method = 'tools/call'
    params = @{
        name = 'adr_list'
        arguments = @{}
    }
}
$result = $response.result.content[0].text | ConvertFrom-Json
if (-not $result.success) { throw "Expected success=true" }
if ($result.count -lt 2) { throw "Expected at least 2 ADRs, got $($result.count)" }
Write-Host "✓ Listed $($result.count) ADRs" -ForegroundColor Green

# ── Test 2: List ADRs filtered by status ──
Write-Host "`nTest: List proposed ADRs only" -ForegroundColor Yellow
$response = Send-McpRequest -Process $Process -Request @{
    jsonrpc = '2.0'
    id = 2
    method = 'tools/call'
    params = @{
        name = 'adr_list'
        arguments = @{
            status = 'proposed'
        }
    }
}
$result = $response.result.content[0].text | ConvertFrom-Json
if (-not $result.success) { throw "Expected success=true" }
# All returned ADRs should be proposed
foreach ($adr in $result.adrs) {
    if ($adr.status -ne 'proposed') {
        throw "Expected all ADRs to be proposed, found $($adr.status)"
    }
}
Write-Host "✓ Filtered to $($result.count) proposed ADRs" -ForegroundColor Green

# ── Test 3: List accepted ADRs ──
Write-Host "`nTest: List accepted ADRs only" -ForegroundColor Yellow
$response = Send-McpRequest -Process $Process -Request @{
    jsonrpc = '2.0'
    id = 3
    method = 'tools/call'
    params = @{
        name = 'adr_list'
        arguments = @{
            status = 'accepted'
        }
    }
}
$result = $response.result.content[0].text | ConvertFrom-Json
if (-not $result.success) { throw "Expected success=true" }
foreach ($adr in $result.adrs) {
    if ($adr.status -ne 'accepted') {
        throw "Expected all ADRs to be accepted, found $($adr.status)"
    }
}
Write-Host "✓ Filtered to $($result.count) accepted ADRs" -ForegroundColor Green

# ── Test 4: ADRs are sorted by id ──
Write-Host "`nTest: ADRs are sorted by id" -ForegroundColor Yellow
$response = Send-McpRequest -Process $Process -Request @{
    jsonrpc = '2.0'
    id = 4
    method = 'tools/call'
    params = @{
        name = 'adr_list'
        arguments = @{}
    }
}
$result = $response.result.content[0].text | ConvertFrom-Json
$ids = @($result.adrs | ForEach-Object { $_.id })
$sorted = @($ids | Sort-Object)
for ($i = 0; $i -lt $ids.Count; $i++) {
    if ($ids[$i] -ne $sorted[$i]) {
        throw "ADRs not sorted by id: expected $($sorted[$i]) at position $i, got $($ids[$i])"
    }
}
Write-Host "✓ ADRs are sorted by id" -ForegroundColor Green

# ── Test 5: Each ADR has expected fields ──
Write-Host "`nTest: ADR list entries have expected fields" -ForegroundColor Yellow
$firstAdr = $result.adrs[0]
$requiredFields = @('id', 'title', 'status', 'file_path', 'file_name')
foreach ($field in $requiredFields) {
    if (-not $firstAdr.PSObject.Properties[$field]) {
        throw "Missing required field: $field"
    }
}
Write-Host "✓ All expected fields present" -ForegroundColor Green

# ── Test 6: YAML quoted titles are correctly unquoted in list ──
Write-Host "`nTest: YAML quoted titles are unquoted in list" -ForegroundColor Yellow
$matchedAdr = $result.adrs | Where-Object { $_.id -eq $proposedId }
if ($matchedAdr -and $matchedAdr.title -match "^'") {
    throw "Title still has YAML quotes: $($matchedAdr.title)"
}
Write-Host "✓ Titles correctly unquoted in list" -ForegroundColor Green
