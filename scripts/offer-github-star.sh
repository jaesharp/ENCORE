#!/bin/sh

# Offer an authenticated interactive user a one-time way to support ENCORE.
set -eu

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"

command -v gh >/dev/null 2>&1 || exit 0
GH_HOST=github.com GH_PROMPT_DISABLED=1 \
    gh auth status --hostname github.com >/dev/null 2>&1 || exit 0

valid_repository()
{
    case $1 in
        */*) ;;
        *) return 1 ;;
    esac
    owner=${1%/*}
    repository_name=${1#*/}
    [ -n "$owner" ] && [ -n "$repository_name" ] || return 1
    case "$owner$repository_name" in
        *[!A-Za-z0-9_.-]*) return 1 ;;
    esac
    [ "$owner/$repository_name" = "$1" ]
}

resolve_repository()
{
    candidate=${ENCORE_GITHUB_REPOSITORY:-wowitsjack/ENCORE}
    if valid_repository "$candidate"; then
        resolved=$(GH_HOST=github.com GH_PROMPT_DISABLED=1 gh repo view "$candidate" \
            --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)
        if valid_repository "$resolved"; then
            printf '%s\n' "$resolved"
            return
        fi
    fi

    origin=$(git -C "$PROJECT_ROOT" remote get-url origin 2>/dev/null || true)
    case $origin in
        https://github.com/*) candidate=${origin#https://github.com/} ;;
        git@github.com:*) candidate=${origin#git@github.com:} ;;
        *) return 1 ;;
    esac
    candidate=${candidate%.git}
    valid_repository "$candidate" || return 1
    resolved=$(GH_HOST=github.com GH_PROMPT_DISABLED=1 gh repo view "$candidate" \
        --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)
    valid_repository "$resolved" || return 1
    printf '%s\n' "$resolved"
}

repository=$(resolve_repository) || exit 0
if GH_HOST=github.com GH_PROMPT_DISABLED=1 \
        gh api --hostname github.com "user/starred/$repository" >/dev/null 2>&1; then
    printf 'Thanks for already starring %s on GitHub.\n' "$repository"
    exit 0
fi

printf '\nENCORE grows through community testing and contributions.\n'
printf 'Star %s on GitHub to help others find it and encourage future development? [Y/n] ' "$repository"
IFS= read -r answer || exit 0
case $answer in
    ''|y|Y|yes|YES|Yes)
        if GH_HOST=github.com GH_PROMPT_DISABLED=1 \
                gh api --hostname github.com --method PUT \
                    "user/starred/$repository" >/dev/null 2>&1; then
            printf 'Thank you! %s is now starred.\n' "$repository"
        else
            printf 'ENCORE: GitHub could not add the star; the installation is still complete.\n' >&2
        fi
        ;;
esac

exit 0
