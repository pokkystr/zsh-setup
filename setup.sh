#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "======================================"
echo " macOS ZSH Environment Setup"
echo "======================================"

# --------------------------------------------------
# 1. Install Homebrew
# --------------------------------------------------
if ! command -v brew >/dev/null 2>&1; then
    echo "[1/7] Installing Homebrew..."

    /bin/bash -c "$(curl -fsSL \
      https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
    echo "[1/7] Homebrew already installed"
fi

# Apple Silicon Homebrew
if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# --------------------------------------------------
# 2. Install ZSH + packages
# --------------------------------------------------
echo "[2/7] Installing packages..."

brew install zsh git git-extras fzf

# --------------------------------------------------
# 3. Install Oh My Zsh
# --------------------------------------------------
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "[3/7] Installing Oh My Zsh..."

    RUNZSH=no CHSH=no sh -c \
      "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
    echo "[3/7] Oh My Zsh already installed"
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

# --------------------------------------------------
# 4. Install ZSH plugins
# --------------------------------------------------
echo "[4/7] Installing ZSH plugins..."

if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
    git clone \
      https://github.com/zsh-users/zsh-autosuggestions \
      "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
fi

if [ ! -d "$ZSH_CUSTOM/plugins/zsh-completions" ]; then
    git clone \
      https://github.com/zsh-users/zsh-completions \
      "$ZSH_CUSTOM/plugins/zsh-completions"
fi

if [ ! -d "$ZSH_CUSTOM/plugins/zsh-history-substring-search" ]; then
    git clone \
      https://github.com/zsh-users/zsh-history-substring-search \
      "$ZSH_CUSTOM/plugins/zsh-history-substring-search"
fi

if [ ! -d "$ZSH_CUSTOM/plugins/fzf-tab" ]; then
    git clone \
      https://github.com/Aloxaf/fzf-tab \
      "$ZSH_CUSTOM/plugins/fzf-tab"
fi

if [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]; then
    git clone \
      https://github.com/zsh-users/zsh-syntax-highlighting.git \
      "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
fi

# --------------------------------------------------
# 5. Restore .zshrc
# --------------------------------------------------
echo "[5/7] Restoring .zshrc..."

if [ -f "$HOME/.zshrc" ]; then
    BACKUP="$HOME/.zshrc.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$HOME/.zshrc" "$BACKUP"

    echo "Backup:"
    echo "  $BACKUP"
fi

cp "$SCRIPT_DIR/zsh.txt" "$HOME/.zshrc"

# --------------------------------------------------
# 6. Install helper scripts
# --------------------------------------------------
echo "[6/7] Installing helper scripts..."

cp "$SCRIPT_DIR/gittag.sh" "$HOME/.gittag.sh"
chmod +x "$HOME/.gittag.sh"

cp "$SCRIPT_DIR/IntelliJOpen.sh" "$HOME/.IntelliJOpen.sh"
chmod +x "$HOME/.IntelliJOpen.sh"

# Fix IntelliJ alias because original zsh.txt points to Documents
sed -i '' \
  's|alias idea=/Users/pigke/Documents/IntelliJOpen.sh|alias idea="$HOME/IntelliJOpen.sh"|' \
  "$HOME/.zshrc"

# --------------------------------------------------
# 7. Set ZSH as default shell
# --------------------------------------------------
echo "[7/7] Checking default shell..."

ZSH_PATH="$(command -v zsh)"

if [ "$SHELL" != "$ZSH_PATH" ]; then

    if ! grep -qx "$ZSH_PATH" /etc/shells; then
        echo "$ZSH_PATH" | sudo tee -a /etc/shells
    fi

    chsh -s "$ZSH_PATH"
fi

echo
echo "======================================"
echo " Setup completed"
echo "======================================"
echo
echo "Run:"
echo
echo "    source ~/.zshrc"
echo
echo "or restart Terminal."
