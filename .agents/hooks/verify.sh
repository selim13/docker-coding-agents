#!/bin/bash

ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/../.." && pwd) || exit 0
OUTPUT=""

check() {
  local label=$1 result
  shift
  if ! result=$("$@" 2>&1); then
    OUTPUT="${OUTPUT}${OUTPUT:+

}${label}:
${result}"
  fi
}

check "ShellCheck" shellcheck \
  "$ROOT/coding-agents-container.sh" \
  "$ROOT/.agents/hooks/lint-edit.sh" \
  "$ROOT/.agents/hooks/verify.sh" \
  "$ROOT/test/fixtures/docker" \
  "$ROOT/test/fixtures/fd"
check "Bats ShellCheck" shellcheck -s bats "$ROOT/test/launcher.bats"
check "Hadolint" hadolint --failure-threshold error "$ROOT/Dockerfile"
check "YAML" yamllint -d relaxed "$ROOT/.github/workflows/publish.yml"
check "JSON" jq empty \
  "$ROOT/renovate.json" \
  "$ROOT/.claude/settings.json" \
  "$ROOT/.codex/hooks.json"
check "Bats" "$ROOT/test/bats/bin/bats" "$ROOT/test/launcher.bats"

if [ -n "$OUTPUT" ]; then
  OUTPUT=$(printf '%s\n' "$OUTPUT" | tail -50)
  printf 'Verification failed:\n%s\n' "$OUTPUT" >&2
  exit 2
fi
