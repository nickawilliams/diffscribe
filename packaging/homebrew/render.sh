#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_PATH="${SCRIPT_DIR}/diffscribe.rb.tmpl"
OUTPUT_PATH="${SCRIPT_DIR}/diffscribe.rb"
METADATA_PATH="${SCRIPT_DIR}/metadata.json"

usage() {
  cat <<'USAGE'
Usage: packaging/homebrew/render.sh <tag> [output]

Arguments:
  <tag>    Release tag (e.g. v1.2.3) whose assets should back the formula.
  [output] Optional path for the rendered formula (defaults to packaging/homebrew/diffscribe.rb).

Environment:
  GH_REPO          Override the repository owner/name (default: nickawilliams/diffscribe).
  GITHUB_TOKEN     Token for authenticated downloads (preferred).
  GH_TOKEN         Fallback token variable if GITHUB_TOKEN isn't set.
USAGE
}

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 1
fi

TAG="$1"
shift
if [[ $# -gt 0 ]]; then
  OUTPUT_PATH="$1"
  shift
fi

if [[ $# -gt 0 ]]; then
  usage >&2
  exit 1
fi

if [[ ! -f "${TEMPLATE_PATH}" ]]; then
  echo "missing template at ${TEMPLATE_PATH}" >&2
  exit 1
fi

if [[ ! -f "${METADATA_PATH}" ]]; then
  echo "missing metadata at ${METADATA_PATH}" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to parse packaging/homebrew/metadata.json" >&2
  exit 1
fi

if ! command -v envsubst >/dev/null 2>&1; then
  echo "envsubst is required to render the Homebrew formula" >&2
  exit 1
fi

meta_desc=$(jq -r '.desc' "${METADATA_PATH}")
meta_homepage=$(jq -r '.homepage' "${METADATA_PATH}")
meta_license=$(jq -r '.license' "${METADATA_PATH}")
meta_binary=$(jq -r '.binary' "${METADATA_PATH}")

if [[ -z "${meta_desc}" || -z "${meta_homepage}" || -z "${meta_license}" || -z "${meta_binary}" ]]; then
  echo "metadata.json is missing a required field" >&2
  exit 1
fi

repo_name="${GH_REPO:-nickawilliams/diffscribe}"
version_no_v="${TAG#v}"
if [[ -z "${version_no_v}" ]]; then
  echo "unable to derive version from tag ${TAG}" >&2
  exit 1
fi
asset_version="${version_no_v}"

asset_path_for() {
  local os="$1"
  local arch="$2"
  local transformed_arch
  case "${arch}" in
    amd64) transformed_arch="x86_64" ;;
    386) transformed_arch="x86" ;;
    *) transformed_arch="${arch}" ;;
  esac
  printf '%s_%s_%s_%s.tar.gz' "${meta_binary}" "${asset_version}" "${os}" "${transformed_arch}"
}

arm_asset="$(asset_path_for darwin arm64)"
amd_asset="$(asset_path_for darwin amd64)"
source_asset="${meta_binary}_${asset_version}_source.tar.gz"
base_download_url="https://github.com/${repo_name}/releases/download/${TAG}"

mkdir -p "$(dirname "${OUTPUT_PATH}")"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "'"${tmp_dir}"'"' EXIT

sha_of() {
  local asset="$1"
  local dest="${tmp_dir}/${asset}"
  local auth_header=()
  local token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
  if [[ -n "${token}" ]]; then
    auth_header=(-H "Authorization: Bearer ${token}")
  fi

  local url="${base_download_url}/${asset}"
  echo "› downloading ${asset}" >&2
  curl -fsSL --retry 3 --retry-delay 2 "${auth_header[@]}" \
    -H "Accept: application/octet-stream" \
    -o "${dest}" \
    "${url}"
  shasum -a 256 "${dest}" | awk '{print $1}'
}

arm_sha="$(sha_of "${arm_asset}")"
amd_sha="$(sha_of "${amd_asset}")"
source_sha="$(sha_of "${source_asset}")"

escape_for_ruby() {
  local value="$1"
  value=${value//\"/\\\"}
  printf '%s' "${value}"
}

export FORMULA_DESC="$(escape_for_ruby "${meta_desc}")"
export HOMEPAGE="${meta_homepage}"
export LICENSE="${meta_license}"
export VERSION="${version_no_v}"
export ARM64_URL="${base_download_url}/${arm_asset}"
export ARM64_SHA="${arm_sha}"
export AMD64_URL="${base_download_url}/${amd_asset}"
export AMD64_SHA="${amd_sha}"
export SOURCE_URL="${base_download_url}/${source_asset}"
export SOURCE_SHA="${source_sha}"
export BINARY_NAME="${meta_binary}"

substitutions='${FORMULA_DESC} ${HOMEPAGE} ${LICENSE} ${VERSION} ${ARM64_URL} ${ARM64_SHA} ${AMD64_URL} ${AMD64_SHA} ${SOURCE_URL} ${SOURCE_SHA} ${BINARY_NAME}'

envsubst "${substitutions}" < "${TEMPLATE_PATH}" > "${OUTPUT_PATH}"

echo "Rendered formula -> ${OUTPUT_PATH}" >&2
