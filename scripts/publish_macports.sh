#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RENDER_SCRIPT="${ROOT_DIR}/packaging/macports/render.sh"

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
lint_dir=""
trap 'rm -rf "${port_dir}" "${lint_dir}"' EXIT

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

mkdir -p "$(dirname "${portfile_dest}")"
cp "${RENDERED_PORTFILE}" "${portfile_dest}"

# Lint the Portfile
if command -v port >/dev/null 2>&1; then
  echo "INFO: Linting Portfile..."

  # Create a minimal local repository with just our port for fast linting
  # (avoids indexing thousands of ports in the full macports-ports fork)
  lint_dir="$(mktemp -d)"
  mkdir -p "${lint_dir}/$(dirname "${PORTFILE_PATH}")"
  cp "${RENDERED_PORTFILE}" "${lint_dir}/${PORTFILE_PATH}"

  # Create portindex for the minimal lint tree
  pushd "${lint_dir}" >/dev/null
  portindex >/dev/null 2>&1
  popd >/dev/null

  # Add minimal lint tree to sources.conf temporarily
  sources_conf="/opt/local/etc/macports/sources.conf"
  if [[ -f "${sources_conf}" ]]; then
    sudo cp "${sources_conf}" "${sources_conf}.bak"
    echo "file://${lint_dir}" | sudo tee -a "${sources_conf}" >/dev/null
  fi

  # Run port lint (-N for non-interactive mode in CI)
  if ! port -N lint --nitpick "${port_name}"; then
    echo "ERROR: Portfile failed lint check" >&2
    # Restore sources.conf
    if [[ -f "${sources_conf}.bak" ]]; then
      sudo mv "${sources_conf}.bak" "${sources_conf}"
    fi
    exit 1
  fi

  # Restore sources.conf
  if [[ -f "${sources_conf}.bak" ]]; then
    sudo mv "${sources_conf}.bak" "${sources_conf}"
  fi

  echo "INFO: Portfile passed lint check"
elif [[ "${PORT_PULLREQUEST:-false}" == "true" ]]; then
  echo "ERROR: port command not found but PORT_PULLREQUEST=true requires lint" >&2
  echo "ERROR: Install MacPorts to enable linting" >&2
  exit 1
else
  echo "WARN: port command not found, skipping lint"
fi

pushd "${port_dir}" >/dev/null
if [[ -z "$(git status --porcelain -- "${PORTFILE_PATH}")" ]]; then
  echo "INFO: Portfile already up to date"
else
  git add "${PORTFILE_PATH}"
  if [[ "${is_new_port}" == "true" ]]; then
    commit_msg="${port_name}: new port, version ${version}"
  else
    commit_msg="${port_name}: update to ${version}"
  fi
  git commit -m "${commit_msg}"
  echo "INFO: Pushing to ${PORT_REPO}..."
  "${push_args[@]}" push origin HEAD
  echo "INFO: Published diffscribe ${TAG} to ${PORT_REPO}"

  # Create PR to upstream repo if enabled
  if [[ "${PORT_PULLREQUEST:-false}" == "true" ]]; then
    echo "INFO: Querying upstream repo for ${PORT_REPO}..."
    upstream_repo=$(gh repo view "${PORT_REPO}" --json parent --jq 'if .parent then "\(.parent.owner.login)/\(.parent.name)" else empty end')
    if [[ -z "${upstream_repo}" ]]; then
      echo "ERROR: Could not determine upstream repo for ${PORT_REPO}" >&2
      echo "ERROR: Is ${PORT_REPO} a fork? PR creation requires a fork relationship." >&2
      exit 1
    fi

    fork_owner="${PORT_REPO%%/*}"
    current_branch="$(git rev-parse --abbrev-ref HEAD)"
    head_ref="${fork_owner}:${current_branch}"

    # Gather system info for PR template
    macos_info="macOS $(sw_vers -productVersion) $(sw_vers -buildVersion) $(uname -m)"
    if xcode_version=$(xcodebuild -version 2>/dev/null); then
      toolchain_info=$(echo "${xcode_version}" | awk 'NR==1{x=$0}END{print x" "$NF}')
    else
      clt_version=$(pkgutil --pkg-info=com.apple.pkg.CLTools_Executables 2>/dev/null | awk '/version:/ {print $2}')
      toolchain_info="Command Line Tools ${clt_version:-unknown}"
    fi

    # Fetch PR template from upstream repo
    echo "INFO: Fetching PR template from ${upstream_repo}..."
    pr_template=$(gh api "repos/${upstream_repo}/contents/.github/PULL_REQUEST_TEMPLATE.md" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null || true)

    if [[ -n "${pr_template}" ]]; then
      # Determine PR type checkboxes
      if [[ "${is_new_port}" == "true" ]]; then
        type_checkboxes="- [ ] bugfix\n- [x] enhancement\n- [ ] security fix"
      else
        type_checkboxes="- [ ] bugfix\n- [x] enhancement\n- [ ] security fix"
      fi

      # Build the PR body with filled-in template
      pr_body="#### Description

Automated update from [diffscribe](https://github.com/nickawilliams/diffscribe) release ${TAG}.

###### Type(s)

${type_checkboxes}

###### Tested on
${macos_info}
${toolchain_info}

###### Verification
Have you

- [x] followed our [Commit Message Guidelines](https://trac.macports.org/wiki/CommitMessages)?
- [x] squashed and [minimized your commits](https://guide.macports.org/#project.github)?
- [x] checked that there aren't other open [pull requests](https://github.com/macports/macports-ports/pulls) for the same change?
- [x] checked your Portfile with \`port lint\`?"
    else
      pr_body="Automated update from [diffscribe](https://github.com/nickawilliams/diffscribe) release ${TAG}.

Tested on: ${macos_info}, ${toolchain_info}"
    fi

    echo "INFO: Creating PR to ${upstream_repo}..."
    pr_url=$(gh pr create \
      --repo "${upstream_repo}" \
      --head "${head_ref}" \
      --title "${commit_msg}" \
      --body "${pr_body}")
    echo "INFO: Created PR: ${pr_url}"
  fi
fi
popd >/dev/null
