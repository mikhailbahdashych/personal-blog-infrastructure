# Personal Blog Infrastructure

Infrastructure-as-code and deployment configuration for
[mikhailbahdashych.me](https://mikhailbahdashych.me) — the blog
([front](https://github.com/mikhailbahdashych/personal-blog-front)), its
[API](https://github.com/mikhailbahdashych/personal-blog-api), and the
[admin panel](https://github.com/mikhailbahdashych/personal-blog-admin).
The app repos build and ship their own images; **everything about where and
how they run lives here.**

```
                              Internet
                                 │
              mikhailbahdashych.me · api.* · admin.*
              (three DNS records → one Elastic IP)
                                 │
┌───────────────────────── EC2 · Docker Compose ─────────────────────────┐
│                                │                                       │
│                              nginx                                     │
│              TLS + security headers, routes by hostname                │
│              (admin.* is IP-allowlisted before auth)                   │
│                                                                        │
│        apex ▼               api.* ▼              admin.* ▼             │
│    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐            │
│    │    front     │    │     api      │    │    admin     │            │
│    │ Next.js SSR  │    │    NestJS    │    │  static SPA  │            │
│    └──────────────┘    └──────┬───────┘    └──────────────┘            │
│                               │                                        │
│    certbot — auto-renews the TLS certificate                           │
└───────────────────────────────┼────────────────────────────────────────┘
                                │
                 ┌──────────────┴──────────────┐
                 ▼                             ▼
         RDS PostgreSQL                    S3 bucket
        (content, private)             (uploaded assets)
```

Not pictured: `front` fetches page data from `api` over the internal Docker
network, and `api` calls `front` back to invalidate cached pages after admin
edits — that traffic never leaves the instance.

## Repository layout

| Path | What it is |
| --- | --- |
| `terraform/` | The entire AWS footprint: EC2 + Elastic IP, security groups, RDS, key pair, scoped IAM users |
| `docker-compose.prod.yml` | The production stack the host runs |
| `deploy/nginx/` | nginx vhosts (TLS, security headers, admin IP allowlist) |
| `scripts/` | One-time bootstrap, admin-user creation, GitHub-secrets sync |
| `.github/workflows/deploy.yml` | Re-applies compose/nginx changes to the host on push |

---

## How it works

### The moving parts

**One EC2 instance** (`t3a.small`, Ubuntu 24.04) runs everything. Its first
boot is scripted by `terraform/cloud-init.sh.tftpl`: install Docker (with the
compose plugin) from Docker's apt repo, add `ubuntu` to the `docker` group,
and clone this repository to **`/opt/blog`**. That checkout is the single
source of truth on the host — the compose file and nginx config are read from
it, and pipelines update it with plain `git pull`.

**The compose stack** (`docker-compose.prod.yml`) runs five containers:

- `nginx` — the only thing listening on 80/443. Terminates TLS and fans out
  to the three apps by hostname (`deploy/nginx/blog.conf`): apex → `front`,
  `api.` → `api`, `admin.` → `admin`. Security headers and per-vhost CSP are
  set here; the admin vhost additionally `include`s an **IP allowlist file
  that exists only on the host** (`deploy/nginx/admin-allowlist.conf`,
  gitignored — a committed `.example` shows the shape). Everyone outside the
  list gets a 403 before authentication is even attempted.
- `front`, `api`, `admin` — the three app images from GHCR, tracking
  `:latest`. Every pipeline push also tags the commit SHA, so any historical
  version can be pinned for rollback. `front` and `api` read their runtime
  environment from `/opt/blog/.env.prod` (gitignored; template in
  `.env.prod.example`); the admin image is fully static.
- `certbot` — wakes twice a day and renews the Let's Encrypt certificate via
  webroot when it's due. nginx mounts the same `blog_letsencrypt` volume
  read-only. One certificate covers all three hostnames.

**RDS PostgreSQL** (`db.t4g.micro`, encrypted, 7-day backups, deletion
protection on) is not reachable from the internet: `publicly_accessible =
false` and its security group accepts 5432 only from the EC2 security group.
The API verifies the TLS connection against the RDS CA bundle baked into its
image.

**S3** holds uploaded assets in a **pre-existing bucket shared with the dev
environment** (`dev/` and `prod/` key prefixes). Terraform deliberately does
not manage the bucket — it holds data and dev uses it too — only the IAM user
that writes to it. The bucket is expected to carry: public-read policy on
`prod/*` only, a deny-non-TLS statement, GET-only CORS, and blocked public
ACLs.

**DNS** is three Cloudflare A records — apex, `api.`, `admin.` — all pointing
at one **Elastic IP**. The EIP is the only piece of infrastructure that
deliberately survives rebuilds (see [Replacing the server](#replacing-the-server)),
so DNS never needs to change.

### The security model

- **Port 22 does not stay open.** The EC2 security group allows 80/443 from
  anywhere and nothing else. Every deploy (and every manual SSH session)
  opens 22 to a single `/32`, does its work, and revokes the rule. The IAM
  user the pipelines use for this (`blog-ci-sg`) can do exactly two things:
  authorize and revoke ingress rules **on that one security group** — a leak
  of its keys cannot touch anything else.
- Security-group rules live in **standalone Terraform rule resources**, not
  inline blocks, so Terraform is not authoritative over rules it didn't
  declare — the pipelines' transient port-22 rules never cause drift or get
  reverted by an `apply`.
- SSH host keys are **pinned**: every pipeline verifies the host against the
  `EC2_SSH_HOST_KEY` secret (an ephemeral runner has no trust-on-first-use
  history, so without this any machine answering on the IP would be trusted).
- The second IAM user (`blog-s3`) can only Put/Get/Delete objects in the
  assets bucket. Neither user has a console password.
- GHCR pulls on the host authenticate with each run's **short-lived
  `GITHUB_TOKEN`** piped over SSH stdin, followed by `docker logout` — the
  host stores no registry credentials.
- IMDSv2 is enforced on the instance. Secrets never enter git: Terraform
  state and `terraform.tfvars` are local and gitignored, runtime secrets live
  in `/opt/blog/.env.prod`, CI credentials live in GitHub Actions secrets.

### Continuous deployment

Four pipelines, one per concern, all sharing the open-22 → act → revoke
pattern:

| Repo | Trigger | What it does |
| --- | --- | --- |
| personal-blog-api | push to master | image → GHCR, roll `api`, run DB migrations |
| personal-blog-front | push to master | test → image → GHCR, roll `front` |
| personal-blog-admin | push to master | test → image → GHCR, roll `admin` |
| **this repo** | push touching compose/nginx | `git pull` at `/opt/blog`, re-apply the stack, reload nginx |

The app pipelines never touch the stack definition; this repo's pipeline
never touches app images. **Terraform is applied manually on purpose** —
infra changes are rare, destructive if wrong, and want a human reading the
plan.

---

## Replicating from zero

The complete path from an empty AWS account to the running blog. Steps 1–2
are one-time local preparation; 3–7 build and wire everything.

### 0. What you need

- Terraform ≥ 1.9, the AWS CLI with admin credentials, `gh` authenticated as
  the repo owner
- The domain in Cloudflare (or any DNS you control)
- The assets bucket (see above) — create it first on a truly fresh account
  and set the expected policy/CORS

### 1. Deploy key

```bash
ssh-keygen -t ed25519 -f deployer_key   # no passphrase; keep both halves safe
```

The public half goes into Terraform (step 3); the private half stays with you
and goes into the repos' `EC2_SSH_KEY` secret (step 6).

### 2. Terraform variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # gitignored
# fill in: ssh_public_key (contents of deployer_key.pub)
#          db_master_password (openssl rand -hex 24)
terraform init
```

### 3. Provision

```bash
# Rebuilding an existing deployment? Adopt the Elastic IP DNS already points
# at, so the records keep working. Skip this on a fresh account.
terraform import aws_eip.blog eipalloc-xxxxxxxxxxxxxxxxx

terraform apply
```

~6 minutes (RDS dominates). The outputs are everything downstream needs:

| Output | Used where |
| --- | --- |
| `public_ip` | Cloudflare A records, `EC2_HOST` secret |
| `ec2_security_group_id` | `EC2_SG_ID` secret, opening port 22 by hand |
| `database_url` (sensitive) | `DATABASE_URL` in `.env.prod` |
| `s3_access_key_id` / `s3_secret_access_key` (sensitive) | `.env.prod` |
| `ci_access_key_id` / `ci_secret_access_key` (sensitive) | `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` secrets |

`terraform output -raw <name>` prints the sensitive ones.

### 4. DNS

Point the three A records (apex, `api.`, `admin.`) at `public_ip`. DNS-only
(grey cloud) is preferred: the API rate-limits by client IP and the admin
allowlist matches real addresses, both of which the proxy would mask.

### 5. Bootstrap the host

Cloud-init needs a couple of minutes after `apply` (watch for
`cloud-init status` to report `done`). Then:

```bash
# Open SSH to yourself
MYIP=$(curl -s https://checkip.amazonaws.com)
aws ec2 authorize-security-group-ingress \
  --group-id $(terraform output -raw ec2_security_group_id) \
  --protocol tcp --port 22 --cidr "$MYIP/32"

# Prepare the two host-only files locally:
#   .env.prod              — from .env.prod.example + the Terraform outputs
#   admin-allowlist.conf   — from deploy/nginx/admin-allowlist.conf.example, your IP
IP=$(terraform output -raw public_ip)
scp -i deployer_key .env.prod ubuntu@$IP:/opt/blog/.env.prod
scp -i deployer_key admin-allowlist.conf ubuntu@$IP:/opt/blog/deploy/nginx/admin-allowlist.conf

ssh -i deployer_key ubuntu@$IP
```

On the host:

```bash
docker login ghcr.io -u <github-user>          # any token able to pull the images
CERT_EMAIL=you@example.com /opt/blog/scripts/bootstrap.sh
/opt/blog/scripts/create-admin.sh you@example.com 'a-long-unique-password'
docker logout ghcr.io
```

`bootstrap.sh` is idempotent: it issues the TLS certificate via standalone
HTTP-01 (or restores one — pass a tarball of `/etc/letsencrypt` as `$1`),
starts the stack, and applies migrations, retrying until RDS answers. The
first migration creates the whole schema, so there is no separate seeding
step. MFA for the admin user enrolls on first login.

Finally revoke your port-22 rule (same command as above with `revoke-…`).

### 6. Wire the pipelines

```bash
./scripts/sync-github-secrets.sh deployer_key
```

pushes `AWS_*`, `EC2_*` (including the freshly scanned pinned host key) into
all four repos' Actions secrets, plus the public build-time URLs the front
and admin images bake in.

### 7. Prove it

Trigger each repo's `deploy.yml` (push to master or `workflow_dispatch`) and
watch all four go green. Then: the apex serves the blog over TLS,
`https://api.<domain>/api/health` returns `{"status":"ok"}`, the admin
answers 200 from your IP and 403 from anywhere else, and
`terraform plan` reports no changes.

---

## Day-2 operations

**Deploying apps** — push to master in the app repo; nothing to do here.

**Changing the stack or nginx config** — edit, push to master here; the
sync-host workflow applies it. For the gitignored allowlist: edit
`/opt/blog/deploy/nginx/admin-allowlist.conf` on the host and
`docker compose -f docker-compose.prod.yml restart nginx`.

**Rolling back an app** — pin the SHA tag in `docker-compose.prod.yml`
(`ghcr.io/…/personal-blog-api:<sha>`) and push; revert to `:latest` when
done.

**SSH access** — see step 5's authorize/revoke pattern; there is no standing
SSH access by design.

**TLS** — renewals are automatic (certbot container). To re-issue from
scratch: stop the stack, remove the `blog_letsencrypt` volume, re-run
`bootstrap.sh`.

**Rotating credentials**
- deploy key: new key pair → `terraform apply` (replaces the EC2 key pair —
  requires instance replacement, see below) → `sync-github-secrets.sh`
- CI / S3 IAM keys: `terraform apply -replace=aws_iam_access_key.ci_sg`
  (or `…access_key.s3`) → re-run the secrets sync / update `.env.prod`
- DB password: change `db_master_password` in tfvars → `terraform apply` →
  update `DATABASE_URL` in `.env.prod` → `docker compose up -d api`

### Replacing the server

The instance is cattle. `terraform apply -replace=aws_instance.blog` builds
a fresh one; the Elastic IP follows it, so DNS is untouched. Then redo step 5
(the host is empty again: `.env.prod`, allowlist, certificate — restore the
certificate from a backup tarball to avoid Let's Encrypt rate limits) and
re-run `sync-github-secrets.sh` (the host key changed). RDS and S3 are
untouched throughout — data survives.

**Losing RDS** is the only real disaster: it holds the content. It has 7-day
automated backups (`aws rds restore-db-instance-to-point-in-time`), plus
whatever manual `pg_dump`s you keep. Restoring a dump:
`docker run --rm -i postgres:16-alpine psql "<database_url>?sslmode=require" < dump.sql`.

**Terraform state** (`terraform/terraform.tfstate`) is local and gitignored,
and contains every secret Terraform knows (IAM secret keys, the DB
password). Back it up like a credential. If it's ever lost, the stack can be
re-adopted with `terraform import` resource by resource — tedious but
possible; the resource addresses are all in this repo.

## Costs (eu-central-1, rough)

| Item | ~$/month |
| --- | --- |
| EC2 t3a.small | 15 |
| RDS db.t4g.micro + 20GB gp3 | 15 |
| EBS 20GB gp3 | 2 |
| S3 + traffic | ≈1 |
| EIP (attached), SGs, IAM | 0 |
| **Total** | **~33** |
