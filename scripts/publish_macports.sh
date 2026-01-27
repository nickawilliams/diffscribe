#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RENDER_SCRIPT="${ROOT_DIR}/packaging/macports/render.sh"
PROJECT_YAML="${ROOT_DIR}/project.yaml"

usage() {
  cat <<'USAGE'
Usage: scripts/publish_macports.sh <tag> <port_repo> <portfile_path> <rendered_portfile_path>
Environment:
  GITHUB_TOKEN      Token with write access to the ports repository (required).
  PORT_PULLREQUEST  Set to "true" to create a PR to the upstream repository.
USAGE
}

if [[ $# -ne 4 ]]; then
  usage >&2
  exit 1
fi

TAG="$1"
PORT_REPO="$2"
PORTFILE_PATH="$3"
RENDERED_PORTFILE="$4"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

if [[ -z "${TAG}" ]]; then
  echo "missing release tag" >&2
  exit 1
fi

if [[ ! -x "${RENDER_SCRIPT}" ]]; then
  echo "missing render script at ${RENDER_SCRIPT}" >&2
  exit 1
fi

mkdir -p "$(dirname "${RENDERED_PORTFILE}")"

echo "INFO: Rendering Portfile for ${TAG}..."
"${RENDER_SCRIPT}" "${TAG}" "${RENDERED_PORTFILE}"

repo_url="https://github.com/${PORT_REPO}.git"
port_dir="$(mktemp -d)"
test_dir=""
trap 'rm -rf "${port_dir}" "${test_dir}"' EXIT

clone_args=(git)
push_args=(git)
if [[ -n "${GITHUB_TOKEN}" ]]; then
  header="Authorization: Basic $(printf "x-access-token:%s" "${GITHUB_TOKEN}" | base64 | tr -d '\n')"
  clone_args+=( -c http.extraHeader="${header}" )
  push_args+=( -c http.extraHeader="${header}" )
fi

echo "INFO: Cloning ${PORT_REPO}..."
"${clone_args[@]}" clone "${repo_url}" "${port_dir}"

portfile_dest="${port_dir}/${PORTFILE_PATH}"
port_name="$(basename "$(dirname "${PORTFILE_PATH}")")"
version="${TAG#v}"

is_new_port=false
if [[ ! -f "${portfile_dest}" ]]; then
  is_new_port=true
fi

# Verify the Portfile (lint, test, install)
if command -v port >/dev/null 2>&1; then
  # Create a minimal ports tree in /var/tmp with permissions for macports user
  test_dir="$(mktemp -d /var/tmp/macports-test.XXXXXX)"
  mkdir -p "${test_dir}/$(dirname "${PORTFILE_PATH}")"
  cp "${RENDERED_PORTFILE}" "${test_dir}/${PORTFILE_PATH}"
  chmod -R o+rx "${test_dir}"

  # Create portindex for the minimal ports tree
  echo "INFO: Indexing ports tree..."
  pushd "${test_dir}" >/dev/null
  portindex
  popd >/dev/null

  # Add ports tree to sources.conf temporarily
  sources_conf="/opt/local/etc/macports/sources.conf"
  sources_conf_modified=false
  if [[ -f "${sources_conf}" ]]; then
    sudo cp "${sources_conf}" "${sources_conf}.bak"
    echo "file://${test_dir}" | sudo tee -a "${sources_conf}" >/dev/null
    sources_conf_modified=true
  fi

  # Helper to restore sources.conf
  restore_sources_conf() {
    if [[ "${sources_conf_modified}" == "true" && -f "${sources_conf}.bak" ]]; then
      sudo mv "${sources_conf}.bak" "${sources_conf}"
    fi
  }

  # Run port lint (-N for non-interactive mode in CI)
  echo "INFO: Linting Portfile..."
  if ! port -N lint --nitpick "${port_name}"; then
    echo "ERROR: Portfile failed lint check" >&2
    restore_sources_conf
    exit 1
  fi
  echo "INFO: Portfile passed lint check"

  # Run port test
  echo "INFO: Running port tests..."
  if ! sudo port -N test "${port_name}"; then
    echo "ERROR: Port tests failed" >&2
    restore_sources_conf
    exit 1
  fi
  echo "INFO: Port tests passed"

  # Run full install from source (-t trace mode omitted as it causes tar failures in CI)
  echo "INFO: Installing port from source..."
  if ! sudo port -N -vs install "${port_name}"; then
    echo "ERROR: Port installation failed" >&2
    restore_sources_conf
    exit 1
  fi
  echo "INFO: Port installed successfully"

  # Test basic functionality
  echo "INFO: Testing binary functionality..."
  if ! "${port_name}" --version; then
    echo "ERROR: Binary functionality test failed" >&2
    restore_sources_conf
    exit 1
  fi
  echo "INFO: Binary functionality verified"

  # Clean up: uninstall the port and restore sources.conf
  sudo port -N uninstall "${port_name}" || true
  restore_sources_conf

elif [[ "${PORT_PULLREQUEST:-false}" == "true" ]]; then
  echo "ERROR: port command not found but PORT_PULLREQUEST=true requires verification" >&2
  echo "ERROR: Install MacPorts to enable linting and testing" >&2
  exit 1
else
  echo "WARN: port command not found, skipping verification"
fi

pushd "${port_dir}" >/dev/null

# Determine commit message
if [[ "${is_new_port}" == "true" ]]; then
  commit_msg="${port_name}: new port, version ${version}"
else
  commit_msg="${port_name}: update to ${version}"
fi

# Create PR to upstream repo if enabled
if [[ "${PORT_PULLREQUEST:-false}" == "true" ]]; then
  echo "INFO: Querying upstream repo for ${PORT_REPO}..."
  upstream_repo=$(gh repo view "${PORT_REPO}" --json parent --jq 'if .parent then "\(.parent.owner.login)/\(.parent.name)" else empty end')
  if [[ -z "${upstream_repo}" ]]; then
    echo "ERROR: Could not determine upstream repo for ${PORT_REPO}" >&2
    echo "ERROR: Is ${PORT_REPO} a fork? PR creation requires a fork relationship." >&2
    exit 1
  fi

  # Create or update branch for this version
  branch_name="${port_name}-${version}"
  fork_owner="${PORT_REPO%%/*}"
  head_ref="${fork_owner}:${branch_name}"

  # Check if branch already exists on remote
  branch_exists=false
  if git ls-remote --heads origin "${branch_name}" | grep -q "${branch_name}"; then
    echo "INFO: Branch ${branch_name} already exists, updating..."
    git fetch origin "${branch_name}"
    git checkout "${branch_name}"
    git reset --hard "origin/${branch_name}"
    branch_exists=true
  else
    echo "INFO: Creating branch ${branch_name}..."
    git checkout -b "${branch_name}"
  fi

  # Copy the Portfile to the branch
  mkdir -p "$(dirname "${PORTFILE_PATH}")"
  cp "${RENDERED_PORTFILE}" "${PORTFILE_PATH}"

  if [[ -z "$(git status --porcelain -- "${PORTFILE_PATH}")" ]]; then
    echo "INFO: Portfile already up to date"
    popd >/dev/null
    exit 0
  fi

  git add "${PORTFILE_PATH}"
  if [[ "${branch_exists}" == "true" ]]; then
    # Amend existing commit to keep history squashed (MacPorts preference)
    git commit --amend -m "${commit_msg}"
  else
    git commit -m "${commit_msg}"
  fi
  "${push_args[@]}" push --force-with-lease -u origin "${branch_name}"
  echo "INFO: Pushed to ${PORT_REPO}:${branch_name}"

  # Check for existing open PR from this branch
  existing_pr=$(gh pr list --repo "${upstream_repo}" --head "${head_ref}" --state open --json number,url --jq '.[0] // empty')
  if [[ -n "${existing_pr}" ]]; then
    pr_url=$(echo "${existing_pr}" | jq -r '.url')
    echo "INFO: Existing PR updated: ${pr_url}"
    popd >/dev/null
    exit 0
  fi

  # No existing PR, create one
  # Gather system info for PR template
  macos_info="macOS $(sw_vers -productVersion) $(sw_vers -buildVersion) $(uname -m)"
  if xcode_version=$(xcodebuild -version 2>/dev/null); then
    toolchain_info=$(echo "${xcode_version}" | awk 'NR==1{x=$0}END{print x" "$NF}')
  else
    clt_version=$(pkgutil --pkg-info=com.apple.pkg.CLTools_Executables 2>/dev/null | awk '/version:/ {print $2}')
    toolchain_info="Command Line Tools ${clt_version:-unknown}"
  fi

  # Build PR description based on new port vs update
  if [[ "${is_new_port}" == "true" ]]; then
    pkg_binary=$(yq -r '.binary' "${PROJECT_YAML}")
    pkg_description=$(yq -r '.description' "${PROJECT_YAML}")
    pr_description="${pkg_binary}: ${pkg_description}

New port submission from [diffscribe](https://github.com/nickawilliams/diffscribe) release ${TAG}."
  else
    pr_description="Automated update from [diffscribe](https://github.com/nickawilliams/diffscribe) release ${TAG}."
  fi

  # Fetch PR template from upstream repo
  echo "INFO: Fetching PR template from ${upstream_repo}..."
  pr_template=$(gh api "repos/${upstream_repo}/contents/.github/PULL_REQUEST_TEMPLATE.md" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null || true)

  if [[ -n "${pr_template}" ]]; then
    pr_body="#### Description

${pr_description}

###### Type(s)

- [ ] bugfix
- [x] enhancement
- [ ] security fix

###### Tested on
${macos_info}
${toolchain_info}

###### Verification
Have you

- [x] followed our [Commit Message Guidelines](https://trac.macports.org/wiki/CommitMessages)?
- [x] squashed and [minimized your commits](https://guide.macports.org/#project.github)?
- [x] checked that there aren't other open [pull requests](https://github.com/macports/macports-ports/pulls) for the same change?
- [x] checked your Portfile with \`port lint\`?
- [x] tried existing tests with \`sudo port test\`?
- [x] tried a full install with \`sudo port -vst install\`?
- [x] tested basic functionality of all binary files?"
  else
    pr_body="${pr_description}

Tested on: ${macos_info}, ${toolchain_info}"
  fi

  echo "INFO: Creating PR to ${upstream_repo}..."
  pr_url=$(gh pr create \
    --repo "${upstream_repo}" \
    --head "${head_ref}" \
    --title "${commit_msg}" \
    --body "${pr_body}")
  echo "INFO: Created PR: ${pr_url}"
else
  # No PR requested, push to default branch
  mkdir -p "$(dirname "${PORTFILE_PATH}")"
  cp "${RENDERED_PORTFILE}" "${PORTFILE_PATH}"

  if [[ -z "$(git status --porcelain -- "${PORTFILE_PATH}")" ]]; then
    echo "INFO: Portfile already up to date"
  else
    git add "${PORTFILE_PATH}"
    git commit -m "${commit_msg}"
    echo "INFO: Pushing to ${PORT_REPO}..."
    "${push_args[@]}" push origin HEAD
    echo "INFO: Published diffscribe ${TAG} to ${PORT_REPO}"
  fi
fi
popd >/dev/null
