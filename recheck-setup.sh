#!/bin/bash

FAILURES=0
SUMMARY_LABELS=()
SUMMARY_RESULTS=()

record_result() {
    local label="$1"
    local result="$2"
    local index="${#SUMMARY_LABELS[@]}"

    SUMMARY_LABELS[$index]="$label"
    SUMMARY_RESULTS[$index]="$result"

    if [ "$result" != PASS ]; then
        FAILURES=$((FAILURES + 1))
    fi
}

print_status() {
    if [ "$1" -eq 1 ]; then
        printf 'OK: %s\n' "$2"
    else
        printf 'ERROR: %s\n' "$2"
    fi
}

path_index() {
    local needle="$1"
    local index=0
    local entry
    local old_ifs="$IFS"

    IFS=:
    for entry in $PATH; do
        if [ "$entry" = "$needle" ]; then
            printf '%s\n' "$index"
            IFS="$old_ifs"
            return 0
        fi
        index=$((index + 1))
    done
    IFS="$old_ifs"
    return 1
}

path_precedes() {
    local first_index
    local second_index

    first_index="$(path_index "$1")" || return 1
    second_index="$(path_index "$2")" || return 1
    [ "$first_index" -lt "$second_index" ]
}

if [ -x /opt/homebrew/bin/brew ]; then
    BREW_BIN=/opt/homebrew/bin/brew
elif [ -x /usr/local/bin/brew ]; then
    BREW_BIN=/usr/local/bin/brew
else
    BREW_BIN=
fi

if [ -n "$BREW_BIN" ]; then
    BREW_PREFIX="$("$BREW_BIN" --prefix 2>/dev/null)"
    EXPECTED_ZSH="$BREW_PREFIX/bin/zsh"
    EXPECTED_GIT="$BREW_PREFIX/bin/git"
    EXPECTED_FZF="$BREW_PREFIX/bin/fzf"
else
    BREW_PREFIX=
    EXPECTED_ZSH=
    EXPECTED_GIT=
    EXPECTED_FZF=
fi


printf '%s\n' '=== Environment ==='
printf 'SHELL:\n%s\n\n' "${SHELL:-}"
printf 'PATH:\n%s\n' "$PATH"

PATH_PRIORITY_OK=0
PATH_UNIQUE_OK=0
PATH_DUPLICATES="$(
    printf '%s\n' "$PATH" | tr ':' '\n' | awk 'NF && seen[$0]++' | sort -u
)"

if [ -n "$BREW_PREFIX" ] \
   && path_precedes "$BREW_PREFIX/bin" /usr/bin \
   && path_precedes "$BREW_PREFIX/bin" /bin \
   && path_precedes "$BREW_PREFIX/sbin" /usr/bin \
   && path_precedes "$BREW_PREFIX/sbin" /bin; then
    PATH_PRIORITY_OK=1
fi

if [ -z "$PATH_DUPLICATES" ]; then
    PATH_UNIQUE_OK=1
fi

print_status "$PATH_PRIORITY_OK" 'Homebrew bin/sbin precede /usr/bin and /bin'
if [ "$PATH_UNIQUE_OK" -eq 1 ]; then
    printf '%s\n' 'OK: PATH has no duplicate entries'
else
    printf 'ERROR: Duplicate PATH entries:\n%s\n' "$PATH_DUPLICATES"
fi


printf '\n%s\n' '=== ZSH ==='

LOGIN_SHELL="$(
    dscl . -read "$HOME" UserShell 2>/dev/null | awk '{print $2}' || true
)"
RESOLVED_ZSH="$(command -v zsh 2>/dev/null || true)"

printf 'Configured login shell:\n%s\n\n' "${LOGIN_SHELL:-not found}"
printf 'ZSH from PATH:\n%s\n\n' "${RESOLVED_ZSH:-not found}"
printf '%s\n' 'All ZSH:'
type -a zsh 2>/dev/null || printf '%s\n' 'not found'
printf '\n%s\n' 'ZSH version from PATH:'
if [ -n "$RESOLVED_ZSH" ]; then
    zsh --version 2>/dev/null || true
else
    printf '%s\n' 'not found'
fi
printf '\nHomebrew ZSH: %s\n' "${EXPECTED_ZSH:-not found}"
if [ -x "$EXPECTED_ZSH" ]; then
    "$EXPECTED_ZSH" --version
else
    printf '%s\n' 'not found'
fi

LOGIN_SHELL_OK=0
ZSH_RESOLUTION_OK=0
[ -n "$EXPECTED_ZSH" ] && [ "$LOGIN_SHELL" = "$EXPECTED_ZSH" ] \
  && LOGIN_SHELL_OK=1
[ -n "$EXPECTED_ZSH" ] && [ "$RESOLVED_ZSH" = "$EXPECTED_ZSH" ] \
  && ZSH_RESOLUTION_OK=1


printf '\n%s\n' '=== Git ==='

RESOLVED_GIT="$(command -v git 2>/dev/null || true)"
printf 'Git from PATH:\n%s\n\n' "${RESOLVED_GIT:-not found}"
printf '%s\n' 'All Git:'
type -a git 2>/dev/null || printf '%s\n' 'not found'
printf '\n%s\n' 'Git version from PATH:'
if [ -n "$RESOLVED_GIT" ]; then
    git --version 2>/dev/null || true
else
    printf '%s\n' 'not found'
fi
printf '\nHomebrew Git: %s\n' "${EXPECTED_GIT:-not found}"
if [ -x "$EXPECTED_GIT" ]; then
    "$EXPECTED_GIT" --version
else
    printf '%s\n' 'not found'
fi

GIT_RESOLUTION_OK=0
[ -n "$EXPECTED_GIT" ] && [ "$RESOLVED_GIT" = "$EXPECTED_GIT" ] \
  && GIT_RESOLUTION_OK=1


printf '\n%s\n' '=== Homebrew ==='

RESOLVED_BREW="$(command -v brew 2>/dev/null || true)"
printf 'Homebrew from PATH:\n%s\n' "${RESOLVED_BREW:-not found}"
if [ -n "$BREW_BIN" ]; then
    "$BREW_BIN" --version | head -1
    printf 'Prefix: %s\n' "$BREW_PREFIX"
else
    printf '%s\n' 'Homebrew not found in /opt/homebrew or /usr/local'
fi

HOMEBREW_OK=0
[ -n "$BREW_BIN" ] && [ "$RESOLVED_BREW" = "$BREW_BIN" ] \
  && HOMEBREW_OK=1


printf '\n%s\n' '=== Oh My Zsh ==='

OMZ_OK=0
if [ -d "$HOME/.oh-my-zsh" ]; then
    OMZ_OK=1
    printf 'OK: %s\n' "$HOME/.oh-my-zsh"
else
    printf 'ERROR: Not found: %s\n' "$HOME/.oh-my-zsh"
fi


printf '\n%s\n' '=== Plugins ==='

PLUGINS_OK=1
for plugin in \
    zsh-completions \
    fzf-tab \
    zsh-autosuggestions \
    zsh-history-substring-search \
    zsh-syntax-highlighting
do
    plugin_path="$HOME/.oh-my-zsh/custom/plugins/$plugin"
    if [ -d "$plugin_path" ]; then
        printf 'OK: %s\n' "$plugin"
    else
        PLUGINS_OK=0
        printf 'MISSING: %s\n' "$plugin"
    fi
done


printf '\n%s\n' '=== fzf ==='

RESOLVED_FZF="$(command -v fzf 2>/dev/null || true)"
printf 'fzf from PATH:\n%s\n' "${RESOLVED_FZF:-not found}"
if [ -n "$RESOLVED_FZF" ]; then
    fzf --version 2>/dev/null || true
fi

FZF_OK=0
[ -n "$EXPECTED_FZF" ] && [ "$RESOLVED_FZF" = "$EXPECTED_FZF" ] \
  && FZF_OK=1


printf '\n%s\n' '=== Helper Scripts ==='

HELPERS_INSTALLED_OK=1
HELPER_PERMISSIONS_OK=1
for helper in "$HOME/.gittag.sh" "$HOME/.IntelliJOpen.sh"; do
    if [ -f "$helper" ]; then
        mode="$(stat -f '%Lp' "$helper" 2>/dev/null || true)"
        printf '%s %s\n' "$mode" "$helper"
        if [ "$mode" != 755 ]; then
            HELPER_PERMISSIONS_OK=0
        fi
    else
        HELPERS_INSTALLED_OK=0
        HELPER_PERMISSIONS_OK=0
        printf 'MISSING: %s\n' "$helper"
    fi
done


printf '\n%s\n' '=== Git Configuration ==='

PUSH_VALUE=
EXCLUDES_VALUE=
if [ -x "$EXPECTED_GIT" ]; then
    PUSH_VALUE="$(
        "$EXPECTED_GIT" config --global --get push.autoSetupRemote 2>/dev/null \
          || true
    )"
    EXCLUDES_VALUE="$(
        "$EXPECTED_GIT" config --global --get core.excludesfile 2>/dev/null \
          || true
    )"
fi

printf 'push.autoSetupRemote: %s\n' "${PUSH_VALUE:-not set}"
printf 'core.excludesfile: %s\n' "${EXCLUDES_VALUE:-not set}"

PUSH_CONFIG_OK=0
GITIGNORE_CONFIG_OK=0
[ "$PUSH_VALUE" = true ] && PUSH_CONFIG_OK=1
[ "$EXCLUDES_VALUE" = "$HOME/.gitignore_global" ] \
  && [ -f "$HOME/.gitignore_global" ] \
  && GITIGNORE_CONFIG_OK=1


printf '\n%s\n' '=== Backup ==='

BACKUPS_OK=1
for backup in "$HOME/.zshrc.backup" "$HOME/.gitignore_global.backup"; do
    if [ -e "$backup" ]; then
        ls -ld "$backup"
    else
        BACKUPS_OK=0
        printf 'MISSING: %s\n' "$backup"
    fi
done


record_result 'Login shell uses Homebrew ZSH' \
  "$([ "$LOGIN_SHELL_OK" -eq 1 ] && printf PASS || printf FAIL)"
record_result 'ZSH resolves to Homebrew' \
  "$([ "$ZSH_RESOLUTION_OK" -eq 1 ] && printf PASS || printf FAIL)"
record_result 'Git resolves to Homebrew' \
  "$([ "$GIT_RESOLUTION_OK" -eq 1 ] && printf PASS || printf FAIL)"
record_result 'Homebrew command resolves correctly' \
  "$([ "$HOMEBREW_OK" -eq 1 ] && printf PASS || printf FAIL)"
record_result 'Homebrew paths precede system paths' \
  "$([ "$PATH_PRIORITY_OK" -eq 1 ] && printf PASS || printf FAIL)"
record_result 'PATH contains no duplicates' \
  "$([ "$PATH_UNIQUE_OK" -eq 1 ] && printf PASS || printf FAIL)"
record_result 'Oh My Zsh installed' \
  "$([ "$OMZ_OK" -eq 1 ] && printf PASS || printf FAIL)"
record_result 'All ZSH plugins installed' \
  "$([ "$PLUGINS_OK" -eq 1 ] && printf PASS || printf FAIL)"
record_result 'fzf installed from Homebrew' \
  "$([ "$FZF_OK" -eq 1 ] && printf PASS || printf FAIL)"
record_result 'Helper scripts installed' \
  "$([ "$HELPERS_INSTALLED_OK" -eq 1 ] && printf PASS || printf FAIL)"
record_result 'Helper permissions correct' \
  "$([ "$HELPER_PERMISSIONS_OK" -eq 1 ] && printf PASS || printf FAIL)"
record_result 'Global gitignore configured' \
  "$([ "$GITIGNORE_CONFIG_OK" -eq 1 ] && printf PASS || printf FAIL)"
record_result 'push.autoSetupRemote enabled' \
  "$([ "$PUSH_CONFIG_OK" -eq 1 ] && printf PASS || printf FAIL)"
record_result 'Backup files exist' \
  "$([ "$BACKUPS_OK" -eq 1 ] && printf PASS || printf FAIL)"

printf '\n%s\n%s\n%s\n' \
  '======================================' \
  ' Verification Summary' \
  '======================================'

for ((index = 0; index < ${#SUMMARY_LABELS[@]}; index++)); do
    printf '%s: %s\n' "${SUMMARY_RESULTS[$index]}" "${SUMMARY_LABELS[$index]}"
done

printf '\n'
if [ "$FAILURES" -eq 0 ]; then
    printf '%s\n' 'Result: PASS'
    exit 0
fi

printf '%s\n' 'Result: FAIL'
printf 'Failed checks: %s\n' "$FAILURES"
exit 1
