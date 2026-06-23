<#
.SYNOPSIS
    Test script to flip the MyGlue visibility on an IT Glue document.
    Document: https://unified.itglue.com/1568612/docs/23035761
    
    OrgID:    1568612
    DocID:    23035761
#>

# ---------------------------------------------------------------
# CONFIG - drop your key in here
# ---------------------------------------------------------------
$ApiKey     = "ITG.c076b293675908068cc42c4ea38b8177._wu40xeNeUw_OxiA9fM78nx4FIpHVIMmi4klFkc7Khf4SGnLr0bD-Sf-Gn3XLiYg"
$BaseUrl    = "https://unified.itglue.com"
$OrgId      = "1568612"
$DocId      = "23035761"

# ---------------------------------------------------------------
# Headers (required on every call)
# ---------------------------------------------------------------
$Headers = @{
    "x-api-key"    = $ApiKey
    "Content-Type" = "application/vnd.api+json"
}

# ---------------------------------------------------------------
# STEP 1 - GET current document state so we can see all attributes
# ---------------------------------------------------------------
Write-Host "`n=== STEP 1: GET current document attributes ===" -ForegroundColor Cyan

$GetUrl = "$BaseUrl/organizations/$OrgId/documents/$DocId"

try {
    $Response = Invoke-RestMethod -Uri $GetUrl -Method GET -Headers $Headers
    $Attrs = $Response.data.attributes

    Write-Host "Document Name : $($Attrs.name)"
    Write-Host "Created At    : $($Attrs.'created-at')"
    Write-Host "Updated At    : $($Attrs.'updated-at')"
    Write-Host ""
    Write-Host "--- Full attributes (so we can spot the MyGlue field) ---" -ForegroundColor Yellow
    $Attrs | ConvertTo-Json -Depth 5
}
catch {
    Write-Host "GET failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ErrorDetails.Message
}

# ---------------------------------------------------------------
# STEP 2 - PATCH attempt: try common attribute names for MyGlue visibility
#          We don't know the exact field name yet - this surfaces the error
#          or succeeds and tells us which one IT Glue accepts
# ---------------------------------------------------------------
Write-Host "`n=== STEP 2: PATCH - attempt to set MyGlue visibility ===" -ForegroundColor Cyan

$PatchUrl = "$BaseUrl/organizations/$OrgId/documents/$DocId"

# Try the most likely attribute names - check the GET response above
# to confirm which one is actually returned before assuming
$PatchBody = @{
    data = @{
        type = "documents"
        id   = $DocId
        attributes = @{
            "my-glue-enabled" = $true   # most likely candidate based on IT Glue naming conventions
            # Uncomment alternatives below if the above doesn't work:
            # "myglue-enabled"   = $true
            # "shared-to-myglue" = $true
            # "my-glue"          = $true
        }
    }
} | ConvertTo-Json -Depth 5

try {
    $PatchResponse = Invoke-RestMethod -Uri $PatchUrl -Method PATCH -Headers $Headers -Body $PatchBody
    Write-Host "PATCH succeeded!" -ForegroundColor Green
    Write-Host "Updated attributes:" -ForegroundColor Yellow
    $PatchResponse.data.attributes | ConvertTo-Json -Depth 5
}
catch {
    Write-Host "PATCH failed (expected if attribute name is wrong or not patchable):" -ForegroundColor Yellow
    Write-Host $_.ErrorDetails.Message
}

# ---------------------------------------------------------------
# STEP 3 - Try the dedicated /publish endpoint
#          This is listed in the IT Glue API docs as a separate action
# ---------------------------------------------------------------
Write-Host "`n=== STEP 3: POST to /publish endpoint ===" -ForegroundColor Cyan

$PublishUrl = "$BaseUrl/organizations/$OrgId/documents/$DocId/publish"

# Publish body - try with my_glue scope
$PublishBody = @{
    data = @{
        type = "documents"
        id   = $DocId
        attributes = @{
            "published" = $true
        }
    }
} | ConvertTo-Json -Depth 5

try {
    $PublishResponse = Invoke-RestMethod -Uri $PublishUrl -Method POST -Headers $Headers -Body $PublishBody
    Write-Host "Publish POST succeeded!" -ForegroundColor Green
    $PublishResponse | ConvertTo-Json -Depth 5
}
catch {
    Write-Host "Publish POST failed:" -ForegroundColor Yellow
    Write-Host $_.ErrorDetails.Message
}

Write-Host "`n=== Done. Check output above to identify the correct approach. ===" -ForegroundColor Cyan