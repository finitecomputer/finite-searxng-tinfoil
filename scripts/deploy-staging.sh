#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: scripts/deploy-staging.sh [TAG]

Deploy or relaunch the SearXNG Tinfoil staging container.

Environment:
  TINFOIL_API_KEY          Optional. Used by tinfoil CLI if not already logged in.
  TINFOIL_BIN              Optional. Defaults to tinfoil or ~/.local/bin/tinfoil.
  TINFOIL_CONTAINER_NAME   Optional. Default: finite-searxng.
  TINFOIL_CONFIG_REPO      Optional. Default: finitecomputer/finite-searxng-tinfoil.
  TINFOIL_CONFIG_TAG       Optional. Default: first positional arg or v0.0.2.
  TINFOIL_STAGING          Optional. true/false. Default: true.
  SEARXNG_SECRET_NAME      Optional. Default: SEARXNG_SECRET.
  SEARXNG_SECRET_VALUE     Optional. If set, creates or updates the Tinfoil secret.
  TINFOIL_PROXY_PORT       Optional. Default: 3301, used only in printed next step.

If SEARXNG_SECRET_VALUE is unset, the script requires an existing Tinfoil secret.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

find_tinfoil() {
  if [[ -n "${TINFOIL_BIN:-}" ]]; then
    printf '%s\n' "$TINFOIL_BIN"
    return
  fi
  if command -v tinfoil >/dev/null 2>&1; then
    command -v tinfoil
    return
  fi
  if [[ -x "$HOME/.local/bin/tinfoil" ]]; then
    printf '%s\n' "$HOME/.local/bin/tinfoil"
    return
  fi
  echo "missing tinfoil CLI; install it or set TINFOIL_BIN" >&2
  exit 1
}

tinfoil_bin="$(find_tinfoil)"
repo="${TINFOIL_CONFIG_REPO:-finitecomputer/finite-searxng-tinfoil}"
tag="${TINFOIL_CONFIG_TAG:-${1:-v0.0.2}}"
container="${TINFOIL_CONTAINER_NAME:-finite-searxng}"
secret_name="${SEARXNG_SECRET_NAME:-SEARXNG_SECRET}"
staging="${TINFOIL_STAGING:-true}"
proxy_port="${TINFOIL_PROXY_PORT:-3301}"

case "$staging" in
  true | false) ;;
  *)
    echo "TINFOIL_STAGING must be true or false" >&2
    exit 1
    ;;
esac

if ! "$tinfoil_bin" whoami >/dev/null 2>&1; then
  cat >&2 <<EOF
Tinfoil CLI is not logged in.

Run one of:
  $tinfoil_bin login --api-key admin_...
  export TINFOIL_API_KEY=admin_...
EOF
  exit 1
fi

if "$tinfoil_bin" secret get "$secret_name" >/dev/null 2>&1; then
  if [[ -n "${SEARXNG_SECRET_VALUE:-}" ]]; then
    printf '%s' "$SEARXNG_SECRET_VALUE" |
      "$tinfoil_bin" secret set "$secret_name" --value-file -
  fi
else
  if [[ -z "${SEARXNG_SECRET_VALUE:-}" ]]; then
    cat >&2 <<EOF
Tinfoil secret '$secret_name' does not exist.

Create it by exporting SEARXNG_SECRET_VALUE, for example:
  export SEARXNG_SECRET_VALUE="\$(openssl rand -hex 32)"
  scripts/deploy-staging.sh "$tag"
  unset SEARXNG_SECRET_VALUE
EOF
    exit 1
  fi
  printf '%s' "$SEARXNG_SECRET_VALUE" |
    "$tinfoil_bin" secret create "$secret_name" --value-file -
fi

if "$tinfoil_bin" container get "$container" >/dev/null 2>&1; then
  "$tinfoil_bin" container relaunch "$container" \
    --tag "$tag" \
    --secret "$secret_name" \
    --staging "$staging"
else
  create_args=(
    container create "$container"
    --repo "$repo"
    --tag "$tag"
    --secret "$secret_name"
  )
  if [[ "$staging" == "true" ]]; then
    create_args+=(--staging)
  fi
  "$tinfoil_bin" "${create_args[@]}"
fi

cat <<EOF

Deploy submitted for $container ($repo@$tag).

After it is ready, verify through the attested local proxy:
  $tinfoil_bin container connect "$container" -p "$proxy_port"
  curl -fsS 'http://127.0.0.1:$proxy_port/search?q=open+source&format=json' | jq '.results | length'
EOF
