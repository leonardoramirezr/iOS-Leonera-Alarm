#!/bin/bash
# Publishes one build to GitHub Pages (branch gh-pages) so it can be installed
# from Safari on the iPhone (itms-services). Run from the repository checkout.
#
#   scripts/publish-pages.sh <path/to/App.ipa>
#
# Environment:
#   TAG, VERSION, BUILD_NUMBER, STABLE (true|false), BUNDLE_ID   about the build
#   APP_TITLE           name shown on the pages and by iOS while installing
#   ICON                1024x1024 PNG used for the 57 and 512 px icons
#   RELEASE_URL         link to the GitHub release
#   KEEP_BRANCH_BUILDS  builds of other branches to keep (default 50; every main version is kept)
#   PAGES_URL           optional; otherwise from `gh api repos/{repo}/pages`,
#                       falling back to https://<owner>.github.io/<repo>/
#   GITHUB_REPOSITORY, GITHUB_REF_NAME, GITHUB_SHA, GITHUB_RUN_NUMBER, GITHUB_RUN_ID,
#   GITHUB_SERVER_URL   (set by GitHub Actions)
#
# gh-pages is rewritten every time as a single orphan commit, so old IPAs do not
# pile up in its history. Folders without build.json are dropped (the branch may
# have been created from the source code). If another build publishes at the
# same time, the push (--force-with-lease) is rejected and everything is retried
# on top of the new gh-pages.
set -euo pipefail

IPA="${1:?usage: publish-pages.sh <ipa>}"
: "${TAG:?}" "${VERSION:?}" "${BUILD_NUMBER:?}" "${STABLE:?}" "${BUNDLE_ID:?}" "${ICON:?}"
: "${GITHUB_REPOSITORY:?}" "${GITHUB_SHA:?}" "${GITHUB_RUN_NUMBER:?}"
APP_TITLE="${APP_TITLE:-$(basename "${IPA}" .ipa)}"
KEEP_BRANCH_BUILDS="${KEEP_BRANCH_BUILDS:-50}"
SERVER="${GITHUB_SERVER_URL:-https://github.com}"
RUN_URL="${SERVER}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID:-}"
RELEASE_URL="${RELEASE_URL:-${SERVER}/${GITHUB_REPOSITORY}/releases/tag/${TAG}}"
BRANCH="${GITHUB_REF_NAME:-$(git rev-parse --abbrev-ref HEAD)}"
SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
GIT_DIR_ABS="$(git rev-parse --absolute-git-dir)"

if [ -z "${PAGES_URL:-}" ]; then
    PAGES_URL="$(gh api "repos/${GITHUB_REPOSITORY}/pages" --jq .html_url 2>/dev/null || true)"
    if [ -z "${PAGES_URL}" ]; then
        owner="${GITHUB_REPOSITORY%%/*}"
        PAGES_URL="https://$(echo "${owner}" | tr '[:upper:]' '[:lower:]').github.io/${GITHUB_REPOSITORY#*/}/"
        echo "GitHub Pages API unavailable (Pages not enabled yet?); using ${PAGES_URL}"
    fi
fi
PAGES_URL="${PAGES_URL%/}/"
echo "Pages URL: ${PAGES_URL}"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

# The new build folder, prepared once.
build_dir="${work}/build"
mkdir -p "${build_dir}"
cp "${IPA}" "${build_dir}/"
sips -z 57 57 "${ICON}" --out "${build_dir}/icon-57.png" >/dev/null
sips -z 512 512 "${ICON}" --out "${build_dir}/icon-512.png" >/dev/null
python3 "${SCRIPTS}/pages_site.py" build \
    --dir "${build_dir}" --base-url "${PAGES_URL}" --tag "${TAG}" --ipa "${IPA}" \
    --bundle-id "${BUNDLE_ID}" --version "${VERSION}" --build-number "${BUILD_NUMBER}" \
    --run-number "${GITHUB_RUN_NUMBER}" --stable "${STABLE}" --branch "${BRANCH}" \
    --commit "${GITHUB_SHA}" --title "${APP_TITLE}" --run-url "${RUN_URL}" --release-url "${RELEASE_URL}"

export GIT_AUTHOR_NAME="github-actions[bot]" GIT_COMMITTER_NAME="github-actions[bot]"
export GIT_AUTHOR_EMAIL="41898282+github-actions[bot]@users.noreply.github.com"
export GIT_COMMITTER_EMAIL="${GIT_AUTHOR_EMAIL}"

for attempt in 1 2 3 4 5 6; do
    site="${work}/site"
    rm -rf "${site}" "${work}/index"
    mkdir -p "${site}"

    # Current gh-pages (if it exists): keep only the build folders.
    lease=""
    if git fetch --quiet origin "+refs/heads/gh-pages:refs/remotes/origin/gh-pages" 2>/dev/null; then
        lease="$(git rev-parse refs/remotes/origin/gh-pages)"
        git archive "${lease}" | tar -x -C "${site}"
        for entry in "${site}"/* "${site}"/.[!.]*; do
            [ -e "${entry}" ] || continue
            if [ ! -f "${entry}/build.json" ]; then
                rm -rf "${entry}"
            fi
        done
    fi

    rm -rf "${site:?}/${TAG}"
    cp -R "${build_dir}" "${site}/${TAG}"
    python3 "${SCRIPTS}/pages_site.py" index --dir "${site}" --keep-branch-builds "${KEEP_BRANCH_BUILDS}"

    # Single orphan commit. --force: a .gitignore with *.ipa must not drop the IPA.
    export GIT_INDEX_FILE="${work}/index"
    (cd "${site}" && git --git-dir="${GIT_DIR_ABS}" --work-tree=. add -A --force .)
    tree="$(git write-tree)"
    unset GIT_INDEX_FILE
    commit="$(git commit-tree "${tree}" -m "Publish ${TAG} (${GITHUB_SHA::7})")"
    if [ -z "$(git ls-tree -r --name-only "${tree}" -- "${TAG}/$(basename "${IPA}")")" ]; then
        echo "error: the IPA is missing from the gh-pages commit" >&2
        exit 1
    fi

    # Empty lease value = gh-pages must not exist yet.
    if git push --force-with-lease="refs/heads/gh-pages:${lease}" origin "${commit}:refs/heads/gh-pages"; then
        echo "Published ${PAGES_URL}${TAG}/"
        if [ -n "${GITHUB_OUTPUT:-}" ]; then
            echo "pages_url=${PAGES_URL}" >> "${GITHUB_OUTPUT}"
            echo "build_url=${PAGES_URL}${TAG}/" >> "${GITHUB_OUTPUT}"
        fi
        exit 0
    fi
    delay=$(( attempt * 5 + RANDOM % 10 ))
    echo "gh-pages changed while publishing (attempt ${attempt}); retrying in ${delay}s..."
    sleep "${delay}"
done
echo "error: could not publish to gh-pages" >&2
exit 1
