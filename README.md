# personal-blog-infrastructure

Infrastructure-as-code and deployment configuration for
[mikhailbahdashych.me](https://mikhailbahdashych.me) — the blog
([front](https://github.com/mikhailbahdashych/personal-blog-front)), its
[API](https://github.com/mikhailbahdashych/personal-blog-api), and the
[admin panel](https://github.com/mikhailbahdashych/personal-blog-admin).
The app repos build and ship their own images; **everything about where and
how they run lives here.**

```
                    ┌──────────────────────── EC2 ────────────────────────┐
Internet ──443──▶ nginx ──▶ front (Next SSR :3000)   ──▶ api (:4201) ──▶ RDS
                    │  ├──▶ api   (NestJS  :4201)     ◀── revalidate ──┘
                    │  └──▶ admin (static  :80)               │
                    └── certbot (auto-renew)                  └──▶ S3 (assets)
```

- `mikhailbahdashych.me` → front, `api.` → api, `admin.` → admin — three
  Cloudflare A records pointing at one Elastic IP
- One EC2 instance runs the whole stack via Docker Compose from a checkout of
  **this repo** at `/opt/blog`
- RDS PostgreSQL, private; S3 for uploaded assets

## Layout

| Path | What it is |
| --- | --- |
| `terraform/` | The entire AWS footprint: EC2 + Elastic IP, security groups, RDS, key pair, scoped IAM users |
| `docker-compose.prod.yml` | The production stack the host runs |
| `deploy/nginx/` | nginx vhosts (TLS, security headers, admin IP allowlist) |
| `scripts/` | One-time bootstrap, admin-user creation, GitHub-secrets sync |
| `.github/workflows/deploy.yml` | Re-applies compose/nginx changes to the host on push |

## Security model

- **Port 22 is closed.** Every pipeline (and operator) opens it to a single
  `/32` for the duration of the session via a dedicated IAM user that can do
  nothing but add/remove rules on that one security group, then revokes it.
- **RDS is private** — reachable only from the EC2 security group.
- **The admin vhost is IP-allowlisted** in nginx. The allowlist file exists
  only on the host (`deploy/nginx/admin-allowlist.conf`, gitignored) so no
  real address ever reaches git history.
- **Secrets never enter this repo**: Terraform state and `terraform.tfvars`
  are local and gitignored, runtime secrets live in `/opt/blog/.env.prod` on
  the host, CI credentials live in GitHub Actions secrets.
- IMDSv2 is enforced on the instance; S3 and CI IAM users are single-purpose
  with one inline policy each.

## Prerequisites

- Terraform ≥ 1.9, AWS credentials with admin access for provisioning
- `gh` CLI authenticated as the repo owner (for the secrets sync)
- An SSH key pair for deploys: `ssh-keygen -t ed25519 -f deployer_key`
- The assets S3 bucket (default `bahdashych-on-security`) is **pre-existing
  and shared with dev** — Terraform references it but never manages or
  destroys it. It is expected to carry: public-read policy on `prod/*`, a
  deny-insecure-transport statement, GET-only CORS, and public-ACLs blocked.
- Cloudflare A records (apex, `api.`, `admin.`) pointing at the Elastic IP,
  DNS-only (grey cloud) preferred

## Provisioning

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # fill in pubkey + db password
terraform init

# Existing account only: adopt the Elastic IP that DNS already points at,
# instead of allocating a new one. Skip on a truly fresh account.
terraform import aws_eip.blog eipalloc-xxxxxxxxxxxxxxxxx

terraform apply
```

Outputs include everything downstream needs: the public IP, the security
group ID, RDS endpoint / ready-made `DATABASE_URL`, and the access keys for
the two IAM users (`terraform output -raw <name>` for the sensitive ones).

## One-time host bootstrap

Cloud-init installs Docker and clones this repo to `/opt/blog`; give it a
couple of minutes after `apply`. Then, with port 22 opened to your IP:

```bash
# 1. Deliver the two host-only files
scp -i deployer_key .env.prod ubuntu@<ip>:/opt/blog/.env.prod
scp -i deployer_key admin-allowlist.conf ubuntu@<ip>:/opt/blog/deploy/nginx/admin-allowlist.conf

# 2. On the host: authenticate to GHCR (any token that can pull the images),
#    then bootstrap — issues TLS certs (or restores a backup) and starts the stack
ssh -i deployer_key ubuntu@<ip>
  docker login ghcr.io -u <github-user>    # e.g. a fine-grained PAT or `gh auth token`
  CERT_EMAIL=you@example.com /opt/blog/scripts/bootstrap.sh
  /opt/blog/scripts/create-admin.sh you@example.com 'a-long-unique-password'
  docker logout ghcr.io
```

Finally wire the pipelines: `./scripts/sync-github-secrets.sh deployer_key`
pushes the CI credentials, host address, SG ID and pinned SSH host key into
all four repos' Actions secrets.

## Continuous deployment

Four independent pipelines, one per concern:

| Repo | Trigger | What it rolls |
| --- | --- | --- |
| personal-blog-api | push to master | builds image → GHCR, rolls `api`, runs DB migrations |
| personal-blog-front | push to master | builds image → GHCR, rolls `front` |
| personal-blog-admin | push to master | builds image → GHCR, rolls `admin` |
| this repo | push touching compose/nginx | `git pull` at `/opt/blog`, re-applies the stack, reloads nginx |

All four share the same SSH pattern: open port 22 to the runner's IP, act,
revoke. GHCR pulls authenticate with each run's short-lived `GITHUB_TOKEN`;
the host stores no registry credentials.

**Rollback**: pin a specific image (`ghcr.io/…/personal-blog-api:<sha>`) in
`docker-compose.prod.yml`, push — the sync workflow re-applies the stack.

**Terraform is applied manually on purpose** — infra changes are rare,
destructive if wrong, and want a human reading the plan. State is local; if
this ever grows contributors, move it to an S3 backend with locking.
