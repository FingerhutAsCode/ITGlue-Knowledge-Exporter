#requires -Version 7
<#
.SYNOPSIS
    Triggers a FULL IT Glue account export, polls until it is ready, and returns
    the export ID and download URL.

.DESCRIPTION
    POSTs to /exports with no organization-id, which IT Glue treats as an export
    of all organizations. It then polls GET /exports/{id} until a download URL is
    present, retrying transient 429/5xx responses with backoff.

.EXAMPLE
    $export = ./Start-ITGlueExport.ps1 -ApiKey $env:ITGLUE_API_KEY -ZipPassword $env:ITGLUE_ZIP_PW
    $export.ExportId
    $export.DownloadUrl

.NOTES
    Verify the two attribute names flagged below against your developer docs:
    https://api.itglue.com/developer/#exports
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $ApiKey,

    # EU partners: https://api.eu.itglue.com
    [string] $BaseUrl = 'https://api.itglue.com',

    # Recommended for automated exports. Omit for an unencrypted archive.
    [string] $ZipPassword,

    [int] $PollIntervalSeconds = 30,
    [int] $TimeoutMinutes = 60
)

$ErrorActionPreference = 'Stop'

$headers = @{
    'x-api-key'    = $ApiKey
    'Content-Type' = 'application/vnd.api+json'
}

function Invoke-ITGlue {
    param(
        [string] $Method,
        [string] $Uri,
        [hashtable] $Headers,
        [string] $Body
    )
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try {
            if ($Body) {
                return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers -Body $Body
            }
            return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers
        }
        catch {
            $code = $null
            $resp = $_.Exception.Response
            if ($resp) { try { $code = [int]$resp.StatusCode } catch { $code = $null } }

            if ($code -eq 429 -or ($code -ge 500 -and $code -le 599)) {
                $wait = [math]::Min(60, [math]::Pow(2, $attempt) * 5)
                Write-Warning "Transient $code from IT Glue; retry $attempt of 5 in ${wait}s."
                Start-Sleep -Seconds $wait
                continue
            }
            throw
        }
    }
    throw "IT Glue request failed after retries: $Method $Uri"
}

# --- Create the export ------------------------------------------------------
# Omitting organization-id => export ALL organizations (full account export).
# VERIFY: the 'zip-password' attribute name against your developer docs. Some
# tenants may also accept an 'include' attribute to scope export contents.
$attributes = @{}
if ($ZipPassword) {
    $attributes['zip-password'] = $ZipPassword
}

$body = @{
    data = @{
        type       = 'exports'
        attributes = $attributes
    }
} | ConvertTo-Json -Depth 6

Write-Host "[$(Get-Date -Format o)] Requesting full account export..."
$create   = Invoke-ITGlue -Method Post -Uri "$BaseUrl/exports" -Headers $headers -Body $body
$exportId = $create.data.id
if (-not $exportId) {
    throw "Export creation did not return an ID. Response: $($create | ConvertTo-Json -Depth 6)"
}
Write-Host "[$(Get-Date -Format o)] Export $exportId created. Polling for completion..."

# --- Poll until ready -------------------------------------------------------
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
while ($true) {
    Start-Sleep -Seconds $PollIntervalSeconds

    $status = Invoke-ITGlue -Method Get -Uri "$BaseUrl/exports/$exportId" -Headers $headers
    $attr   = $status.data.attributes

    # A populated download URL is the authoritative "ready" signal. We also read a
    # textual status if one is present. VERIFY these attribute names if your tenant
    # returns something different (e.g. 'download-url' vs 'url', 'status' vs 'state').
    $downloadUrl = $attr.'download-url'
    $state       = $attr.status ?? $attr.state

    Write-Host "[$(Get-Date -Format o)] export $exportId status='$state' downloadReady=$([bool]$downloadUrl)"

    if ($downloadUrl) {
        Write-Host "[$(Get-Date -Format o)] Export ready."
        return [pscustomobject]@{
            ExportId    = $exportId
            DownloadUrl = $downloadUrl
            Status      = $state
        }
    }
    if ($state -and $state -match 'fail|error') {
        throw "Export $exportId reported a failure state: '$state'."
    }
    if ((Get-Date) -gt $deadline) {
        throw "Timed out after $TimeoutMinutes minutes waiting for export $exportId."
    }
}
