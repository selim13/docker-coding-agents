#!/bin/bash

INPUT=$(cat)
ROOT=$(unset CDPATH; cd -- "$(dirname -- "$0")/../.." && pwd) || exit 0
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')
[ -n "$CWD" ] || CWD=$ROOT
OUTPUT=""

while IFS= read -r file; do
  [ -n "$file" ] || continue
  [[ "$file" = /* ]] || file="$CWD/$file"
  file=$(realpath "$file" 2>/dev/null) || continue
  [[ "$file" = "$ROOT"/* ]] || continue

  case "$file" in
    *.sh)
      label="ShellCheck"
      command=(shellcheck "$file")
      ;;
    *.bats)
      label="ShellCheck"
      command=(shellcheck -s bats "$file")
      ;;
    */Dockerfile)
      label="Hadolint"
      command=(hadolint --failure-threshold error "$file")
      ;;
    *.yaml|*.yml)
      label="YAML"
      command=(yamllint -d relaxed "$file")
      ;;
    *.json)
      label="JSON"
      command=(jq empty "$file")
      ;;
    *)
      continue
      ;;
  esac

  if ! result=$("${command[@]}" 2>&1); then
    OUTPUT="${OUTPUT}${OUTPUT:+

}${label} (${file#"$ROOT"/}):
${result}"
  fi
done < <(
  {
    printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty'
    printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' |
      sed -nE 's/^\*\*\* (Add|Update) File: //p; s/^\*\*\* Move to: //p'
  } | sort -u
)

[ -z "$OUTPUT" ] || {
  if printf '%s' "$INPUT" | jq -e 'has("model")' >/dev/null; then
    jq -n --arg out "$OUTPUT" '{systemMessage:("Edit checks failed:\n" + $out)}'
  else
    jq -n --arg out "$OUTPUT" '{decision:"block",reason:("Edit checks failed:\n" + $out)}'
  fi
}
