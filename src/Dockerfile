# PowerShell 7 on Debian — lightweight Linux base for the export/generation job.
FROM mcr.microsoft.com/powershell:lts-debian-12

# ---------------------------------------------------------------------------
# System packages. Add whatever your processing/rendering step needs here.
# Example: if your PDF rendering uses wkhtmltopdf, uncomment the block below.
# RUN apt-get update \
#  && apt-get install -y --no-install-recommends wkhtmltopdf unzip \
#  && rm -rf /var/lib/apt/lists/*
# ---------------------------------------------------------------------------

# PowerShell modules. Az.Accounts/Az.Storage make managed-identity auth easy.
# Trim these if you authenticate to the storage REST APIs directly.
RUN pwsh -NoProfile -Command " \
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted; \
    Install-Module -Name Az.Accounts -Scope AllUsers -Force; \
    Install-Module -Name Az.Storage -Scope AllUsers -Force"

WORKDIR /app
COPY scripts/ /app/

# entrypoint.ps1 is the placeholder the job runs once per day. Replace its TODO
# sections with your export pull, document processing, and blob/table writes
# (or have it call your own scripts copied in above).
ENTRYPOINT ["pwsh", "-NoProfile", "-File", "/app/entrypoint.ps1"]
