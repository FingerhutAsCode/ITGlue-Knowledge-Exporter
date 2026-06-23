#requires -Version 7
<#
.SYNOPSIS
    Processes an extracted IT Glue export: discovers document HTML files, computes
    a per-document version hash, and gives you a single place to drop in your
    cleanup + HTML/PDF generation.

.DESCRIPTION
    The export tree lays content out per organization with documents rendered as
    HTML alongside their assets. The exact layout can vary between tenants, so this
    discovers the HTML files rather than hard-coding paths. Inspect one real export
    and tighten the filter / path parsing to suit.

    Returns one record per document including a SHA-256 content hash - that hash is
    your stable version signal for the DocumentMapping table, so distribution only
    pushes documents that actually changed.

.EXAMPLE
    $docs = ./Convert-ITGlueExport.ps1 -ExtractedPath ./work/extracted -OutDir ./artifacts
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $ExtractedPath,
    [string] $OutDir = './artifacts'
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $ExtractedPath)) { throw "Extracted path not found: $ExtractedPath" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# Resolve to an absolute path so relative-path computation below is correct
# (Get-ChildItem returns absolute FullName values).
$root = (Resolve-Path -Path $ExtractedPath).Path

$htmlFiles = Get-ChildItem -Path $root -Recurse -File -Filter *.html
Write-Host "[$(Get-Date -Format o)] Found $($htmlFiles.Count) HTML file(s) to process."

$results = foreach ($file in $htmlFiles) {
    # Stable identity (path relative to the export root) + version signal.
    $relativePath = $file.FullName.Substring($root.Length).TrimStart('/', '\')
    $contentHash  = (Get-FileHash -Path $file.FullName -Algorithm SHA256).Hash

    # ------------------------------------------------------------------------
    # TODO: your existing cleanup + rendering goes here. Typical per-document flow:
    #   $html = Get-Content -Path $file.FullName -Raw
    #   1. Clean the HTML
    #   2. Resolve/rewrite image references to durable URLs
    #   3. Write a cleaned .html and a .pdf into $OutDir
    # Set $htmlArtifact / $pdfArtifact to the output paths you produce.
    # ------------------------------------------------------------------------
    $htmlArtifact = $null
    $pdfArtifact  = $null

    [pscustomobject]@{
        SourcePath   = $relativePath
        ContentHash  = $contentHash
        HtmlArtifact = $htmlArtifact
        PdfArtifact  = $pdfArtifact
    }
}

Write-Host "[$(Get-Date -Format o)] Processing complete ($($results.Count) document(s))."
return $results
