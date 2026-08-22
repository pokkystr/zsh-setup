#!/bin/bash

set -u

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FAILURES=0
TESTS=0

pass() {
    TESTS=$((TESTS + 1))
    printf 'PASS: %s\n' "$1"
}

fail() {
    TESTS=$((TESTS + 1))
    FAILURES=$((FAILURES + 1))
    printf 'FAIL: %s\n' "$1" >&2
}

detect_brew() {
    if [ -x /opt/homebrew/bin/brew ]; then
        BREW_BIN=/opt/homebrew/bin/brew
    elif [ -x /usr/local/bin/brew ]; then
        BREW_BIN=/usr/local/bin/brew
    else
        printf 'SKIP: Homebrew is not installed in a standard macOS prefix\n'
        exit 0
    fi

    BREW_PREFIX="$($BREW_BIN --prefix)"
}

path_index() {
    local needle="$1"
    local value="$2"
    local index=0
    local entry
    local old_ifs="$IFS"

    IFS=:
    for entry in $value; do
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

assert_path_precedes() {
    local first="$1"
    local second="$2"
    local value="$3"
    local description="$4"
    local first_index
    local second_index

    first_index="$(path_index "$first" "$value")" || {
        fail "$description (missing $first)"
        return
    }
    second_index="$(path_index "$second" "$value")" || {
        fail "$description (missing $second)"
        return
    }

    if [ "$first_index" -lt "$second_index" ]; then
        pass "$description"
    else
        fail "$description ($first_index is not before $second_index)"
    fi
}

test_zsh_template_prioritizes_homebrew() {
    local test_home
    local bad_path
    local output
    local resolved_zsh
    local resolved_git
    local final_path
    local duplicates

    test_home="$(mktemp -d)"
    mkdir -p "$test_home/.oh-my-zsh"
    printf '%s\n' 'export PATH="$TEST_GCLOUD_BIN:$PATH"' > "$test_home/.oh-my-zsh/oh-my-zsh.sh"

    bad_path="/usr/local/bin:/System/Cryptexes/App/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:$BREW_PREFIX/bin:$BREW_PREFIX/share/google-cloud-sdk/bin"

    output="$(
        HOME="$test_home" \
        TEST_GCLOUD_BIN="$BREW_PREFIX/share/google-cloud-sdk/bin" \
        PATH="$bad_path" \
        "$BREW_PREFIX/bin/zsh" -dfc '
            source "$1"
            print -r -- "$(command -v zsh)|$(command -v git)|$PATH"
        ' _ "$PROJECT_DIR/zsh.txt"
    )"

    resolved_zsh="${output%%|*}"
    output="${output#*|}"
    resolved_git="${output%%|*}"
    final_path="${output#*|}"

    if [ "$resolved_zsh" = "$BREW_PREFIX/bin/zsh" ]; then
        pass "zsh.txt resolves Homebrew ZSH"
    else
        fail "zsh.txt resolves Homebrew ZSH (got $resolved_zsh)"
    fi

    if [ "$resolved_git" = "$BREW_PREFIX/bin/git" ]; then
        pass "zsh.txt resolves Homebrew Git"
    else
        fail "zsh.txt resolves Homebrew Git (got $resolved_git)"
    fi

    assert_path_precedes "$BREW_PREFIX/bin" /usr/bin "$final_path" "Homebrew bin precedes /usr/bin"
    assert_path_precedes "$BREW_PREFIX/sbin" /bin "$final_path" "Homebrew sbin precedes /bin"

    duplicates="$(printf '%s\n' "$final_path" | tr ':' '\n' | sort | uniq -d)"
    if [ -z "$duplicates" ]; then
        pass "zsh.txt removes duplicate PATH entries"
    else
        fail "zsh.txt removes duplicate PATH entries (duplicates: $duplicates)"
    fi

    rm -rf "$test_home"
}

test_recheck_fails_for_system_first_path() {
    local bad_path
    local output
    local status

    bad_path="/usr/local/bin:/System/Cryptexes/App/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:$BREW_PREFIX/bin"

    output="$(PATH="$bad_path" /bin/bash "$PROJECT_DIR/recheck-setup.sh" 2>&1)"
    status=$?

    if [ "$status" -ne 0 ]; then
        pass "recheck exits non-zero for a system-first PATH"
    else
        fail "recheck exits non-zero for a system-first PATH"
    fi

    if printf '%s\n' "$output" | grep -Fq 'Result: FAIL'; then
        pass "recheck prints Result: FAIL"
    else
        fail "recheck prints Result: FAIL"
    fi
}

setup_fixture_project() {
    local fixture_project="$1"

    mkdir -p "$fixture_project"
    cp "$PROJECT_DIR/setup.sh" "$fixture_project/setup.sh"
    cp "$PROJECT_DIR/zsh.txt" "$fixture_project/zsh.txt"
    cp "$PROJECT_DIR/gitignore_global.txt" "$fixture_project/gitignore_global.txt"
    cp "$PROJECT_DIR/gittag.sh" "$fixture_project/gittag.sh"
    cp "$PROJECT_DIR/IntelliJOpen.sh" "$fixture_project/IntelliJOpen.sh"
}

prepare_installed_omz_fixture() {
    local fixture_home="$1"
    local plugin

    mkdir -p "$fixture_home/.oh-my-zsh/custom/plugins"
    for plugin in \
        zsh-completions \
        fzf-tab \
        zsh-autosuggestions \
        zsh-history-substring-search \
        zsh-syntax-highlighting
    do
        mkdir -p "$fixture_home/.oh-my-zsh/custom/plugins/$plugin"
    done
}

run_setup_fixture() {
    local fixture_home="$1"
    local fixture_setup="$2"

    HOME="$fixture_home" \
    EXPECTED_LOGIN_SHELL="$BREW_PREFIX/bin/zsh" \
    /bin/bash -c '
        dscl() {
            printf "UserShell: %s\n" "$EXPECTED_LOGIN_SHELL"
        }
        chsh() {
            printf "ERROR: fixture attempted to call chsh\n" >&2
            return 99
        }
        sudo() {
            while IFS= read -r ignored; do :; done
            return 0
        }
        source "$0"
    ' "$fixture_setup" >/dev/null
}

all_formulae_installed() {
    local formula

    for formula in zsh git git-extras fzf; do
        "$BREW_BIN" list --formula "$formula" >/dev/null 2>&1 || return 1
    done
}

test_setup_preserves_original_backups_on_rerun() {
    local fixture_root
    local fixture_home
    local fixture_project
    local status

    if ! all_formulae_installed; then
        printf 'SKIP: setup idempotency fixture requires all requested formulae\n'
        return
    fi

    fixture_root="$(mktemp -d)"
    fixture_home="$fixture_root/home"
    fixture_project="$fixture_root/project"
    mkdir -p "$fixture_home"
    setup_fixture_project "$fixture_project"
    prepare_installed_omz_fixture "$fixture_home"
    printf '%s\n' 'original zsh configuration' > "$fixture_home/.zshrc"
    printf '%s\n' 'original global ignore' > "$fixture_home/.gitignore_global"

    run_setup_fixture "$fixture_home" "$fixture_project/setup.sh"
    status=$?
    if [ "$status" -eq 0 ]; then
        pass "setup completes in an isolated existing-config fixture"
    else
        fail "setup completes in an isolated existing-config fixture"
        rm -rf "$fixture_root"
        return
    fi

    run_setup_fixture "$fixture_home" "$fixture_project/setup.sh"
    status=$?
    if [ "$status" -eq 0 ] \
       && [ "$(sed -n '1p' "$fixture_home/.zshrc.backup")" = 'original zsh configuration' ] \
       && [ "$(sed -n '1p' "$fixture_home/.gitignore_global.backup")" = 'original global ignore' ]; then
        pass "setup rerun does not overwrite original backups"
    else
        fail "setup rerun does not overwrite original backups"
    fi

    if [ "$(stat -f '%Lp' "$fixture_home/.gittag.sh")" = 755 ] \
       && [ "$(stat -f '%Lp' "$fixture_home/.IntelliJOpen.sh")" = 755 ]; then
        pass "setup installs helper scripts with mode 755"
    else
        fail "setup installs helper scripts with mode 755"
    fi

    rm -rf "$fixture_root"
}

test_setup_creates_empty_backup_sentinels() {
    local fixture_root
    local fixture_home
    local fixture_project
    local status

    if ! all_formulae_installed; then
        return
    fi

    fixture_root="$(mktemp -d)"
    fixture_home="$fixture_root/home"
    fixture_project="$fixture_root/project"
    mkdir -p "$fixture_home"
    setup_fixture_project "$fixture_project"
    prepare_installed_omz_fixture "$fixture_home"

    run_setup_fixture "$fixture_home" "$fixture_project/setup.sh"
    status=$?
    run_setup_fixture "$fixture_home" "$fixture_project/setup.sh" || status=$?

    if [ "$status" -eq 0 ] \
       && [ -f "$fixture_home/.zshrc.backup" ] \
       && [ ! -s "$fixture_home/.zshrc.backup" ] \
       && [ -f "$fixture_home/.gitignore_global.backup" ] \
       && [ ! -s "$fixture_home/.gitignore_global.backup" ]; then
        pass "setup keeps empty backup sentinels across reruns"
    else
        fail "setup keeps empty backup sentinels across reruns"
    fi

    rm -rf "$fixture_root"
}

detect_brew
test_zsh_template_prioritizes_homebrew
test_recheck_fails_for_system_first_path
test_setup_preserves_original_backups_on_rerun
test_setup_creates_empty_backup_sentinels

printf '\nTests: %s, Failures: %s\n' "$TESTS" "$FAILURES"

if [ "$FAILURES" -ne 0 ]; then
    exit 1
fi
