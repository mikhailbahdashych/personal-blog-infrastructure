#!/usr/bin/env bash
# One-time host bootstrap. Run ON the EC2 host, as a user in the docker group,
# after Terraform has created the infrastructure and cloud-init has cloned this
# repo to /opt/blog. Idempotent — safe to re-run after a failure.
#
# Expects, before running:
#   /opt/blog/.env.prod                            (see .env.prod.example)
#   /opt/blog/deploy/nginx/admin-allowlist.conf    (see the .example next to it)
#   docker login ghcr.io                           (any token able to pull the images)
#
# Usage:
#   CERT_EMAIL=you@example.com ./scripts/bootstrap.sh
#   ./scripts/bootstrap.sh /path/to/letsencrypt-backup.tar.gz   # restore certs instead of issuing
set -euo pipefail

cd /opt/blog
COMPOSE="docker compose -f docker-compose.prod.yml"
DOMAINS=(mikhailbahdashych.me api.mikhailbahdashych.me admin.mikhailbahdashych.me)
LE_BACKUP="${1:-}"

[[ -f .env.prod ]] || { echo "ERROR: /opt/blog/.env.prod is missing"; exit 1; }
[[ -f deploy/nginx/admin-allowlist.conf ]] || { echo "ERROR: deploy/nginx/admin-allowlist.conf is missing"; exit 1; }

# The compose project is named after this directory ("blog"), so its volumes
# are blog_*. Pre-create the certificate volume so certbot can fill it before
# the stack (and nginx, which refuses to start certless) comes up.
docker volume create blog_letsencrypt >/dev/null

if docker run --rm -v blog_letsencrypt:/le alpine test -e "/le/live/${DOMAINS[0]}/fullchain.pem"; then
  echo "Certificates already present — skipping issuance."
elif [[ -n "$LE_BACKUP" ]]; then
  echo "Restoring certificates from $LE_BACKUP ..."
  docker run --rm -i -v blog_letsencrypt:/le alpine tar xzf - -C /le < "$LE_BACKUP"
else
  [[ -n "${CERT_EMAIL:-}" ]] || { echo "ERROR: set CERT_EMAIL for the Let's Encrypt registration"; exit 1; }
  echo "Issuing certificates via standalone HTTP-01 (port 80 must be free) ..."
  docker run --rm -p 80:80 -v blog_letsencrypt:/etc/letsencrypt \
    certbot/certbot certonly --standalone --non-interactive --agree-tos --no-eff-email \
    --email "$CERT_EMAIL" \
    $(printf -- '-d %s ' "${DOMAINS[@]}")
fi

echo "Starting the stack ..."
$COMPOSE up -d

echo "Waiting for the API, then applying migrations ..."
for i in $(seq 1 30); do
  if $COMPOSE exec -T api node dist/db/migrate.js; then
    break
  elif [[ "$i" == 30 ]]; then
    echo "ERROR: migrations still failing after 30 attempts"; exit 1
  fi
  sleep 2
done

echo
echo "Bootstrap complete. Create the first admin user with:"
echo "  ./scripts/create-admin.sh you@example.com 'a-long-unique-password'"
