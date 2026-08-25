#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

printf '%s\n' \
  '======================================' \
  ' macOS ZSH Environment Setup' \
  '======================================'


# ==================================================
# 1. Project files
# ==================================================

printf '%s\n' '[1/11] Checking project files...'

for required_file in \
    zsh.txt \
    gitignore_global.txt \
    gittag.sh \
    IntelliJOpen.sh \
    ssh-key.zip
do
    if [ ! -f "$SCRIPT_DIR/$required_file" ]; then
        printf 'ERROR: Required project file not found: %s\n' \
          "$SCRIPT_DIR/$required_file" >&2
        exit 1
    fi
done


# ==================================================
# 2. Homebrew
# ==================================================

printf '%s\n' '[2/11] Checking Homebrew...'

if [ -x /opt/homebrew/bin/brew ]; then
    BREW_BIN=/opt/homebrew/bin/brew
elif [ -x /usr/local/bin/brew ]; then
    BREW_BIN=/usr/local/bin/brew
else
    printf '%s\n' 'Installing Homebrew...'
    /bin/bash -c "$(curl -fsSL \
      https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    if [ -x /opt/homebrew/bin/brew ]; then
        BREW_BIN=/opt/homebrew/bin/brew
    elif [ -x /usr/local/bin/brew ]; then
        BREW_BIN=/usr/local/bin/brew
    else
        printf '%s\n' 'ERROR: Homebrew installation not found in a standard prefix' >&2
        exit 1
    fi
fi

eval "$("$BREW_BIN" shellenv)"
hash -r

BREW_PREFIX="$("$BREW_BIN" --prefix)"

printf 'Homebrew: %s\n' "$BREW_BIN"


# ==================================================
# 3. Original backups
# ==================================================

printf '%s\n' '[3/11] Preserving original configuration...'

if [ ! -e "$HOME/.zshrc.backup" ]; then
    if [ -e "$HOME/.zshrc" ]; then
        cp -p "$HOME/.zshrc" "$HOME/.zshrc.backup"
        printf 'Original backup created: %s\n' "$HOME/.zshrc.backup"
    else
        touch "$HOME/.zshrc.backup"
        printf 'Empty backup sentinel created: %s\n' "$HOME/.zshrc.backup"
    fi
else
    printf 'Keeping existing backup: %s\n' "$HOME/.zshrc.backup"
fi

if [ ! -e "$HOME/.gitignore_global.backup" ]; then
    if [ -e "$HOME/.gitignore_global" ]; then
        cp -p "$HOME/.gitignore_global" "$HOME/.gitignore_global.backup"
        printf 'Original backup created: %s\n' "$HOME/.gitignore_global.backup"
    else
        touch "$HOME/.gitignore_global.backup"
        printf 'Empty backup sentinel created: %s\n' \
          "$HOME/.gitignore_global.backup"
    fi
else
    printf 'Keeping existing backup: %s\n' "$HOME/.gitignore_global.backup"
fi


# ==================================================
# 4. Homebrew packages
# ==================================================

printf '%s\n' '[4/11] Installing Homebrew packages...'

for formula in zsh git git-extras fzf; do
    if "$BREW_BIN" list --formula "$formula" >/dev/null 2>&1; then
        printf '%s already installed\n' "$formula"
    else
        "$BREW_BIN" install "$formula"
    fi
done

ZSH_PATH="$BREW_PREFIX/bin/zsh"
GIT_BIN="$BREW_PREFIX/bin/git"

if [ ! -x "$ZSH_PATH" ]; then
    printf 'ERROR: Homebrew ZSH not found: %s\n' "$ZSH_PATH" >&2
    exit 1
fi

if [ ! -x "$GIT_BIN" ]; then
    printf 'ERROR: Homebrew Git not found: %s\n' "$GIT_BIN" >&2
    exit 1
fi


# ==================================================
# 5. Oh My Zsh
# ==================================================

printf '%s\n' '[5/11] Checking Oh My Zsh...'

OMZ_DIR="$HOME/.oh-my-zsh"
ZSH_CUSTOM="$OMZ_DIR/custom"

if [ ! -e "$OMZ_DIR" ]; then
    printf '%s\n' 'Installing Oh My Zsh...'
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes ZSH="$OMZ_DIR" sh -c \
      "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
      '' --unattended --keep-zshrc
elif [ ! -f "$OMZ_DIR/oh-my-zsh.sh" ]; then
    printf 'ERROR: Incomplete Oh My Zsh installation: %s\n' \
      "$OMZ_DIR" >&2
    printf '%s\n' 'Remove or repair that directory, then run setup again.' >&2
    exit 1
else
    printf '%s\n' 'Oh My Zsh already installed'
fi

if [ ! -f "$OMZ_DIR/oh-my-zsh.sh" ]; then
    printf 'ERROR: Oh My Zsh entrypoint not found: %s\n' \
      "$OMZ_DIR/oh-my-zsh.sh" >&2
    exit 1
fi

mkdir -p "$ZSH_CUSTOM/plugins"


# ==================================================
# 6. ZSH plugins
# ==================================================

printf '%s\n' '[6/11] Installing ZSH plugins...'

install_plugin() {
    local name="$1"
    local repo="$2"
    local entrypoint="$3"
    local target="$ZSH_CUSTOM/plugins/$name"

    if [ -d "$target" ]; then
        if [ -f "$target/$entrypoint" ]; then
            printf '%s already installed\n' "$name"
            return
        fi

        printf 'ERROR: Incomplete plugin installation: %s\n' "$target" >&2
        printf '%s\n' 'Remove or repair that directory, then run setup again.' >&2
        exit 1
    fi

    if [ -e "$target" ]; then
        printf 'ERROR: Plugin target exists but is not a directory: %s\n' \
          "$target" >&2
        exit 1
    fi

    printf 'Installing %s...\n' "$name"
    "$GIT_BIN" clone --depth=1 "$repo" "$target"

    if [ ! -f "$target/$entrypoint" ]; then
        printf 'ERROR: Plugin entrypoint not found after clone: %s\n' \
          "$target/$entrypoint" >&2
        exit 1
    fi
}

install_plugin zsh-completions \
  https://github.com/zsh-users/zsh-completions \
  zsh-completions.plugin.zsh
install_plugin fzf-tab \
  https://github.com/Aloxaf/fzf-tab \
  fzf-tab.plugin.zsh
install_plugin zsh-autosuggestions \
  https://github.com/zsh-users/zsh-autosuggestions \
  zsh-autosuggestions.plugin.zsh
install_plugin zsh-history-substring-search \
  https://github.com/zsh-users/zsh-history-substring-search \
  zsh-history-substring-search.plugin.zsh
install_plugin zsh-syntax-highlighting \
  https://github.com/zsh-users/zsh-syntax-highlighting \
  zsh-syntax-highlighting.plugin.zsh


# ==================================================
# 7. User configuration
# ==================================================

printf '%s\n' '[7/11] Installing user configuration...'

install -m 644 "$SCRIPT_DIR/zsh.txt" "$HOME/.zshrc"
install -m 644 "$SCRIPT_DIR/gitignore_global.txt" "$HOME/.gitignore_global"

install -m 755 "$SCRIPT_DIR/gittag.sh" "$HOME/.gittag.sh"
xattr -d com.apple.quarantine \
  "$HOME/.gittag.sh" 2>/dev/null || true

install -m 755 "$SCRIPT_DIR/IntelliJOpen.sh" "$HOME/.IntelliJOpen.sh"
xattr -d com.apple.quarantine \
  "$HOME/.IntelliJOpen.sh" 2>/dev/null || true

"$GIT_BIN" config --global core.excludesfile "$HOME/.gitignore_global"
"$GIT_BIN" config --global push.autoSetupRemote true

printf 'Installed: %s\n' \
  "$HOME/.zshrc" \
  "$HOME/.gitignore_global" \
  "$HOME/.gittag.sh" \
  "$HOME/.IntelliJOpen.sh"


# ==================================================
# 8. SSH keys and configuration
# ==================================================

printf '%s\n' '[8/11] Installing SSH keys and configuration...'

SSH_DIR="$HOME/.ssh"
SSH_KEY_ARCHIVE="$SCRIPT_DIR/ssh-key.zip"
SSH_KEY_TEMP_DIR="$(mktemp -d)"

cleanup_ssh_key_temp() {
    rm -rf "$SSH_KEY_TEMP_DIR"
}

trap cleanup_ssh_key_temp EXIT HUP INT TERM

install -d -m 700 "$SSH_DIR"
/usr/bin/unzip -q "$SSH_KEY_ARCHIVE" -d "$SSH_KEY_TEMP_DIR"

for private_key in 2022-sshkey ssh.gitlab.com; do
    if [ ! -f "$SSH_KEY_TEMP_DIR/ssh-key/$private_key" ]; then
        printf 'ERROR: SSH private key not found in archive: %s\n' \
          "ssh-key/$private_key" >&2
        exit 1
    fi

    install -m 600 \
      "$SSH_KEY_TEMP_DIR/ssh-key/$private_key" \
      "$SSH_DIR/$private_key"
done

for public_key in 2022-sshkey.pub ssh.gitlab.com.pub; do
    if [ -f "$SSH_KEY_TEMP_DIR/ssh-key/$public_key" ]; then
        install -m 644 \
          "$SSH_KEY_TEMP_DIR/ssh-key/$public_key" \
          "$SSH_DIR/$public_key"
    fi
done

if [ -f "$SSH_DIR/config" ]; then
    cp -p "$SSH_DIR/config" "$SSH_DIR/config.backup"
    chmod 600 "$SSH_DIR/config.backup"
    printf 'SSH config backup refreshed: %s\n' "$SSH_DIR/config.backup"
fi

cat > "$SSH_KEY_TEMP_DIR/config" <<'EOF'
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

install -m 600 "$SSH_KEY_TEMP_DIR/config" "$SSH_DIR/config"

cleanup_ssh_key_temp
trap - EXIT HUP INT TERM

printf 'Installed SSH keys and config in: %s\n' "$SSH_DIR"


# ==================================================
# 9. Default shell
# ==================================================

printf '%s\n' '[9/11] Checking default shell...'

if ! grep -Fqx "$ZSH_PATH" /etc/shells; then
    printf 'Adding Homebrew ZSH to /etc/shells: %s\n' "$ZSH_PATH"
    printf '%s\n' "$ZSH_PATH" | sudo tee -a /etc/shells >/dev/null
fi

CURRENT_LOGIN_SHELL="$(
    dscl . -read "$HOME" UserShell 2>/dev/null | awk '{print $2}' || true
)"

if [ "$CURRENT_LOGIN_SHELL" != "$ZSH_PATH" ]; then
    printf 'Changing default shell: %s -> %s\n' \
      "${CURRENT_LOGIN_SHELL:-unknown}" "$ZSH_PATH"
    chsh -s "$ZSH_PATH"
else
    printf 'Homebrew ZSH is already the default shell: %s\n' "$ZSH_PATH"
fi


# ==================================================
# 10. Direct verification
# ==================================================

printf '%s\n' \
  '[10/11] Verifying installed tools...' \
  '' \
  '======================================' \
  ' Verification' \
  '======================================'

printf 'Homebrew: %s (%s)\n' \
  "$BREW_BIN" "$("$BREW_BIN" --version | head -1)"
printf 'ZSH:      %s (%s)\n' \
  "$ZSH_PATH" "$("$ZSH_PATH" --version)"
printf 'Git:      %s (%s)\n' \
  "$GIT_BIN" "$("$GIT_BIN" --version)"
printf 'fzf:      %s (%s)\n' \
  "$BREW_PREFIX/bin/fzf" "$("$BREW_PREFIX/bin/fzf" --version)"
printf 'push.autoSetupRemote: %s\n' \
  "$("$GIT_BIN" config --global --get push.autoSetupRemote)"
printf 'core.excludesfile:    %s\n' \
  "$("$GIT_BIN" config --global --get core.excludesfile)"


# ==================================================
# 11. SSH connection verification
# ==================================================

printf '%s\n' '[11/11] Verifying SSH connections...'

verify_ssh_connection() {
    local destination="$1"
    local output
    local status

    if output="$(
        ssh \
          -o BatchMode=yes \
          -o ConnectTimeout=10 \
          -o StrictHostKeyChecking=accept-new \
          -T "$destination" 2>&1
    )"; then
        status=0
    else
        status=$?
    fi

    if [ -n "$output" ]; then
        printf '%s\n' "$output"
    fi

    case "$status" in
        0|1)
            printf 'SSH connection verified: %s\n' "$destination"
            ;;
        *)
            printf 'ERROR: SSH connection failed: %s (exit %s)\n' \
              "$destination" "$status" >&2
            return 1
            ;;
    esac
}

verify_ssh_connection git@github.com
verify_ssh_connection git@gitlab.com

printf '%s\n' \
  '' \
  '======================================' \
  ' Setup completed' \
  '======================================' \
  '' \
  'Open a Homebrew ZSH login shell:' \
  '' \
  '  exec "$(brew --prefix)/bin/zsh" -l' \
  '' \
  'Then verify:' \
  '' \
  '  ./recheck-setup.sh'
