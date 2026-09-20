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
    assert_path_precedes "$test_home/.local/bin" "$BREW_PREFIX/bin" "$final_path" \
      "User-local bin precedes Homebrew bin"

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
    cp "$PROJECT_DIR/gitsync.sh" "$fixture_project/gitsync.sh"
    cp "$PROJECT_DIR/IntelliJOpen.sh" "$fixture_project/IntelliJOpen.sh"
    cp "$PROJECT_DIR/orca.sh" "$fixture_project/orca.sh"
    cp "$PROJECT_DIR/ssh-key.zip" "$fixture_project/ssh-key.zip"
}

prepare_installed_omz_fixture() {
    local fixture_home="$1"
    local plugin

    mkdir -p "$fixture_home/.oh-my-zsh/custom/plugins"
    touch "$fixture_home/.oh-my-zsh/oh-my-zsh.sh"
    for plugin in \
        zsh-completions \
        fzf-tab \
        zsh-autosuggestions \
        zsh-history-substring-search \
        zsh-syntax-highlighting
    do
        mkdir -p "$fixture_home/.oh-my-zsh/custom/plugins/$plugin"
        touch "$fixture_home/.oh-my-zsh/custom/plugins/$plugin/$plugin.plugin.zsh"
    done
}

test_zsh_template_loads_local_configuration() {
    local fixture_home
    local output

    fixture_home="$(mktemp -d)"
    prepare_installed_omz_fixture "$fixture_home"
    printf '%s\n' 'export ZSH_SETUP_LOCAL_CONFIG=loaded' \
      > "$fixture_home/.zshrc.local"

    output="$(
        HOME="$fixture_home" "$BREW_PREFIX/bin/zsh" -dfc '
            source "$1"
            print -r -- "${ZSH_SETUP_LOCAL_CONFIG:-missing}"
        ' _ "$PROJECT_DIR/zsh.txt"
    )"

    if [ "$output" = loaded ]; then
        pass "zsh.txt loads machine-local configuration"
    else
        fail "zsh.txt loads machine-local configuration (got $output)"
    fi

    rm -rf "$fixture_home"
}

test_zsh_template_binds_history_substring_search() {
    local fixture_home
    local output

    fixture_home="$(mktemp -d)"
    prepare_installed_omz_fixture "$fixture_home"
    cat > "$fixture_home/.oh-my-zsh/oh-my-zsh.sh" <<'EOF'
history-substring-search-up() { :; }
history-substring-search-down() { :; }
zle -N history-substring-search-up
zle -N history-substring-search-down
EOF

    output="$(
        HOME="$fixture_home" "$BREW_PREFIX/bin/zsh" -dfc '
            source "$1"
            bindkey "^[[A"
            bindkey "^[[B"
        ' _ "$PROJECT_DIR/zsh.txt"
    )"

    if printf '%s\n' "$output" \
         | grep -Fq '"^[[A" history-substring-search-up' \
       && printf '%s\n' "$output" \
         | grep -Fq '"^[[B" history-substring-search-down'; then
        pass "zsh.txt binds arrow keys to history substring search"
    else
        fail "zsh.txt binds arrow keys to history substring search (got $output)"
    fi

    rm -rf "$fixture_home"
}

test_git_prune_local_removes_only_gone_noncurrent_branches() {
    local fixture_root
    local fixture_home
    local remote_repo
    local work_repo
    local output
    local status

    fixture_root="$(mktemp -d)"
    fixture_home="$fixture_root/home"
    remote_repo="$fixture_root/remote.git"
    work_repo="$fixture_root/work"
    prepare_installed_omz_fixture "$fixture_home"

    "$BREW_PREFIX/bin/git" init --bare "$remote_repo" >/dev/null
    "$BREW_PREFIX/bin/git" clone "$remote_repo" "$work_repo" >/dev/null 2>&1
    "$BREW_PREFIX/bin/git" -C "$work_repo" config user.name fixture
    "$BREW_PREFIX/bin/git" -C "$work_repo" config user.email fixture@example.com
    printf '%s\n' fixture > "$work_repo/README.md"
    "$BREW_PREFIX/bin/git" -C "$work_repo" add README.md
    "$BREW_PREFIX/bin/git" -C "$work_repo" commit -m initial >/dev/null
    "$BREW_PREFIX/bin/git" -C "$work_repo" branch -M main
    "$BREW_PREFIX/bin/git" -C "$work_repo" push -u origin main >/dev/null 2>&1
    "$BREW_PREFIX/bin/git" -C "$work_repo" branch stale
    "$BREW_PREFIX/bin/git" -C "$work_repo" push -u origin stale >/dev/null 2>&1
    "$BREW_PREFIX/bin/git" -C "$work_repo" switch -c current-gone >/dev/null
    "$BREW_PREFIX/bin/git" -C "$work_repo" push -u origin current-gone >/dev/null 2>&1
    "$BREW_PREFIX/bin/git" --git-dir="$remote_repo" update-ref -d refs/heads/stale
    "$BREW_PREFIX/bin/git" --git-dir="$remote_repo" update-ref -d refs/heads/current-gone

    output="$(
        HOME="$fixture_home" "$BREW_PREFIX/bin/zsh" -dfc '
            source "$1"
            cd "$2"
            git-prune-local
            print -r -- "current=$(git branch --show-current)"
            if git show-ref --verify --quiet refs/heads/stale; then
                print -r -- stale=present
            else
                print -r -- stale=absent
            fi
        ' _ "$PROJECT_DIR/zsh.txt" "$work_repo" 2>&1
    )"
    status=$?

    if [ "$status" -eq 0 ] \
       && printf '%s\n' "$output" | grep -Fq 'current=current-gone' \
       && printf '%s\n' "$output" | grep -Fq 'stale=absent'; then
        pass "git-prune-local removes gone branches and keeps the current branch"
    else
        fail "git-prune-local removes gone branches and keeps the current branch (got $output)"
    fi

    rm -rf "$fixture_root"
}

test_zsh_template_omits_unused_plugins() {
    local fixture_home
    local output

    fixture_home="$(mktemp -d)"
    prepare_installed_omz_fixture "$fixture_home"

    output="$(
        HOME="$fixture_home" "$BREW_PREFIX/bin/zsh" -dfc '
            source "$1"
            for plugin in pod gradle nvm yarn pyenv postgres heroku supervisor; do
                if (( ${plugins[(Ie)$plugin]} )); then
                    print -r -- "$plugin"
                fi
            done
        ' _ "$PROJECT_DIR/zsh.txt"
    )"

    if [ -z "$output" ]; then
        pass "zsh.txt omits plugins for unused tools"
    else
        fail "zsh.txt omits plugins for unused tools (still enabled: $output)"
    fi

    rm -rf "$fixture_home"
}

prepare_orca_wrapper_fixture() {
    local fixture_root="$1"

    mkdir -p \
      "$fixture_root/wrapper-bin" \
      "$fixture_root/real-bin" \
      "$fixture_root/project"
    cp "$PROJECT_DIR/orca.sh" "$fixture_root/wrapper-bin/orca"
    chmod 755 "$fixture_root/wrapper-bin/orca"

    cat > "$fixture_root/real-bin/orca" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" > "$ORCA_TEST_LOG"
exit "${ORCA_TEST_EXIT:-0}"
EOF
    chmod 755 "$fixture_root/real-bin/orca"
}

test_orca_wrapper_adds_explicit_directory() {
    local fixture_root
    local expected_project_path
    local expected_log
    local status

    fixture_root="$(mktemp -d)"
    expected_log="$fixture_root/expected.log"

    if [ ! -f "$PROJECT_DIR/orca.sh" ]; then
        fail "orca wrapper adds an explicit directory (orca.sh is missing)"
        rm -rf "$fixture_root"
        return
    fi

    prepare_orca_wrapper_fixture "$fixture_root"
    expected_project_path="$(cd "$fixture_root/project" && pwd -P)"
    printf '%s\n' \
      repo \
      add \
      --path \
      "$expected_project_path" \
      --json \
      > "$expected_log"

    (
        cd "$fixture_root/project" || exit 1
        PATH="$fixture_root/wrapper-bin:$fixture_root/real-bin:/usr/bin:/bin" \
          ORCA_TEST_LOG="$fixture_root/actual.log" \
          orca .
    )
    status=$?

    if [ "$status" -eq 0 ] \
       && cmp -s "$expected_log" "$fixture_root/actual.log"; then
        pass "orca wrapper adds an explicit directory"
    else
        fail "orca wrapper adds an explicit directory"
    fi

    rm -rf "$fixture_root"
}

test_orca_wrapper_passes_other_commands_through() {
    local fixture_root
    local status

    fixture_root="$(mktemp -d)"

    if [ ! -f "$PROJECT_DIR/orca.sh" ]; then
        fail "orca wrapper passes other commands through (orca.sh is missing)"
        rm -rf "$fixture_root"
        return
    fi

    prepare_orca_wrapper_fixture "$fixture_root"
    mkdir -p "$fixture_root/project/repo"

    (
        cd "$fixture_root/project" || exit 1
        PATH="$fixture_root/wrapper-bin:$fixture_root/real-bin:/usr/bin:/bin" \
          ORCA_TEST_LOG="$fixture_root/actual.log" \
          ORCA_TEST_EXIT=23 \
          orca repo
    )
    status=$?

    if [ "$status" -eq 23 ] \
       && [ "$(cat "$fixture_root/actual.log")" = repo ]; then
        pass "orca wrapper passes other commands through"
    else
        fail "orca wrapper passes other commands through"
    fi

    rm -rf "$fixture_root"
}

run_setup_fixture() {
    local fixture_home="$1"
    local fixture_setup="$2"

    HOME="$fixture_home" \
    SSH_FIXTURE_MODE="${SSH_FIXTURE_MODE:-success}" \
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
        ssh() {
            local argument
            local destination=""

            for argument in "$@"; do
                destination="$argument"
            done

            if [ "$SSH_FIXTURE_MODE" = failure ]; then
                printf "Permission denied (publickey).\n" >&2
                return 255
            fi

            case "$destination" in
                git@github.com)
                    printf "Hi fixture! Authentication succeeded; shell access is disabled.\n" >&2
                    return 1
                    ;;
                git@gitlab.com)
                    printf "Welcome to GitLab, @fixture!\n"
                    return 0
                    ;;
                *)
                    printf "Unexpected SSH destination: %s\n" "$destination" >&2
                    return 255
                    ;;
            esac
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

    run_setup_fixture "$fixture_home" "$fixture_project/setup.sh" 2>/dev/null
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

    if [ -x "$fixture_home/.local/bin/orca" ]; then
        pass "setup installs the Orca wrapper"
    else
        fail "setup installs the Orca wrapper"
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

test_setup_rejects_partial_plugin_install() {
    local fixture_root
    local fixture_home
    local fixture_project
    local plugin
    local status

    if ! all_formulae_installed; then
        return
    fi

    fixture_root="$(mktemp -d)"
    fixture_home="$fixture_root/home"
    fixture_project="$fixture_root/project"
    mkdir -p "$fixture_home/.oh-my-zsh/custom/plugins"
    touch "$fixture_home/.oh-my-zsh/oh-my-zsh.sh"
    setup_fixture_project "$fixture_project"

    for plugin in \
        zsh-completions \
        fzf-tab \
        zsh-autosuggestions \
        zsh-history-substring-search \
        zsh-syntax-highlighting
    do
        mkdir -p "$fixture_home/.oh-my-zsh/custom/plugins/$plugin"
    done

    run_setup_fixture "$fixture_home" "$fixture_project/setup.sh" 2>/dev/null
    status=$?

    if [ "$status" -ne 0 ]; then
        pass "setup rejects an incomplete plugin directory"
    else
        fail "setup rejects an incomplete plugin directory"
    fi

    rm -rf "$fixture_root"
}

test_setup_installs_ssh_keys_without_removing_existing_files() {
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
    mkdir -p "$fixture_home/.ssh"
    chmod 755 "$fixture_home/.ssh"
    printf '%s\n' 'keep this file' > "$fixture_home/.ssh/known_hosts"
    setup_fixture_project "$fixture_project"
    prepare_installed_omz_fixture "$fixture_home"

    run_setup_fixture "$fixture_home" "$fixture_project/setup.sh" 2>/dev/null
    status=$?

    if [ "$status" -eq 0 ] \
       && [ "$(stat -f '%Lp' "$fixture_home/.ssh")" = 700 ] \
       && unzip -p "$fixture_project/ssh-key.zip" ssh-key/2022-sshkey \
          | cmp -s - "$fixture_home/.ssh/2022-sshkey" \
       && unzip -p "$fixture_project/ssh-key.zip" ssh-key/ssh.gitlab.com \
          | cmp -s - "$fixture_home/.ssh/ssh.gitlab.com"; then
        pass "setup installs SSH private keys and secures the SSH directory"
    else
        fail "setup installs SSH private keys and secures the SSH directory"
    fi

    if [ "$(stat -f '%Lp' "$fixture_home/.ssh/2022-sshkey")" = 600 ] \
       && [ "$(stat -f '%Lp' "$fixture_home/.ssh/ssh.gitlab.com")" = 600 ] \
       && [ "$(stat -f '%Lp' "$fixture_home/.ssh/2022-sshkey.pub")" = 644 ] \
       && [ "$(stat -f '%Lp' "$fixture_home/.ssh/ssh.gitlab.com.pub")" = 644 ]; then
        pass "setup applies safe SSH key permissions"
    else
        fail "setup applies safe SSH key permissions"
    fi

    if [ "$(cat "$fixture_home/.ssh/known_hosts")" = 'keep this file' ]; then
        pass "setup keeps unrelated files in the SSH directory"
    else
        fail "setup keeps unrelated files in the SSH directory"
    fi

    rm -rf "$fixture_root"
}

test_setup_rewrites_and_backs_up_ssh_config() {
    local fixture_root
    local fixture_home
    local fixture_project
    local expected_config
    local status

    if ! all_formulae_installed; then
        return
    fi

    fixture_root="$(mktemp -d)"
    fixture_home="$fixture_root/home"
    fixture_project="$fixture_root/project"
    expected_config="$fixture_root/expected-config"
    mkdir -p "$fixture_home/.ssh"
    printf '%s\n' 'old SSH config' > "$fixture_home/.ssh/config"
    printf '%s\n' 'older backup' > "$fixture_home/.ssh/config.backup"
    setup_fixture_project "$fixture_project"
    prepare_installed_omz_fixture "$fixture_home"

    cat > "$expected_config" <<'EOF'
Host github.com
  Preferredauthentications publickey
  IdentityFile ~/.ssh/2022-sshkey
Host gitlab.com
  Preferredauthentications publickey
  IdentityFile ~/.ssh/2022-sshkey
Host gitdev.devops.krungthai.com
  Port 2222
  Preferredauthentications publickey
  IdentityFile ~/.ssh/2022-sshkey

Host *
   ServerAliveInterval 10
EOF

    run_setup_fixture "$fixture_home" "$fixture_project/setup.sh" 2>/dev/null
    status=$?

    if [ "$status" -eq 0 ] \
       && cmp -s "$expected_config" "$fixture_home/.ssh/config" \
       && [ "$(stat -f '%Lp' "$fixture_home/.ssh/config")" = 600 ]; then
        pass "setup rewrites SSH config with the requested hosts"
    else
        fail "setup rewrites SSH config with the requested hosts"
    fi

    if [ "$(cat "$fixture_home/.ssh/config.backup")" = 'old SSH config' ]; then
        pass "setup overwrites the single SSH config backup"
    else
        fail "setup overwrites the single SSH config backup"
    fi

    printf '%s\n' 'next SSH config' > "$fixture_home/.ssh/config"
    run_setup_fixture "$fixture_home" "$fixture_project/setup.sh" 2>/dev/null
    status=$?

    if [ "$status" -eq 0 ] \
       && [ "$(cat "$fixture_home/.ssh/config.backup")" = 'next SSH config' ]; then
        pass "setup refreshes the SSH config backup on every rerun"
    else
        fail "setup refreshes the SSH config backup on every rerun"
    fi

    rm -rf "$fixture_root"
}

test_setup_fails_when_ssh_verification_cannot_connect() {
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

    SSH_FIXTURE_MODE=failure \
      run_setup_fixture "$fixture_home" "$fixture_project/setup.sh" 2>/dev/null
    status=$?

    if [ "$status" -ne 0 ]; then
        pass "setup fails when SSH verification cannot connect"
    else
        fail "setup fails when SSH verification cannot connect"
    fi

    rm -rf "$fixture_root"
}

test_recheck_rejects_broken_fresh_login_startup() {
    local fixture_root
    local fixture_home
    local output
    local status
    local good_path

    fixture_root="$(mktemp -d)"
    fixture_home="$fixture_root/home"
    mkdir -p "$fixture_home"
    prepare_installed_omz_fixture "$fixture_home"

    printf '%s\n' '# Intentionally empty: startup must establish Homebrew PATH itself.' \
      > "$fixture_home/.zshrc"
    mkdir -p "$fixture_home/alternate-zdotdir"
    cp "$PROJECT_DIR/zsh.txt" "$fixture_home/alternate-zdotdir/.zshrc"
    touch "$fixture_home/.zshrc.backup"
    touch "$fixture_home/.gitignore_global"
    touch "$fixture_home/.gitignore_global.backup"
    touch "$fixture_home/.gittag.sh" "$fixture_home/.IntelliJOpen.sh"
    chmod 755 "$fixture_home/.gittag.sh" "$fixture_home/.IntelliJOpen.sh"

    HOME="$fixture_home" "$BREW_PREFIX/bin/git" config --global \
      core.excludesfile "$fixture_home/.gitignore_global"
    HOME="$fixture_home" "$BREW_PREFIX/bin/git" config --global \
      push.autoSetupRemote true

    good_path="$BREW_PREFIX/bin:$BREW_PREFIX/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    output="$(
        HOME="$fixture_home" \
        ZDOTDIR="$fixture_home/alternate-zdotdir" \
        PATH="$good_path" \
        EXPECTED_LOGIN_SHELL="$BREW_PREFIX/bin/zsh" \
        /bin/bash -c '
            dscl() {
                printf "UserShell: %s\n" "$EXPECTED_LOGIN_SHELL"
            }
            source "$0"
        ' "$PROJECT_DIR/recheck-setup.sh" 2>&1
    )"
    status=$?

    if [ "$status" -ne 0 ] \
       && printf '%s\n' "$output" | grep -Fq 'Fresh login shell startup'; then
        pass "recheck rejects a broken fresh login startup"
    else
        fail "recheck rejects a broken fresh login startup"
    fi

    rm -rf "$fixture_root"
}

detect_brew
test_zsh_template_prioritizes_homebrew
test_zsh_template_loads_local_configuration
test_zsh_template_binds_history_substring_search
test_git_prune_local_removes_only_gone_noncurrent_branches
test_zsh_template_omits_unused_plugins
test_orca_wrapper_adds_explicit_directory
test_orca_wrapper_passes_other_commands_through
test_recheck_fails_for_system_first_path
test_setup_preserves_original_backups_on_rerun
test_setup_creates_empty_backup_sentinels
test_setup_rejects_partial_plugin_install
test_setup_installs_ssh_keys_without_removing_existing_files
test_setup_rewrites_and_backs_up_ssh_config
test_setup_fails_when_ssh_verification_cannot_connect
test_recheck_rejects_broken_fresh_login_startup

printf '\nTests: %s, Failures: %s\n' "$TESTS" "$FAILURES"

if [ "$FAILURES" -ne 0 ]; then
    exit 1
fi
