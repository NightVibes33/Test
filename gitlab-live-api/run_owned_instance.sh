#!/usr/bin/env bash
# Run only against your own licensed/self-managed GitLab test instance.
set -euo pipefail
cd "$(dirname "$0")"
umask 077
mkdir -p .tokens evidence
chmod 700 .tokens

if ! curl -fsS --max-time 15 http://127.0.0.1:8929/help >/dev/null; then
  echo "GitLab is not yet serving HTTP on 127.0.0.1:8929."
  echo "Run: docker compose -f compose.yml up -d, then activate an Ultimate trial in Admin > Subscription."
  exit 2
fi

# A disposable local root PAT is used to run true HTTP requests with the
# GitLab 'Sudo' header for separately created Owner / Author identities.
# No privileged access to gitlab.com or to other people's instances.
docker compose -f compose.yml exec -T gitlab gitlab-rails runner \
  "u=User.find_by_username('root'); abort 'missing root' unless u; p=u.personal_access_tokens.create(name: 'Bounty local repro', scopes: [:api, :sudo], expires_at: Date.today + 1); secret='glpat-' + SecureRandom.hex(20); p.set_token(secret); p.save!; puts secret" \
  > .tokens/root.pat

if ! grep -q '^glpat-' .tokens/root.pat; then
  echo "Could not provision an API token; inspect the local GitLab instance." >&2
  exit 2
fi

echo "Starting real REST-only test. Secrets stay in gitignored .tokens/."
GITLAB_URL=http://127.0.0.1:8929 \
  EVIDENCE_DIR="$(pwd)/evidence" \
  TOKEN_DIR="$(pwd)/.tokens" \
  python3 live_api_repro.py

echo "Completed. Review evidence/summary.json and evidence/http-transcript.json."
