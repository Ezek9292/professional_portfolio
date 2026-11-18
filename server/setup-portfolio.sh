#!/usr/bin/env bash
# Server-side setup for the portfolio (edonkor.dev). Runs ON the server as root.
# You don't run this yourself: server/setup-server.ps1 uploads and runs it.
# Safe to run again: every step checks whether it is already done.
set -euo pipefail

DEPLOY_USER=deploy
SITE_DIR=/var/www/portfolio
CERT=/etc/ssl/cloudflare/edonkor.dev.pem
CERT_KEY=/etc/ssl/cloudflare/edonkor.dev.key
# Public half of the key GitHub Actions uses (SSH_PRIVATE_KEY secret).
GITHUB_DEPLOY_KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOEN8Gsxb8bYtI+EPMedbjKT6ajBNHgPZXfK3k0v3xhC github-deploy'

[ "$(id -u)" -eq 0 ] || { echo "Run this as root"; exit 1; }

echo "==> System packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get upgrade -y -q
apt-get install -y -q nginx rsync ufw fail2ban openssl

echo "==> Deploy user (GitHub Actions logs in as '$DEPLOY_USER', not root)"
id "$DEPLOY_USER" >/dev/null 2>&1 || adduser --disabled-password --gecos "" "$DEPLOY_USER"
install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh"
AK="/home/$DEPLOY_USER/.ssh/authorized_keys"
touch "$AK"
grep -qF "$GITHUB_DEPLOY_KEY" "$AK" || echo "$GITHUB_DEPLOY_KEY" >> "$AK"
chown "$DEPLOY_USER:$DEPLOY_USER" "$AK"
chmod 600 "$AK"

echo "==> Site folder $SITE_DIR"
install -d -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$SITE_DIR"

echo "==> TLS certificate"
# Temporary self-signed certificate so HTTPS works behind Cloudflare (SSL mode "Full").
# Replace it with a Cloudflare Origin Certificate later (see server/README.md).
if [ ! -f "$CERT" ]; then
  install -d -m 755 /etc/ssl/cloudflare
  openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
    -subj "/CN=edonkor.dev" -keyout "$CERT_KEY" -out "$CERT" 2>/dev/null
  chmod 600 "$CERT_KEY"
fi

echo "==> Nginx"
cat > /etc/nginx/sites-available/portfolio <<'NGINX'
server {
    listen 80;
    listen [::]:80;
    server_name edonkor.dev www.edonkor.dev;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name edonkor.dev www.edonkor.dev;
    ssl_certificate     /etc/ssl/cloudflare/edonkor.dev.pem;
    ssl_certificate_key /etc/ssl/cloudflare/edonkor.dev.key;

    root /var/www/portfolio;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }
    location ~* \.(css|js|webp|png|jpg|jpeg|svg|pdf|woff2?)$ {
        expires 7d;
        add_header Cache-Control "public";
    }
}
NGINX
ln -sf /etc/nginx/sites-available/portfolio /etc/nginx/sites-enabled/portfolio
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable nginx >/dev/null
systemctl restart nginx

echo "==> Firewall"
ufw allow OpenSSH >/dev/null
ufw allow 'Nginx Full' >/dev/null
ufw --force enable >/dev/null

echo "==> Brute-force protection (fail2ban)"
systemctl enable --now fail2ban >/dev/null

echo "==> Server setup done"
