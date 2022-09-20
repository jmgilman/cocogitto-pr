set -euo pipefail

log() {
    echo "[cocogitto-pr] >>> ${1}"
}

BRANCH="${1}"
FILENAME="${2}"

# Trust this directory
git config --global --add safe.directory "$(pwd)"

log "Starting..."

VERSION=$(cog bump --auto --dry-run 2>/dev/null)
CHANGELOG=$(cog changelog)

log "Checking out changelog branch..."

# Create or checkout the changelog branch
if ! git branch --list | grep -q "${BRANCH}"; then
    log "Changelog branch does not exist. Creating it..."
    git checkout -b "${BRANCH}" &>/dev/null
else
    log "Using existing changelog branch..."
    git checkout "${BRANCH}" &>/dev/null
fi

log "Checking for changes..."

# Stop execution if there are no changes
if [[ -f "${FILENAME}" ]]; then
    if [[ "$(cat "${FILENAME}")" == "${CHANGELOG}" ]]; then
        log "${FILENAME} is up to date"
        exit
    fi
fi

# Update and commit changelog changes
log "Updating and committing changelog..."
echo "${CHANGELOG}" >CHANGELOG.md
git add CHANGELOG.md
git commit -m "chore: Update changelog for v${VERSION}"
git push origin "${BRANCH}"

log "Checking changelog PR status..."

# Create or update PR for changelog branch
if ! gh pr view "${BRANCH}"; then
    log "No PR exists for changelog. Creating it..."
    gh pr create --title "chore(changelog): Update changelog for v${VERSION}" --body "${CHANGELOG}" --head "${BRANCH}"
else
    log "Updating changelog PR..."
    gh pr edit "${BRANCH}" --title "chore(changelog): Update changelog for v${VERSION}" --body "${CHANGELOG}"
fi
