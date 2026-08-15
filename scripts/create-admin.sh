#!/usr/bin/env bash
# Creates the first admin-panel user. Run ON the EC2 host from /opt/blog with
# the stack up. MFA enrolls on the user's first login.
#
# Usage: ./scripts/create-admin.sh you@example.com 'a-long-unique-password'
set -euo pipefail

[[ $# -eq 2 ]] || { echo "usage: $0 <email> <password>"; exit 1; }
cd /opt/blog

docker compose -f docker-compose.prod.yml exec -T api node -e "
  const { hashSync } = require('bcryptjs');
  const { Pool } = require('pg');
  const [email, password] = process.argv.slice(1);
  const pool = new Pool({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: true } });
  pool.query('INSERT INTO users (email, password_hash) VALUES (\$1, \$2)', [email, hashSync(password, 12)])
    .then(() => console.log('Created admin:', email)).then(() => pool.end());
" "$1" "$2"
