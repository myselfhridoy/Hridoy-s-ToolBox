# scripts/generate_keystore.ps1
param(
    [string]$KeystoreName = "upload-keystore.jks",
    [string]$Alias = "upload"
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Android Release Keystore Generator     " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Check for keytool
if (-not (Get-Command keytool -ErrorAction SilentlyContinue)) {
    Write-Host "Error: 'keytool' not found in PATH." -ForegroundColor Red
    Write-Host "Please ensure Java JDK is installed." -ForegroundColor Yellow
    exit 1
}

$repoRoot = Resolve-Path "$PSScriptRoot\.."
Set-Location $repoRoot

if (Test-Path $KeystoreName) {
    Write-Host "Warning: '$KeystoreName' already exists in $repoRoot." -ForegroundColor Yellow
    $confirm = Read-Host "Do you want to overwrite it? (y/N)"
    if ($confirm -ne 'y' -and $confirm -ne 'Y') {
        Write-Host "Operation cancelled." -ForegroundColor Yellow
        exit 0
    }
    Remove-Item $KeystoreName -Force
}

# Prompt for password
$secPass = Read-Host "Enter a strong password for your keystore (min 6 chars)" -AsSecureString
$plainPass = [System.Net.NetworkCredential]::new("", $secPass).Password

if ([string]::IsNullOrWhiteSpace($plainPass) -or $plainPass.Length -lt 6) {
    Write-Host "Password must be at least 6 characters long." -ForegroundColor Red
    exit 1
}

Write-Host "`nGenerating keystore: $KeystoreName with alias '$Alias'..." -ForegroundColor Cyan

& keytool -genkeypair -v `
    -keystore $KeystoreName `
    -alias $Alias `
    -keyalg RSA `
    -keysize 2048 `
    -validity 10000 `
    -storetype PKCS12 `
    -storepass $plainPass `
    -keypass $plainPass `
    -dname "CN=Hridoy, OU=HridoyToolBox, O=Hridoy, L=Dhaka, ST=Dhaka, C=BD"

if ($LASTEXITCODE -ne 0) {
    Write-Host "`nFailed to generate keystore." -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host "`n[SUCCESS] Keystore created: $KeystoreName" -ForegroundColor Green

# Generate Base64
$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path $KeystoreName))
$base64String = [System.Convert]::ToBase64String($bytes)

$base64File = "keystore_base64.txt"
[System.IO.File]::WriteAllText((Join-Path $repoRoot $base64File), $base64String)

try {
    Set-Clipboard -Value $base64String
    Write-Host "[SUCCESS] Base64 string copied to clipboard!" -ForegroundColor Green
} catch {
    # Clipboard might not be available in non-interactive/remote sessions
}

Write-Host "`n=================================================================" -ForegroundColor Cyan
Write-Host "  NEXT STEP: Add Secrets to GitHub Repository" -ForegroundColor Yellow
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "Go to: https://github.com/<your-username>/<your-repo>/settings/secrets/actions"
Write-Host ""
Write-Host "Add the following 3 Repository Secrets:" -ForegroundColor White
Write-Host "  1. KEYSTORE_BASE64   -> (Content inside '$base64File' - already copied to clipboard)" -ForegroundColor Green
Write-Host "  2. KEYSTORE_PASSWORD -> (The password you just entered)" -ForegroundColor Green
Write-Host "  3. KEY_ALIAS         -> $Alias" -ForegroundColor Green
Write-Host ""
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "IMPORTANT: Keep '$KeystoreName' safe as a backup! It is gitignored." -ForegroundColor Magenta
Write-Host "=================================================================" -ForegroundColor Cyan

