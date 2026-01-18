#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_PATH="${SCRIPT_DIR}/Portfile.tmpl"
OUTPUT_PATH="${SCRIPT_DIR}/Portfile"
METADATA_PATH="${SCRIPT_DIR}/../metadata.yaml"

usage() {
  cat <<'USAGE'
Usage: packaging/macports/render.sh <tag> [output]

Arguments:
  <tag>    Release tag (e.g. v1.2.3) whose source tarball should back the Portfile.
  [output] Optional path for the rendered Portfile (defaults to packaging/macports/Portfile).

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

if [[ -z "${TAG}" ]]; then
  echo "missing release tag" >&2
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

if ! command -v yq >/dev/null 2>&1; then
  echo "yq is required to parse packaging/metadata.yaml" >&2
  exit 1
fi

if ! command -v envsubst >/dev/null 2>&1; then
  echo "envsubst is required to render the MacPorts Portfile" >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required to download the GitHub release asset" >&2
  exit 1
fi

meta_description=$(yq -r '.description // ""' "${METADATA_PATH}")
meta_homepage=$(yq -r '.homepage // ""' "${METADATA_PATH}")
meta_license=$(yq -r '.license // ""' "${METADATA_PATH}")

if [[ -z "${meta_description}" || -z "${meta_homepage}" || -z "${meta_license}" ]]; then
  echo "metadata.yaml is missing a required field" >&2
  exit 1
fi

license_for_macports() {
  local license="$1"
  case "${license}" in
    BSD-3-Clause|BSD-2-Clause|BSD-4-Clause|BSD-0-Clause) printf 'BSD' ;;
    *) printf '%s' "${license}" ;;
  esac
}

repo_name="${GH_REPO:-nickawilliams/diffscribe}"
version_no_v="${TAG#v}"
if [[ -z "${version_no_v}" ]]; then
  echo "unable to derive version from tag ${TAG}" >&2
  exit 1
fi

mkdir -p "$(dirname "${OUTPUT_PATH}")"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "'"${tmp_dir}"'"' EXIT

tarball_path="${tmp_dir}/source.tar.gz"

auth_header=()
token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
if [[ -n "${token}" ]]; then
  auth_header=(-H "Authorization: Bearer ${token}")
fi

asset_name="diffscribe_${version_no_v}_source.tar.gz"
url="https://github.com/${repo_name}/releases/download/${TAG}/${asset_name}"
echo "› downloading ${url}" >&2
curl -fsSL --retry 3 --retry-delay 2 "${auth_header[@]}" \
  -H "Accept: application/octet-stream" \
  -o "${tarball_path}" \
  "${url}"

rmd160_sum=$(openssl dgst -rmd160 "${tarball_path}" | awk '{print $NF}')
sha256_sum=$(shasum -a 256 "${tarball_path}" | awk '{print $1}')
if stat -f%z "${tarball_path}" >/dev/null 2>&1; then
  size_bytes=$(stat -f%z "${tarball_path}")
else
  size_bytes=$(wc -c < "${tarball_path}" | tr -d ' ')
fi

export PORT_VERSION="${version_no_v}"
PORT_LICENSE="$(license_for_macports "${meta_license}")"
export PORT_LICENSE
export PORT_DESCRIPTION="${meta_description}"
export PORT_HOMEPAGE="${meta_homepage}"
export PORT_RMD160="${rmd160_sum}"
export PORT_SHA256="${sha256_sum}"
export PORT_SIZE="${size_bytes}"

substitutions='${PORT_VERSION} ${PORT_LICENSE} ${PORT_DESCRIPTION} ${PORT_HOMEPAGE} ${PORT_RMD160} ${PORT_SHA256} ${PORT_SIZE}'

envsubst "${substitutions}" < "${TEMPLATE_PATH}" > "${OUTPUT_PATH}"

echo "Rendered Portfile -> ${OUTPUT_PATH}" >&2
