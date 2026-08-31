#!/usr/bin/env bash
set -euo pipefail

TAP_REPOSITORY="${HOMEBREW_TAP_REPOSITORY:-Saber5656/homebrew-tap}"
: "${RELEASE_VERSION:?RELEASE_VERSION is required}"
: "${RELEASE_SHA256:?RELEASE_SHA256 is required}"
: "${RELEASE_ASSET_URL:?RELEASE_ASSET_URL is required}"

if [[ ! "$RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "error: RELEASE_VERSION must be a Homebrew-compatible semantic version" >&2
  exit 1
fi
if [[ ! "$RELEASE_SHA256" =~ ^[[:xdigit:]]{64}$ ]]; then
  echo "error: RELEASE_SHA256 must be a 64-character hexadecimal digest" >&2
  exit 1
fi

expected_asset_url="https://github.com/Saber5656/duck/releases/download/v${RELEASE_VERSION}/duck-${RELEASE_VERSION}.zip"
if [[ "$RELEASE_ASSET_URL" != "$expected_asset_url" ]]; then
  echo "error: RELEASE_ASSET_URL does not match the expected duck release asset" >&2
  exit 1
fi

cask_content="$(cat <<EOF
cask "duck" do
  version "${RELEASE_VERSION}"
  sha256 "${RELEASE_SHA256}"

  url "https://github.com/Saber5656/duck/releases/download/v#{version}/duck-#{version}.zip"
  name "duck"
  desc "Privacy-first desktop companion that reacts to voice volume"
  homepage "https://github.com/Saber5656/duck"

  depends_on macos: ">= :ventura"

  app "duck.app"
end
EOF
)"

if [[ "${DUCK_CASK_DRY_RUN:-0}" == "1" ]]; then
  printf '%s\n' "$cask_content"
  exit 0
fi

: "${GH_TOKEN:?GH_TOKEN is required for the Homebrew tap update}"
command -v gh >/dev/null || { echo "error: gh CLI is required" >&2; exit 1; }
command -v jq >/dev/null || { echo "error: jq is required" >&2; exit 1; }

api_headers=(--header 'Accept: application/vnd.github+json' --header 'X-GitHub-Api-Version: 2022-11-28')
repo_json="$(gh api "repos/${TAP_REPOSITORY}" "${api_headers[@]}")"
default_branch="$(jq -er '.default_branch' <<< "$repo_json")"

file_sha=""
if file_json="$(gh api "repos/${TAP_REPOSITORY}/contents/Casks/duck.rb?ref=${default_branch}" "${api_headers[@]}" 2>/dev/null)"; then
  file_sha="$(jq -er '.sha' <<< "$file_json")"
fi

encoded_content="$(printf '%s' "$cask_content" | base64 | tr -d '\n')"
payload="$(jq -n \
  --arg message "chore: update duck cask to ${RELEASE_VERSION}" \
  --arg content "$encoded_content" \
  --arg branch "$default_branch" \
  --arg sha "$file_sha" \
  '{message: $message, content: $content, branch: $branch} + (if $sha == "" then {} else {sha: $sha} end)')"

printf '%s' "$payload" | gh api --method PUT \
  "repos/${TAP_REPOSITORY}/contents/Casks/duck.rb" \
  "${api_headers[@]}" \
  --input - \
  >/dev/null

printf 'Updated %s/Casks/duck.rb to %s\n' "$TAP_REPOSITORY" "$RELEASE_VERSION"
