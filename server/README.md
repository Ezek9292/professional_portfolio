# Portfolio server (edonkor.dev)

Hetzner server `personalPortfolio`, `37.27.34.194`. This folder sets it up from your PC; it is not uploaded
to the website (the deploy workflow excludes it). District Games will be set up separately later.

| File | Runs on | What it does |
|---|---|---|
| `setup-server.ps1` | your PC (VS Code terminal) | logs in, runs the setup, uploads the site, checks it |
| `setup-portfolio.sh` | the server (uploaded for you) | Nginx, `deploy` user, firewall, fail2ban, certificate |

## 1. Get a clean server (Hetzner Cloud Console)

1. **Backups / Snapshots**: if one is from before 18 Nov 2026, you can restore it instead.
   Otherwise: server → **Rebuild** → **Ubuntu 24.04**.
2. Note the root password Hetzner shows (or emails) after the rebuild.

## 2. Run the setup

In the VS Code terminal, from the repo folder:

```powershell
powershell -ExecutionPolicy Bypass -File server\setup-server.ps1 -ResetHostKey
```

- `-ResetHostKey` is needed once after a rebuild (the server's fingerprint changed).
- The first time, it creates your admin key `~/.ssh/edonkor_admin` and asks for the **root password** once to
  install it. After that it logs in with the key.
- It ends by printing the GitHub secrets to set.

Upload only the website files again (no setup):

```powershell
powershell -ExecutionPolicy Bypass -File server\setup-server.ps1 -DeployOnly
```

## 3. GitHub secrets (professional_portfolio)

| Secret | Value |
|---|---|
| `SSH_HOST` | `37.27.34.194` |
| `SSH_USER` | `deploy` |
| `DEPLOY_PATH` | `/var/www/portfolio` |
| `SSH_PRIVATE_KEY` | unchanged (`~/.ssh/github_deploy`) |

Then **Actions → Deploy to server → Enable workflow**, and push.

## 4. Cloudflare

The server starts with a self-signed certificate, so set **SSL/TLS → Overview → Full** (not "strict").
To upgrade to **Full (strict)**:

1. **SSL/TLS → Origin Server → Create certificate** (hostnames `edonkor.dev`, `*.edonkor.dev`).
2. Log in (`ssh -i $HOME\.ssh\edonkor_admin root@37.27.34.194`) and paste the certificate into
   `/etc/ssl/cloudflare/edonkor.dev.pem` and the private key into `/etc/ssl/cloudflare/edonkor.dev.key`.
3. `nginx -t && systemctl reload nginx`, then switch Cloudflare to **Full (strict)**.

## 5. Turn off password login (once the admin key works)

```bash
printf 'PasswordAuthentication no\nPermitRootLogin prohibit-password\n' > /etc/ssh/sshd_config.d/99-hardening.conf
sshd -t && systemctl reload ssh
```
