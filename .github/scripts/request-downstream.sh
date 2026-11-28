#!/usr/bin/env bash
# Push a one-line git ref to another repository so a workflow on its main
# branch runs. A deploy-key push starts workflows; a GITHUB_TOKEN push does not.
#
# Required environment:
#   DEPLOY_KEY      private key with write access to TARGET_REPO
#   TARGET_REPO     owner/name
#   TARGET_FILE     path under .github/ that the downstream workflow watches
#   REF             commit SHA or branch name to record in TARGET_FILE
# Optional:
#   COMMIT_MESSAGE  commit subject; the ref is appended
set -euo pipefail

: "${DEPLOY_KEY:?}"
: "${TARGET_REPO:?}"
: "${TARGET_FILE:?}"
: "${REF:?}"

if [[ ! "$TARGET_REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
  echo "invalid TARGET_REPO" >&2
  exit 1
fi
if [[ ! "$TARGET_FILE" =~ ^\.github/[A-Za-z0-9._-]+$ ]]; then
  echo "invalid TARGET_FILE" >&2
  exit 1
fi
if [[ ! "$REF" =~ ^[A-Za-z0-9._/-]{1,80}$ || "$REF" == *..* ]]; then
  echo "invalid REF" >&2
  exit 1
fi

message="${COMMIT_MESSAGE:-ci: request downstream sync} (${REF})"
key_file="$(mktemp)"
workdir="$(mktemp -d)"
cleanup() {
  rm -f "$key_file"
  rm -rf "$workdir"
}
trap cleanup EXIT

printf '%s\n' "$DEPLOY_KEY" > "$key_file"
chmod 600 "$key_file"
install -d -m 700 "${HOME}/.ssh"
if ! ssh-keyscan -t ed25519 github.com >> "${HOME}/.ssh/known_hosts"; then
  echo "ssh-keyscan failed" >&2
  exit 1
fi

export GIT_SSH_COMMAND="ssh -i ${key_file} -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes"
git clone --depth 1 "git@github.com:${TARGET_REPO}.git" "${workdir}/repo"
git -C "${workdir}/repo" config user.name "github-actions[bot]"
git -C "${workdir}/repo" config user.email "41898282+github-actions[bot]@users.noreply.github.com"
printf '%s\n' "$REF" > "${workdir}/repo/${TARGET_FILE}"
git -C "${workdir}/repo" add -- "$TARGET_FILE"
if git -C "${workdir}/repo" diff --cached --quiet; then
  echo "${TARGET_REPO} already has ${TARGET_FILE} at ${REF}"
  exit 0
fi
git -C "${workdir}/repo" commit -m "$message"
git -C "${workdir}/repo" push origin HEAD:main
echo "requested ${TARGET_REPO} at ${REF}"
