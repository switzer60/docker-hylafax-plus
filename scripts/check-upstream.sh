#!/bin/bash
# Compares the pins in docker/versions.env against what upstream currently
# has, and prints a Markdown report. Never changes anything - bumping stays
# a deliberate, smoke-tested commit (docs/BUILD.md#updating-the-pins).
# Run nightly by .github/workflows/check-upstream.yml, and safe to run
# locally: `./scripts/check-upstream.sh`.
#
# Checks, in order of how actionable they are:
#   1. Alpine APKINDEX for the pinned branch - a newer hylafaxplus/iaxmodem
#      there means the pinned version is gone from the mirror (Alpine only
#      indexes the latest build), so the current pins will stop building.
#   2. Alpine base image - a newer point release on the pinned branch, a
#      re-pushed digest, or a newer stable branch.
#   3. Alpine edge and SourceForge - newer upstream releases Alpine hasn't
#      shipped on our branch yet. Heads-up only.
#   4. Watched aports merge requests (WATCH_MRS) - reported once merged or
#      closed.
#
# Output: the report on stdout. When $GITHUB_OUTPUT is set, also writes
# `updates` (true if anything under Actionable/Heads-up), `fingerprint`
# (changes only when those findings change), and `partial` (true if a
# non-critical source couldn't be reached). Exits 2 if Alpine or Docker Hub
# can't be reached - those checks are the ones that matter.
set -Eeuo pipefail
cd "$(dirname "$0")/.."

VERSIONS_FILE="${VERSIONS_FILE:-docker/versions.env}"
# shellcheck source=docker/versions.env
. "${VERSIONS_FILE}"

# Space-separated aports MR numbers to watch. 108638 = main/iaxmodem 1.3.5.
WATCH_MRS="${WATCH_MRS-108638}"
# The architectures the image is published for (.github/workflows/build.yml).
ARCHES="x86_64 aarch64"
CDN="https://dl-cdn.alpinelinux.org/alpine"
AUTOTAG="alpine-${ALPINE_VERSION}_hylafaxplus-${HYLAFAX_PKG_VERSION}_iaxmodem-${IAXMODEM_PKG_VERSION}"

minor="$(echo "${ALPINE_VERSION}" | cut -d. -f1,2)"
branch="v${minor}"

actions=() headsups=() status=() warnings=()
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

fetch() { curl -fsSL --retry 3 --retry-delay 5 --max-time 60 "$@"; }

die() { echo "check-upstream: $*" >&2; exit 2; }

# True if $1 is a strictly newer version than $2.
newer() {
    [[ "$1" != "$2" ]] && [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" == "$1" ]]
}

# apk_version <branch> <repo> <arch> <pkg> - version in that APKINDEX, or
# empty if the package isn't there. Indexes are cached per run.
apk_version() {
    local idx="${tmp}/$1-$2-$3"
    if [[ ! -f "${idx}" ]]; then
        fetch "${CDN}/$1/$2/$3/APKINDEX.tar.gz" | tar -xzO APKINDEX > "${idx}" ||
            die "can't fetch ${CDN}/$1/$2/$3/APKINDEX.tar.gz"
    fi
    awk -v p="$4" '/^P:/{n=substr($0,3)} /^V:/{if(n==p)print substr($0,3)}' "${idx}"
}

# latest_release <branch> - newest point release on that branch, e.g. 3.24.2.
latest_release() {
    fetch "${CDN}/$1/releases/x86_64/latest-releases.yaml" |
        awk '/^ *version:/ && !done {print $2; done=1}' || die "can't fetch the $1 release list"
}

# hub_digest <tag> - alpine:<tag>'s digest on Docker Hub, or empty if that tag
# doesn't exist (yet - Alpine can publish a release before Hub has it).
hub_digest() {
    local code
    code="$(curl -sSL --retry 3 --retry-delay 5 --max-time 60 -o "${tmp}/hub.json" -w '%{http_code}' \
        "https://hub.docker.com/v2/repositories/library/alpine/tags/$1")" || code=000
    case "${code}" in
        200) jq -r '.digest // empty' "${tmp}/hub.json" ;;
        404) ;;
        *) die "can't fetch alpine:$1 from Docker Hub (HTTP ${code})" ;;
    esac
}

# --- 1. Packages on the pinned branch ----------------------------------------
check_pinned_pkg() {
    local pkg="$1" repo="$2" var="$3" pin="${!3}" arch v found=()
    for arch in ${ARCHES}; do
        v="$(apk_version "${branch}" "${repo}" "${arch}" "${pkg}")"
        [[ "${v}" == "${pin}" ]] || found+=("${arch}: ${v:-missing}")
    done
    if (( ${#found[@]} )); then
        actions+=("\`${pkg}\` \`${pin}\` is no longer what Alpine \`${branch}/${repo}\` serves (${found[*]}). The pinned build is gone from the mirror, so the current pins will stop building - bump \`${var}\`.")
    fi
}
check_pinned_pkg hylafaxplus community HYLAFAX_PKG_VERSION
check_pinned_pkg iaxmodem main IAXMODEM_PKG_VERSION

# --- 2. Alpine base image ----------------------------------------------------
branch_latest="$(latest_release "${branch}")"
[[ -n "${branch_latest}" ]] || die "no version in the ${branch} release list"
if newer "${branch_latest}" "${ALPINE_VERSION}"; then
    digest="$(hub_digest "${branch_latest}")"
    # A bare-minor pin (ALPINE_VERSION=3.24) whose digest already is the
    # latest point release isn't behind - it's just less specifically named.
    [[ "${digest}" == "${ALPINE_DIGEST}" ]] ||
    actions+=("Alpine \`${branch_latest}\` released on \`${branch}\` (pinned: \`${ALPINE_VERSION}\`). New digest: \`${digest:-not on Docker Hub yet}\`.")
else
    pinned_now="$(hub_digest "${ALPINE_VERSION}")"
    if [[ -n "${pinned_now}" && "${pinned_now}" != "${ALPINE_DIGEST}" ]]; then
        actions+=("\`alpine:${ALPINE_VERSION}\` was re-pushed: Docker Hub now has \`${pinned_now}\` (pinned: \`${ALPINE_DIGEST}\`).")
    fi
fi

stable="$(latest_release latest-stable)"
[[ -n "${stable}" ]] || die "no version in the latest-stable release list"
stable_branch="v$(echo "${stable}" | cut -d. -f1,2)"
if newer "${stable}" "${branch_latest}" && [[ "${stable_branch}" != "${branch}" ]]; then
    hv="$(apk_version "${stable_branch}" community x86_64 hylafaxplus)"
    iv="$(apk_version "${stable_branch}" main x86_64 iaxmodem)"
    digest="$(hub_digest "${stable}")"
    actions+=("New Alpine stable branch \`${stable_branch}\` (\`${stable}\`, digest \`${digest:-not on Docker Hub yet}\`). It ships \`hylafaxplus\` \`${hv:-missing}\` and \`iaxmodem\` \`${iv:-missing}\`.")
fi

# --- 3. Newer upstream releases not yet on our branch -----------------------
for pair in "hylafaxplus:community:${HYLAFAX_PKG_VERSION}" "iaxmodem:main:${IAXMODEM_PKG_VERSION}"; do
    IFS=: read -r pkg repo pin <<< "${pair}"
    v="$(apk_version edge "${repo}" x86_64 "${pkg}")"
    if [[ -n "${v}" ]] && newer "${v}" "${pin}"; then
        headsups+=("\`${pkg}\` \`${v}\` is in Alpine edge (pinned: \`${pin}\`) - it'll reach a stable branch at the next Alpine release, or sooner if backported.")
    fi
done

# SourceForge project names differ from the Alpine package names.
for pair in "hylafax:hylafaxplus:${HYLAFAX_PKG_VERSION}" "iaxmodem:iaxmodem:${IAXMODEM_PKG_VERSION}"; do
    IFS=: read -r project pkg pin <<< "${pair}"
    upstream_pin="${pin%-r*}"
    if file="$(fetch "https://sourceforge.net/projects/${project}/best_release.json" 2>/dev/null |
                jq -r '.release.filename // empty')" && [[ -n "${file}" ]]; then
        v="$(sed -nE 's#.*/[a-z]+-([0-9][0-9.]*)\.tar\.[a-z0-9]+$#\1#p' <<< "${file}")"
        if [[ -z "${v}" ]]; then
            warnings+=("Couldn't parse a version out of SourceForge's latest ${project} file (\`${file}\`).")
        elif newer "${v}" "${upstream_pin}"; then
            headsups+=("${project} \`${v}\` released upstream on SourceForge (pinned Alpine package is \`${upstream_pin}\`). Nothing to do until Alpine packages it.")
        fi
    else
        warnings+=("Couldn't reach SourceForge for ${project}.")
    fi
done

# --- 4. Watched aports merge requests ----------------------------------------
for mr in ${WATCH_MRS}; do
    url="https://gitlab.alpinelinux.org/alpine/aports/-/merge_requests/${mr}"
    if json="$(fetch "https://gitlab.alpinelinux.org/api/v4/projects/alpine%2Faports/merge_requests/${mr}" 2>/dev/null)"; then
        title="$(jq -r '.title' <<< "${json}")"
        state="$(jq -r '.state' <<< "${json}")"
        case "${state}" in
            merged) headsups+=("aports [!${mr}](${url}) (${title}) was merged $(jq -r '.merged_at[:10]' <<< "${json}"). Watch Alpine edge, then a stable branch, for the package - and drop ${mr} from WATCH_MRS once it lands.") ;;
            closed) headsups+=("aports [!${mr}](${url}) (${title}) was closed without merging.") ;;
            *) status+=("aports [!${mr}](${url}) (${title}): ${state}.") ;;
        esac
    else
        warnings+=("Couldn't reach GitLab for aports !${mr}.")
    fi
done

# --- Report ------------------------------------------------------------------
section() {
    local heading="$1"; shift
    (( $# )) || return 0
    printf '\n### %s\n\n' "${heading}"
    printf -- '- %s\n' "$@"
}

{
    echo "## Upstream check"
    echo
    echo "Current pins: \`${AUTOTAG}\`"
    if (( ${#actions[@]} + ${#headsups[@]} == 0 )); then
        echo
        echo "All pins current."
    fi
    section "Actionable - can bump now" "${actions[@]}"
    section "Heads-up - nothing to do yet" "${headsups[@]}"
    section "Watching" "${status[@]}"
    section "Check warnings" "${warnings[@]}"
}

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
        (( ${#actions[@]} + ${#headsups[@]} )) && echo "updates=true" || echo "updates=false"
        echo "fingerprint=$(printf '%s\n' "${actions[@]}" "${headsups[@]}" | sha256sum | cut -c1-16)"
        (( ${#warnings[@]} )) && echo "partial=true" || echo "partial=false"
    } >> "${GITHUB_OUTPUT}"
fi
