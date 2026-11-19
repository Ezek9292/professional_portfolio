<#
.SYNOPSIS
  Sets up the portfolio server and deploys the site, from your own PC.

.DESCRIPTION
  Run from the repo folder in the VS Code terminal:

    powershell -ExecutionPolicy Bypass -File server\setup-server.ps1

  What it does:
    1. Makes sure you have an admin SSH key (~/.ssh/edonkor_admin) and that the server accepts it.
       The first time, ssh asks for the server's root password once.
    2. Uploads server/setup-portfolio.sh and runs it on the server (Nginx, deploy user, firewall...).
    3. Uploads the website files to /var/www/portfolio.
    4. Checks that the site responds.

  Options:
    -ServerIp 1.2.3.4   another server (default 37.27.34.194)
    -ResetHostKey       use after rebuilding the server in Hetzner (forgets its old fingerprint)
    -DeployOnly         skip the setup, only upload the website files
#>
param(
    [string]$ServerIp = "37.27.34.194",
    [string]$KeyPath = "$HOME\.ssh\edonkor_admin",
    [switch]$ResetHostKey,
    [switch]$DeployOnly
)

# "Continue", not "Stop": in Windows PowerShell 5.1, "Stop" turns ssh's harmless stderr
# warnings into fatal errors. Every native call checks $LASTEXITCODE instead.
$ErrorActionPreference = "Continue"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$Target = "root@$ServerIp"
$SiteDir = "/var/www/portfolio"
$SiteFiles = @("index.html", "styles.css", "script.js", "assets")

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Fail($msg) { Write-Host "`nERROR: $msg" -ForegroundColor Red; exit 1 }

# Run ssh/scp and stop the script if they fail.
function Invoke-Native {
    param([string]$Exe, [string[]]$Arguments)
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { Fail "$Exe exited with code $LASTEXITCODE" }
}

$SshOpts = @("-i", $KeyPath, "-o", "IdentitiesOnly=yes", "-o", "StrictHostKeyChecking=accept-new")

# --- Checks ------------------------------------------------------------------
Step "Checking tools and files"
foreach ($tool in "ssh", "scp", "ssh-keygen") {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Fail "$tool not found. Install 'OpenSSH Client' (Settings > System > Optional features)."
    }
}
foreach ($f in $SiteFiles + "server\setup-portfolio.sh") {
    if (-not (Test-Path (Join-Path $RepoRoot $f))) { Fail "Missing $f in $RepoRoot" }
}
Write-Host "OK"

if ($ResetHostKey) {
    Step "Forgetting the old host key for $ServerIp"
    & ssh-keygen -R $ServerIp | Out-Null
}

# --- 1. Admin key --------------------------------------------------------------
Step "Admin SSH key ($KeyPath)"
if (-not (Test-Path $KeyPath)) {
    Write-Host "No admin key yet, creating one (press Enter twice for no passphrase)."
    & ssh-keygen -t ed25519 -f $KeyPath -C "edonkor-admin"
    if ($LASTEXITCODE -ne 0) { Fail "Could not create the key" }
}
$PubKey = (Get-Content "$KeyPath.pub" -Raw).Trim()

# A key with a passphrase can't be used non-interactively. Load it into ssh-agent so the
# passphrase is typed once; without the agent, ssh asks for it on every connection.
& ssh-keygen -y -P "" -f $KeyPath *> $null
if ($LASTEXITCODE -ne 0) {
    $agent = Get-Service ssh-agent -ErrorAction SilentlyContinue
    if ($agent -and $agent.Status -eq "Running") {
        Write-Host "Your key has a passphrase; adding it to ssh-agent (type the passphrase once)."
        & ssh-add $KeyPath
    } else {
        Write-Host ("Your key has a passphrase and ssh-agent isn't running, so you'll be asked for the`n" +
                    "passphrase several times. To type it only once, run in an ADMIN PowerShell:`n" +
                    "  Set-Service ssh-agent -StartupType Automatic; Start-Service ssh-agent") -ForegroundColor Yellow
    }
}

# Key-only login test. PreferredAuthentications=publickey (not BatchMode) still lets ssh
# ask for the key's passphrase, but never falls back to a password prompt.
function Test-KeyLogin {
    & ssh @SshOpts -o PreferredAuthentications=publickey -o ConnectTimeout=10 -o LogLevel=QUIET $Target "true"
    return ($LASTEXITCODE -eq 0)
}

if (-not (Test-KeyLogin)) {
    # Probe without credentials: a healthy server answers "Permission denied (...)";
    # a broken one just closes the connection or times out.
    $probe = (& ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=10 `
              -o PreferredAuthentications=none $Target "true" 2>&1 | Out-String)
    if ($probe -notmatch "Permission denied") {
        Fail ("The server's SSH isn't working, so no password or key can log in:`n  $($probe.Trim())`n" +
              "  This is the server damaged by the bad deploy. Rebuild it first:`n" +
              "  Hetzner Cloud Console > server > Rebuild > Ubuntu 24.04, then rerun with -ResetHostKey")
    }
    Write-Host "The server doesn't accept the admin key yet. Installing it now;"
    Write-Host "ssh will ask for the server's ROOT PASSWORD (from Hetzner) once." -ForegroundColor Yellow
    $install = "mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && " +
               "(grep -qF '$PubKey' ~/.ssh/authorized_keys || echo '$PubKey' >> ~/.ssh/authorized_keys) && " +
               "chmod 600 ~/.ssh/authorized_keys"
    Write-Host "If it says the password has expired, type the current password, then a NEW password twice." -ForegroundColor Yellow
    # Up to 2 tries: after a forced password change the server closes the session
    # before running the command, so the second try installs the key with the new password.
    $installed = $false
    for ($try = 1; $try -le 2 -and -not $installed; $try++) {
        if ($try -eq 2) { Write-Host "`nLogging in again with your NEW password to finish installing the key..." -ForegroundColor Yellow }
        # -t gives ssh a terminal, which the forced password change needs.
        & ssh -t -o StrictHostKeyChecking=accept-new -o PreferredAuthentications=password,keyboard-interactive $Target $install
        $installed = Test-KeyLogin
    }
    if (-not $installed) {
        Fail ("Could not install the admin key on $Target.`n" +
              "  - If you see 'REMOTE HOST IDENTIFICATION HAS CHANGED', rerun with -ResetHostKey`n" +
              "  - If you don't know the root password: Hetzner Console > server > Rescue > Reset root password")
    }
}
Write-Host "Logged in with the admin key"

# --- 2. Server setup -------------------------------------------------------------
if (-not $DeployOnly) {
    Step "Uploading and running setup-portfolio.sh on the server (takes a few minutes)"
    Invoke-Native scp ($SshOpts + @((Join-Path $RepoRoot "server\setup-portfolio.sh"), "${Target}:/root/setup-portfolio.sh"))
    # sed strips Windows line endings in case git converted the file.
    Invoke-Native ssh ($SshOpts + @($Target, "sed -i 's/\r$//' /root/setup-portfolio.sh && bash /root/setup-portfolio.sh"))
}

# --- 3. Deploy the site ------------------------------------------------------------
Step "Uploading website files to $SiteDir"
$Upload = "/tmp/portfolio-upload"
Invoke-Native ssh ($SshOpts + @($Target, "rm -rf $Upload && mkdir -p $Upload"))
$LocalPaths = $SiteFiles | ForEach-Object { Join-Path $RepoRoot $_ }
Invoke-Native scp ($SshOpts + @("-r") + $LocalPaths + @("${Target}:$Upload/"))
# Replace the site contents only inside $SiteDir, hand ownership to the deploy user and
# reset permissions: scp from Windows can create folders Nginx (www-data) can't open.
Invoke-Native ssh ($SshOpts + @($Target, ("test -d $SiteDir && rsync -a --delete $Upload/ $SiteDir/ && " +
    "chown -R deploy:deploy $SiteDir && find $SiteDir -type d -exec chmod 755 {} + && " +
    "find $SiteDir -type f -exec chmod 644 {} + && rm -rf $Upload")))

# --- 4. Check ------------------------------------------------------------------------
Step "Checking the site on the server"
$code = & curl.exe -sk -o NUL -w "%{http_code}" --max-time 15 --resolve "edonkor.dev:443:$ServerIp" "https://edonkor.dev/"
if ($code -eq "200") {
    Write-Host "Server answers 200 for edonkor.dev" -ForegroundColor Green
} else {
    Write-Host "Server answered '$code' (expected 200). Check: ssh -i $KeyPath $Target 'nginx -t; tail /var/log/nginx/error.log'" -ForegroundColor Yellow
}

Write-Host @"

Done. Remaining one-time steps:
  1. GitHub > professional_portfolio > Settings > Secrets and variables > Actions:
       SSH_HOST    = $ServerIp
       SSH_USER    = deploy
       DEPLOY_PATH = $SiteDir
       (SSH_PRIVATE_KEY stays as it is)
  2. Cloudflare > SSL/TLS > Overview: set to Full (see server/README.md to upgrade to Full (strict)).
  3. Re-enable the 'Deploy to server' workflow in GitHub Actions, then push.

Log in to the server any time with:
  ssh -i $KeyPath $Target
"@ -ForegroundColor Green
