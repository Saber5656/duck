#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

declare -a candidates=()
for path in Package.swift Sources Tests Resources scripts .github/workflows; do
  [[ -e "$path" ]] || continue
  if [[ -d "$path" ]]; then
    while IFS= read -r file; do
      candidates+=("$file")
    done < <(find "$path" -type f | sort)
  else
    candidates+=("$path")
  fi
done

declare -a files=()
for file in "${candidates[@]}"; do
  case "$file" in
    docs/references/*|./docs/references/*)
      continue
      ;;
  esac

  case "$file" in
    Package.swift|Sources/*|Tests/*|Resources/*|scripts/*|.github/workflows/*)
      files+=("$file")
      ;;
  esac
done

if [[ "${#files[@]}" -eq 0 ]]; then
  echo "privacy-guard: no files selected" >&2
  exit 1
fi

declare -a patterns=(
  "SF""Speech""Recognizer"
  "AV""Audio""File"
  "AV""Audio""Recorder"
  "AV""Capture""Audio""File""Output"
  "URL""Session"
  "Network"'\.framework'
  "import[[:space:]]+""Network"
  "NW""Connection"
  "socket[[:space:]]*\\("
  "com.apple.security.network.""client"
  "com.apple.security.network.""server"
)

found=0
for pattern in "${patterns[@]}"; do
  if output="$(grep -nE "$pattern" "${files[@]}" 2>/dev/null)"; then
    if [[ -n "$output" ]]; then
      printf '%s\n' "$output"
      found=1
    fi
  fi
done

if [[ "$found" -ne 0 ]]; then
  echo "privacy-guard: blocked forbidden speech, recording, or networking surface" >&2
  exit 1
fi

echo "privacy-guard: checked ${#files[@]} source, build, entitlement, and workflow files"
