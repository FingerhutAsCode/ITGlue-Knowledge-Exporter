<#
.SYNOPSIS
  Converts an IT Glue Export ZIP (documents in HTML + attachments) into standardized PDFs per document.

.DESCRIPTION
  - Extracts IT Glue export ZIP
  - Loads documents.csv
  - Locates each document's HTML export
  - Rewrites attachment/image references to local file paths
  - Applies a branded HTML template + CSS (Phase 2 styling)
  - Renders PDFs using wkhtmltopdf (no watermark; free)

.NOTES
  IT Glue export includes Documents in HTML format and Attachments. (See IT Glue export documentation.)
  wkhtmltopdf requires --enable-local-file-access to load local images.

.EXAMPLE
Converts all documents in the export.zip to PDFs in C:\Temp\ITGlue-PDF.

.\Convert-ITGlueExportToPdf.ps1 -ExportZipPath "C:\Temp\ITGlue\export.zip"
#>

[CmdletBinding()]
param(
  # Path to an IT Glue export.zip you downloaded (UI or API)
  [Parameter(Mandatory)]
  [string]$ExportZipPath,

  # Where to extract and build outputs
  [Parameter()]
  [string]$WorkingRoot = "C:\Temp\ITGlue-Export",

  # Where to write PDFs
  [Parameter()]
  [string]$OutputRoot = "C:\Temp\ITGlue-PDF",

  # Path to wkhtmltopdf.exe
  [Parameter()]
  [string]$WkhtmltopdfPath = "C:\Program Files\wkhtmltopdf\bin\wkhtmltopdf.exe",

  # Optional: If your export was encrypted (ZipCrypto), supply the password here.
  # NOTE: Windows Expand-Archive cannot decrypt. This script will try 7z if present.
  [Parameter()]
  [string]$ZipPassword = "",

  # Optional: Include a simple PDF footer with page numbers
  [Parameter()]
  [switch]$IncludePageNumbers,

  # Template root directory (contains template folders)
  [Parameter()]
  [string]$TemplateRoot = (Join-Path $PSScriptRoot "templates"),

  # Template folder name under TemplateRoot
  [Parameter()]
  [string]$TemplateName = "pdf-standard",

  # Brand text shown in the styled header/footer
  [Parameter()]
  [string]$BrandName = "IT Glue",

  # Optional: process only specific document IDs (comma-separated or repeated)
  [Parameter()]
  [string[]]$DocumentIds,

  # When set, skip documents whose 'help center' column in documents.csv is not 'Yes'.
  # Pass -AllDocuments to process everything in the export regardless of that flag.
  [Parameter()]
  [switch]$AllDocuments,

  # Maximum length for output base names (helps avoid Windows path length failures)
  [Parameter()]
  [int]$OutputNameMaxLength = 80
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Warn($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }

function Ensure-Dir([string]$Path) {
  if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
}

function Get-AbsoluteFileUri([string]$Path) {
  # wkhtmltopdf is happiest with file:/// URIs
  $full = (Resolve-Path $Path).Path
  return ("file:///" + ($full -replace "\\","/"))
}

function Expand-ZipSmart {
  param(
    [Parameter(Mandatory)][string]$Zip,
    [Parameter(Mandatory)][string]$Destination,
    [Parameter()][string]$Password = ""
  )

  Ensure-Dir $Destination

  # Clean destination for idempotence
  if (Test-Path $Destination) {
    Get-ChildItem -Path $Destination -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
  }
  Ensure-Dir $Destination

  # If no password, try Expand-Archive first
  if ([string]::IsNullOrEmpty($Password)) {
    Write-Info "Expanding ZIP with Expand-Archive..."
    Expand-Archive -Path $Zip -DestinationPath $Destination -Force
    return
  }

  # Encrypted ZIP: Expand-Archive won't work. Try 7z if available.
  $sevenZip = @("C:\Program Files\7-Zip\7z.exe", "C:\Program Files (x86)\7-Zip\7z.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1

  if (-not $sevenZip) {
    throw "ZIP appears encrypted and 7-Zip was not found. Install 7-Zip or provide an unencrypted export."
  }

  Write-Info "Expanding encrypted ZIP with 7-Zip..."
  & $sevenZip x $Zip "-p$Password" "-o$Destination" -y | Out-Null
}

function Find-DocumentsCsv([string]$Root) {
  $candidates = Get-ChildItem -Path $Root -Recurse -Filter "documents.csv" -File -ErrorAction SilentlyContinue
  if (-not $candidates) { throw "Could not find documents.csv under $Root" }
  return $candidates[0].FullName
}

function Find-AttachmentsRoot([string]$Root) {
  # Common patterns: attachments\documents\<docId>\...
  $att = Get-ChildItem -Path $Root -Recurse -Directory -ErrorAction SilentlyContinue |
         Where-Object { $_.Name -match "^attachments$" } |
         Select-Object -First 1
  if ($att) { return $att.FullName }
  return $null
}

function Find-DocumentHtmlFile {
  param(
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)][string]$DocumentId,
    [Parameter()][string]$DocumentName = ""
  )

  # Try the most likely patterns first: id.html, <id>\index.html, etc.
  $preferred = @(
    (Join-Path -Path $Root -ChildPath ("documents\{0}.html" -f $DocumentId))
    (Join-Path -Path $Root -ChildPath ("documents\{0}\index.html" -f $DocumentId))
    (Join-Path -Path $Root -ChildPath ("{0}.html" -f $DocumentId))
  )

  foreach ($p in $preferred) {
    if (Test-Path $p) { return (Resolve-Path $p).Path }
  }

  # IT Glue exports commonly use: documents\DOC-<orgId>-<docId> <title>\<title>.html
  $documentsRoot = Join-Path -Path $Root -ChildPath "documents"
  if (Test-Path $documentsRoot) {
    $docFolder = Get-ChildItem -Path $documentsRoot -Directory -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -like ("DOC-*-{0} *" -f $DocumentId) } |
                 Select-Object -First 1
    if ($docFolder) {
      $htmlInFolder = Get-ChildItem -Path $docFolder.FullName -Filter "*.html" -File -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($htmlInFolder) { return $htmlInFolder.FullName }
    }
  }

  # Fallback: search all html files for one that contains a strong hint.
  $htmls = Get-ChildItem -Path $Root -Recurse -Filter "*.html" -File -ErrorAction SilentlyContinue

  # Best-effort matching: any part of the full path contains doc id
  $match = $htmls | Where-Object { $_.FullName -match [regex]::Escape($DocumentId) } | Select-Object -First 1
  if ($match) { return $match.FullName }

  # Next fallback: filename contains sanitized doc name
  if (-not [string]::IsNullOrWhiteSpace($DocumentName)) {
    $safe = ($DocumentName -replace "[^a-zA-Z0-9]+","-").Trim("-")
    $match2 = $htmls | Where-Object { $_.Name -match [regex]::Escape($safe) } | Select-Object -First 1
    if ($match2) { return $match2.FullName }

    # Final fallback: normalized alphanumeric title comparison (handles slash/underscore/space differences)
    $normalizedDocName = ($DocumentName -replace "[^a-zA-Z0-9]","").ToLowerInvariant()
    if (-not [string]::IsNullOrWhiteSpace($normalizedDocName)) {
      $match3 = $htmls | Where-Object {
        $normalizedBase = ($_.BaseName -replace "[^a-zA-Z0-9]","").ToLowerInvariant()
        ($normalizedBase.Contains($normalizedDocName) -or $normalizedDocName.Contains($normalizedBase))
      } | Select-Object -First 1
      if ($match3) { return $match3.FullName }
    }
  }

  return $null
}

function Rewrite-ResourceUrlsToLocal {
  param(
    [Parameter(Mandatory)][string]$Html,
    [Parameter(Mandatory)][string]$ExportRoot,
    [Parameter(Mandatory)][string]$DocumentId,
    [Parameter(Mandatory)][string]$SourceHtmlPath
  )

  $sourceDocDir = Split-Path -Path $SourceHtmlPath -Parent
  $sourceDocUri = Get-AbsoluteFileUri -Path $sourceDocDir

  # Try to locate attachment folder for this doc:
  # attachments\documents\<docId>\...
  $attachmentsRoot = Find-AttachmentsRoot -Root $ExportRoot
  $docAttachFolder = $null

  if ($attachmentsRoot) {
    $docAttachFolder = Get-ChildItem -Path $attachmentsRoot -Recurse -Directory -ErrorAction SilentlyContinue |
                       Where-Object { $_.FullName -match "\\documents\\$DocumentId($|\\)" } |
                       Select-Object -First 1
  }

  $out = $Html
  if ($docAttachFolder) {
    $docAttachPath = $docAttachFolder.FullName
    $docAttachUri  = Get-AbsoluteFileUri -Path $docAttachPath

    # Rewrite common relative references:
    # src="attachments/..." or src="/attachments/..."
    $out = $out -replace ('src=["'']\/?attachments\/documents\/' + [regex]::Escape($DocumentId) + '\/'), ('src="' + $docAttachUri + '/')
    $out = $out -replace ('href=["'']\/?attachments\/documents\/' + [regex]::Escape($DocumentId) + '\/'), ('href="' + $docAttachUri + '/')
  }

  # Also handle generic: /attachments/ -> local attachments root
  if ($attachmentsRoot) {
    $attUri = Get-AbsoluteFileUri -Path $attachmentsRoot
    $out = $out -replace 'src=["'']\/attachments\/', ('src="' + $attUri + '/')
    $out = $out -replace 'href=["'']\/attachments\/', ('href="' + $attUri + '/')
  }

  # Handle IT Glue document-local assets and preserve nested path segments, e.g.
  # /1570439/docs/5108706/images/7572724 -> file:///.../<doc-folder>/1570439/docs/5108706/images/7572724
  $out = $out -replace 'src=["'']\/?(\d+\/docs\/\d+\/[^"''\s>]+)', ('src="' + $sourceDocUri + '/$1')
  $out = $out -replace 'href=["'']\/?(\d+\/docs\/\d+\/[^"''\s>]+)', ('href="' + $sourceDocUri + '/$1')

  # Handle relative assets that lived beside the original HTML (thumbnail/*, assets/*, etc.).
  # This intentionally skips absolute URLs, anchors, and already rewritten file:// paths.
  $out = $out -replace 'src=["''](?![a-z]+:|\/|#|file:\/\/)([^"'']+)', ('src="' + $sourceDocUri + '/$1')
  $out = $out -replace 'href=["''](?![a-z]+:|\/|#|file:\/\/)([^"'']+)', ('href="' + $sourceDocUri + '/$1')

  return $out
}

function Get-StylingTemplate {
  param(
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)][string]$Name
  )

  $templateDir = Join-Path -Path $Root -ChildPath $Name
  $layoutPath = Join-Path -Path $templateDir -ChildPath "layout.html"
  $cssPath = Join-Path -Path $templateDir -ChildPath "styles.css"

  if (-not (Test-Path $layoutPath)) { throw "Template layout not found: $layoutPath" }
  if (-not (Test-Path $cssPath)) { throw "Template stylesheet not found: $cssPath" }

  return [pscustomobject]@{
    TemplateDir = $templateDir
    LayoutHtml  = Get-Content -Path $layoutPath -Raw -Encoding utf8
    StylesCss   = Get-Content -Path $cssPath -Raw -Encoding utf8
  }
}

function Resolve-CssCustomProperties {
  param(
    [Parameter(Mandatory)][string]$Css
  )

  $rootMatch = [regex]::Match($Css, '(?s):root\s*\{(?<body>.*?)\}')
  if (-not $rootMatch.Success) { return $Css }

  $rootBody = $rootMatch.Groups['body'].Value
  $vars = @{}

  foreach ($m in [regex]::Matches($rootBody, '--([A-Za-z0-9\-_]+)\s*:\s*([^;]+);')) {
    $vars['--' + $m.Groups[1].Value] = $m.Groups[2].Value.Trim()
  }

  if ($vars.Count -eq 0) { return $Css }

  $resolved = $Css
  for ($i = 0; $i -lt 3; $i++) {
    $before = $resolved
    $resolved = [regex]::Replace(
      $resolved,
      'var\(\s*(--[A-Za-z0-9\-_]+)\s*(?:,\s*([^\)]+))?\)',
      {
        param($match)
        $name = $match.Groups[1].Value
        $fallback = $match.Groups[2].Value
        if ($vars.ContainsKey($name)) { return $vars[$name] }
        if (-not [string]::IsNullOrWhiteSpace($fallback)) { return $fallback.Trim() }
        return $match.Value
      }
    )

    if ($resolved -eq $before) { break }
  }

  return $resolved
}

function Build-StyledHtml {
  param(
    [Parameter(Mandatory)][string]$Title,
    [Parameter(Mandatory)][string]$BodyHtml,
    [Parameter(Mandatory)][string]$LayoutHtml,
    [Parameter(Mandatory)][string]$StylesCss,
    [Parameter()][string]$LogoUri = "",
    [Parameter()][string]$OrgName = "",
    [Parameter()][string]$DocId = "",
    [Parameter()][string]$Brand = "",
    [Parameter()][string]$SourceHtmlPath = ""
  )

  $stamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  $titleEncoded = [System.Net.WebUtility]::HtmlEncode($Title)
  $orgEncoded = [System.Net.WebUtility]::HtmlEncode($OrgName)
  $docIdEncoded = [System.Net.WebUtility]::HtmlEncode($DocId)
  $brandEncoded = [System.Net.WebUtility]::HtmlEncode($Brand)
  $sourceEncoded = [System.Net.WebUtility]::HtmlEncode($SourceHtmlPath)
  $generatedEncoded = [System.Net.WebUtility]::HtmlEncode($stamp)
  $resolvedCss = Resolve-CssCustomProperties -Css $StylesCss

  $out = $LayoutHtml
  $out = $out.Replace("{{STYLE_INLINE}}", $resolvedCss)
  $out = $out.Replace("{{TITLE}}", $titleEncoded)
  $out = $out.Replace("{{ORG_NAME}}", $orgEncoded)
  $out = $out.Replace("{{DOC_ID}}", $docIdEncoded)
  $out = $out.Replace("{{BRAND_NAME}}", $brandEncoded)
  $out = $out.Replace("{{GENERATED_AT}}", $generatedEncoded)
  $out = $out.Replace("{{SOURCE_HTML_PATH}}", $sourceEncoded)
  $out = $out.Replace("{{LOGO_URI}}", $LogoUri)
  $out = $out.Replace("{{BODY_HTML}}", $BodyHtml)
  return $out
}

function New-SafeOutputBaseName {
  param(
    [Parameter(Mandatory)][string]$DocumentName,
    [Parameter(Mandatory)][string]$DocumentId,
    [Parameter()][int]$MaxLength = 80
  )

  $raw = ($DocumentName -replace '[<>:"/\\|?*]+','_').Trim()
  if ([string]::IsNullOrWhiteSpace($raw)) { $raw = "document" }
  $raw = ($raw -replace '\s+',' ')

  $idSuffix = "_" + $DocumentId
  $budget = [Math]::Max(12, $MaxLength - $idSuffix.Length)
  $base = $raw
  if ($base.Length -gt $budget) {
    $base = $base.Substring(0, $budget).Trim()
    $base = $base.TrimEnd('.', ' ')
  }
  if ([string]::IsNullOrWhiteSpace($base)) { $base = "document" }

  return ($base + $idSuffix)
}

function Render-PdfWkhtmltopdf {
  param(
    [Parameter(Mandatory)][string]$Wkhtmltopdf,
    [Parameter(Mandatory)][string]$InputHtmlPath,
    [Parameter(Mandatory)][string]$OutputPdfPath,
    [Parameter()][switch]$PageNumbers
  )

  $wkArgs = @(
    "--enable-local-file-access",
    "--print-media-type",
    "--margin-top", "15mm",
    "--margin-bottom", "15mm",
    "--margin-left", "12mm",
    "--margin-right", "12mm"
  )

  if ($PageNumbers) {
    $wkArgs += @("--footer-right", "Page [page] of [toPage]", "--footer-font-size", "9")
  }

  $wkArgs += @($InputHtmlPath, $OutputPdfPath)

  & $Wkhtmltopdf @wkArgs | Out-Null
}

# ----------------------------
# MAIN
# ----------------------------
if (-not (Test-Path $ExportZipPath)) { throw "ExportZipPath not found: $ExportZipPath" }
if (-not (Test-Path $WkhtmltopdfPath)) { throw "wkhtmltopdf not found: $WkhtmltopdfPath" }
if (-not (Test-Path $TemplateRoot)) { throw "TemplateRoot not found: $TemplateRoot" }
if ($OutputNameMaxLength -lt 20) { throw "OutputNameMaxLength must be 20 or greater." }

Ensure-Dir $WorkingRoot
Ensure-Dir $OutputRoot

Write-Info "PHASE 1/3 - Extract export ZIP"
Expand-ZipSmart -Zip $ExportZipPath -Destination $WorkingRoot -Password $ZipPassword

$documentsCsv = Find-DocumentsCsv -Root $WorkingRoot
Write-Info "Found documents.csv: $documentsCsv"

$docs = Import-Csv -Path $documentsCsv

if ($DocumentIds -and $DocumentIds.Count -gt 0) {
  $requestedIds = @($DocumentIds | ForEach-Object { [string]$_ })
  $docs = @($docs | Where-Object { $requestedIds -contains [string]$_.id })

  if ($docs.Count -eq 0) {
    throw ("No matching document IDs were found in documents.csv: {0}" -f ($requestedIds -join ", "))
  }

  Write-Info ("Document filter active. Processing IDs: {0}" -f ($requestedIds -join ", "))
}

if (-not $AllDocuments) {
  $beforeCount = $docs.Count
  $docs = @($docs | Where-Object { $_."help center" -ieq "Yes" })
  $skipped = $beforeCount - $docs.Count
  Write-Info ("Help Center filter: {0} to process, {1} skipped." -f $docs.Count, $skipped)

  if ($docs.Count -eq 0) {
    Write-Warn "No documents have 'help center = Yes' in the export. Use -AllDocuments to bypass."
    exit 0
  }
}

$template = Get-StylingTemplate -Root $TemplateRoot -Name $TemplateName
$logoUri = ""
$logoPath = Join-Path -Path $template.TemplateDir -ChildPath "logo.jpg"
if (Test-Path $logoPath) {
  $logoUri = Get-AbsoluteFileUri -Path $logoPath
}

# Create a run log
$logPath = Join-Path $OutputRoot "conversion-log.csv"
"DocumentId,DocumentName,Status,OutputPdf,Notes" | Out-File -Encoding utf8 $logPath

Write-Info ("Documents found in CSV: {0}" -f $docs.Count)
Write-Info ("Using template: {0}" -f $template.TemplateDir)

foreach ($d in $docs) {
  $docId   = $d.id
  $docName = $d.name
  $docTitle = (($docName -replace "_", " ") -replace "\s+", " ").Trim()
  if ([string]::IsNullOrWhiteSpace($docTitle)) { $docTitle = $docName }

  # Some exports include org name/id fields; if missing we just leave blank
  $orgName = ""
  if ($d.PSObject.Properties.Name -contains "organization_name") { $orgName = $d.organization_name }
  elseif ($d.PSObject.Properties.Name -contains "organization-name") { $orgName = $d."organization-name" }

  try {
    Write-Info "Processing doc $docId - $docTitle"

    Write-Info "PHASE 2/3 - Normalize and style HTML"
    $htmlPath = Find-DocumentHtmlFile -Root $WorkingRoot -DocumentId $docId -DocumentName $docName
    if (-not $htmlPath) {
      Write-Warn "No HTML found for doc $docId. Skipping."
      "$docId,""{0}"",MissingHtml,,""No HTML export located""" -f ($docName -replace '"','""') | Add-Content $logPath
      continue
    }

    $raw = Get-Content -Path $htmlPath -Raw -Encoding utf8
    if ([string]::IsNullOrWhiteSpace($raw)) {
      Write-Warn "Empty HTML content for doc $docId. Skipping."
      "$docId,""{0}"",EmptyHtml,,""HTML file exists but has no content: {1}""" -f ($docName -replace '"','""'), (($htmlPath -replace '"','""')) | Add-Content $logPath
      continue
    }

    # Rewrite images/links to local attachment paths so wkhtmltopdf can load them
    $fixed = Rewrite-ResourceUrlsToLocal -Html $raw -ExportRoot $WorkingRoot -DocumentId $docId -SourceHtmlPath $htmlPath

    # Apply consistent branding template/CSS
    $standardHtml = Build-StyledHtml -Title $docTitle -BodyHtml $fixed -LayoutHtml $template.LayoutHtml -StylesCss $template.StylesCss -LogoUri $logoUri -OrgName $orgName -DocId $docId -Brand $BrandName -SourceHtmlPath $htmlPath

    # Write temp HTML near output for traceability
    $safeName = New-SafeOutputBaseName -DocumentName $docName -DocumentId $docId -MaxLength $OutputNameMaxLength
    $outDir   = Join-Path $OutputRoot $safeName
    Ensure-Dir $outDir

    $outHtml = Join-Path $outDir ("{0}.html" -f $safeName)
    $outPdf  = Join-Path $outDir ("{0}.pdf"  -f $safeName)

    $standardHtml | Out-File -Path $outHtml -Encoding utf8

    # Render PDF
    Write-Info "PHASE 3/3 - Convert styled HTML to PDF"
    Render-PdfWkhtmltopdf -Wkhtmltopdf $WkhtmltopdfPath -InputHtmlPath $outHtml -OutputPdfPath $outPdf -PageNumbers:$IncludePageNumbers

    "$docId,""{0}"",Success,""{1}"","""" " -f ($docName -replace '"','""'), ($outPdf -replace '"','""') | Add-Content $logPath
  }
  catch {
    $err = $_.Exception.Message -replace '"','""'
    Write-Warn "Failed doc $docId : $err"
    "$docId,""{0}"",Failed,,""{1}""" -f ($docName -replace '"','""'), $err | Add-Content $logPath
  }
}

Write-Info "Done."
Write-Info "Log: $logPath"
Write-Info "Output root: $OutputRoot"

if (Test-Path $logPath) {
  $summaryRows = Import-Csv -Path $logPath
  $summaryByStatus = $summaryRows | Group-Object -Property Status | Sort-Object Name

  Write-Info "Run Summary"
  foreach ($group in $summaryByStatus) {
    Write-Info ("  {0}: {1}" -f $group.Name, $group.Count)
  }

  $failed = @($summaryRows | Where-Object { $_.Status -eq "Failed" })
  if ($failed.Count -gt 0) {
    Write-Warn "Top failure reasons:"
    $failed |
      Group-Object -Property Notes |
      Sort-Object Count -Descending |
      Select-Object -First 5 |
      ForEach-Object {
        Write-Warn ("  x{0} - {1}" -f $_.Count, $_.Name)
      }
  }
}