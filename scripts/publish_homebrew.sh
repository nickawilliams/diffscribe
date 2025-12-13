#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RENDER_SCRIPT="${ROOT_DIR}/packaging/homebrew/render.sh"

usage() {
  cat <<'USAGE'
Usage: scripts/publish_homebrew.sh <tag> <tap_repo> <tap_branch> <tap_formula_path> <rendered_formula_path>
Environment:
  GITHUB_TOKEN  Token with write access to the tap repository (required).
USAGE
}

if [[ $# -ne 5 ]]; then
  usage >&2
  exit 1
fi

TAG="$1"
TAP_REPO="$2"
TAP_BRANCH="$3"
TAP_FORMULA_PATH="$4"
RENDERED_FORMULA="$5"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

if [[ -z "${TAG}" ]]; then
  echo "missing release tag" >&2
  exit 1
fi

if [[ ! -x "${RENDER_SCRIPT}" ]]; then
  echo "missing render script at ${RENDER_SCRIPT}" >&2
  exit 1
fi

mkdir -p "$(dirname "${RENDERED_FORMULA}")"

echo "🧱 Rendering formula for ${TAG}..."
"${RENDER_SCRIPT}" "${TAG}" "${RENDERED_FORMULA}"

repo_url="https://github.com/${TAP_REPO}.git"
tap_dir="$(mktemp -d)"
cleanup_tap_dir="${tap_dir}"
trap 'rm -rf "${cleanup_tap_dir}"' EXIT

clone_args=(git)
push_args=(git)
if [[ -n "${GITHUB_TOKEN}" ]]; then
  header="Authorization: Basic $(printf "x-access-token:%s" "${GITHUB_TOKEN}" | base64 | tr -d '\n')"
  clone_args+=( -c http.extraHeader="${header}" )
  push_args+=( -c http.extraHeader="${header}" )
fi

echo "🔁 Cloning ${TAP_REPO}..."
"${clone_args[@]}" clone "${repo_url}" "${tap_dir}"

formula_dest="${tap_dir}/${TAP_FORMULA_PATH}"
mkdir -p "$(dirname "${formula_dest}")"
cp "${RENDERED_FORMULA}" "${formula_dest}"

formula_name="$(basename "${TAP_FORMULA_PATH}" .rb)"

pushd "${tap_dir}" >/dev/null
if [[ -z "$(git status --porcelain -- "${TAP_FORMULA_PATH}")" ]]; then
  echo "✅ Formula already up to date"
else
  git add "${TAP_FORMULA_PATH}"
  git commit -m "publish(formula): ${formula_name} ${TAG}"
  echo "📤 Pushing to ${TAP_REPO}..."
  "${push_args[@]}" push origin "HEAD:${TAP_BRANCH}"
  echo "🚀 Published diffscribe ${TAG} to ${TAP_REPO}"
fi
popd >/dev/null
