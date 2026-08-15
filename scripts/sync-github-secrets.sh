#!/usr/bin/env bash
# Pushes the deploy secrets every pipeline needs into the GitHub repos, sourced
# from the Terraform outputs. Run locally from the repo root after `terraform
# apply`, authenticated to gh as the repo owner.
#
# Usage: ./scripts/sync-github-secrets.sh /path/to/deployer_private_key
set -euo pipefail

[[ $# -eq 1 && -f "$1" ]] || { echo "usage: $0 <path-to-deployer-private-key>"; exit 1; }
SSH_KEY_FILE="$1"

OWNER=mikhailbahdashych
APP_REPOS=(personal-blog-api personal-blog-front personal-blog-admin)
ALL_REPOS=("${APP_REPOS[@]}" personal-blog-infrastructure)

cd "$(dirname "$0")/../terraform"
HOST=$(terraform output -raw public_ip)
SG_ID=$(terraform output -raw ec2_security_group_id)
CI_KEY_ID=$(terraform output -raw ci_access_key_id)
CI_KEY_SECRET=$(terraform output -raw ci_secret_access_key)
REGION=eu-central-1

# Pin the host's SSH key: ephemeral Actions runners have no TOFU history, so
# without this any host answering on the IP would be trusted.
HOST_KEY=$(ssh-keyscan -t ed25519 "$HOST" 2>/dev/null)
[[ -n "$HOST_KEY" ]] || { echo "ERROR: ssh-keyscan got nothing from $HOST"; exit 1; }

for repo in "${ALL_REPOS[@]}"; do
  echo "--- $OWNER/$repo"
  gh secret set AWS_ACCESS_KEY_ID     --repo "$OWNER/$repo" --body "$CI_KEY_ID"
  gh secret set AWS_SECRET_ACCESS_KEY --repo "$OWNER/$repo" --body "$CI_KEY_SECRET"
  gh secret set AWS_REGION            --repo "$OWNER/$repo" --body "$REGION"
  gh secret set EC2_HOST              --repo "$OWNER/$repo" --body "$HOST"
  gh secret set EC2_SG_ID             --repo "$OWNER/$repo" --body "$SG_ID"
  gh secret set EC2_SSH_USER          --repo "$OWNER/$repo" --body "ubuntu"
  gh secret set EC2_SSH_KEY           --repo "$OWNER/$repo" < "$SSH_KEY_FILE"
  gh secret set EC2_SSH_HOST_KEY      --repo "$OWNER/$repo" --body "$HOST_KEY"
done

# Build-time public URLs baked into the frontend / admin bundles.
gh secret set NEXT_PUBLIC_SITE_URL --repo "$OWNER/personal-blog-front" --body "https://mikhailbahdashych.me"
gh secret set NEXT_PUBLIC_API_URL  --repo "$OWNER/personal-blog-front" --body "https://api.mikhailbahdashych.me"
gh secret set VITE_API_URL         --repo "$OWNER/personal-blog-admin" --body "https://api.mikhailbahdashych.me"

echo "Done."
