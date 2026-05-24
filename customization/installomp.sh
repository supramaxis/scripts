#!/bin/bash

# Check if the script is being run as root or with sudo
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root or with sudo."
  exit 1
fi

# Get the username of the user who ran the script with sudo
USER_NAME=${SUDO_USER:-$(whoami)}

# Get the real home directory of that user
USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6)

if [ -z "$USER_HOME" ] || [ ! -d "$USER_HOME" ]; then
  echo "Could not determine home directory for user: $USER_NAME"
  exit 1
fi

# Define color codes
GREEN='\033[0;32m'
RESET='\033[0m'

function log() {
  echo -e "[init] $*"
}

# Install Zsh if it's not already installed
if ! command -v zsh &> /dev/null; then
  log "${GREEN}Installing Zsh${RESET}"
  apt update
  apt install -y zsh
fi

# Backup existing Zsh config files from the real user, not root
mkdir -p "$USER_HOME/zsh-backup"

ZSH_CONFIG_FILES=(
  "$USER_HOME/.zshenv"
  "$USER_HOME/.zprofile"
  "$USER_HOME/.zshrc"
  "$USER_HOME/.zlogin"
  "$USER_HOME/.zlogout"
  "$USER_HOME/.oh-my-zsh"
)

for rc in "${ZSH_CONFIG_FILES[@]}"; do
  if [ -e "$rc" ]; then
    cp -r "$rc" "$USER_HOME/zsh-backup/" && rm -rf "$rc"
  fi
done

chown -R "$USER_NAME:$USER_NAME" "$USER_HOME/zsh-backup"

# Function to check if a package is installed
function is_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -c "ok installed"
}

# Install required packages if they are not already installed
REQUIRED_PACKAGES=(fontconfig unzip git wget nano curl)

for pkg in "${REQUIRED_PACKAGES[@]}"; do
  if [ "$(is_installed "$pkg")" -eq 0 ]; then
    log "${GREEN}Installing $pkg${RESET}"
    apt install -y "$pkg"
  else
    log "${GREEN}$pkg is already installed${RESET}"
  fi
done

# Check if fonts are already installed
if ! ls /usr/share/fonts/*.ttf &> /dev/null; then
  mkdir -p /tmp/cascadiacode
  cd /tmp/cascadiacode || exit 1

  log "${GREEN}Installing CascadiaCode font${RESET}"
  wget https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaCode.zip
  unzip CascadiaCode.zip
  mv ./*.ttf /usr/share/fonts/

  log "${GREEN}Moved downloaded fonts to /usr/share/fonts${RESET}"
  fc-cache -fv

  cd /tmp || exit 1
  rm -rf /tmp/cascadiacode
fi

# Install Oh My Posh globally
log "${GREEN}Downloading Oh My Posh${RESET}"
curl -s https://ohmyposh.dev/install.sh | bash -s

# Install fzf as the real user, not root
log "${GREEN}Cloning and installing fzf for ${USER_NAME}${RESET}"
sudo -u "$USER_NAME" bash << 'EOF'
cd "$HOME" || exit 1

if [ ! -d "$HOME/.fzf" ]; then
  git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
fi

"$HOME/.fzf/install" --all
EOF

# Install zoxide as the real user
log "${GREEN}Installing zoxide for ${USER_NAME}${RESET}"
sudo -u "$USER_NAME" bash << 'EOF'
cd "$HOME" || exit 1
wget -O - https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
EOF

# Copy zoxide binary globally if it exists
if [ -f "$USER_HOME/.local/bin/zoxide" ]; then
  install -m 755 "$USER_HOME/.local/bin/zoxide" /usr/local/bin/zoxide
else
  echo "zoxide binary was not found at $USER_HOME/.local/bin/zoxide"
  exit 1
fi

# Download .zshrc and Oh My Posh config as the real user
sudo -u "$USER_NAME" bash << 'EOF'
cd "$HOME" || exit 1

mkdir -p "$HOME/.config/ohmyposh/"

echo -e "[init] \033[0;32mDownloading .zshrc\033[0m"

wget -O "$HOME/.zshrc" https://raw.githubusercontent.com/supramaxis/scripts/main/customization/omp.zshrc
wget -O "$HOME/.config/ohmyposh/spm.toml" https://raw.githubusercontent.com/supramaxis/scripts/main/customization/spm.toml
EOF

# Patch .zshrc for fzf path and lsd preview bug
sudo -u "$USER_NAME" bash << 'EOF'
# Ensure fzf is available in PATH
grep -q 'HOME/.fzf/bin' "$HOME/.zshrc" || \
  sed -i '/# Shell integrations/a export PATH="$HOME/.fzf/bin:$PATH"' "$HOME/.zshrc"

# Fix lsd --color usage in fzf-tab preview
sed -i 's|lsd --color \$realpath|lsd --color=always -- \$realpath|g' "$HOME/.zshrc"
EOF

# Determine architecture
ARCH=$(uname -m)

case "$ARCH" in
  x86_64)
    LSD_URL="https://github.com/lsd-rs/lsd/releases/download/v1.1.2/lsd-musl_1.1.2_amd64.deb"
    VIVID_URL="https://github.com/sharkdp/vivid/releases/download/v0.9.0/vivid-musl_0.9.0_amd64.deb"
    ;;
  aarch64)
    LSD_URL="https://github.com/lsd-rs/lsd/releases/download/v1.1.2/lsd-musl_1.1.2_arm64.deb"
    VIVID_URL="https://github.com/sharkdp/vivid/releases/download/v0.9.0/vivid_0.9.0_arm64.deb"
    ;;
  *)
    echo "Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

# Install lsd
log "${GREEN}Installing lsd${RESET}"
cd /tmp || exit 1
wget "$LSD_URL"
dpkg -i "$(basename "$LSD_URL")"
rm "$(basename "$LSD_URL")"

# Install vivid
log "${GREEN}Installing vivid${RESET}"
cd /tmp || exit 1
wget "$VIVID_URL"
dpkg -i "$(basename "$VIVID_URL")"
rm "$(basename "$VIVID_URL")"

# Fix ownership of user config files
chown -R "$USER_NAME:$USER_NAME" \
  "$USER_HOME/.fzf" \
  "$USER_HOME/.config" \
  "$USER_HOME/.zshrc" \
  "$USER_HOME/.local" \
  2>/dev/null || true

# Optional: change default shell to zsh for the real user
if command -v zsh &> /dev/null; then
  log "${GREEN}Changing default shell to zsh for ${USER_NAME}${RESET}"
  chsh -s "$(command -v zsh)" "$USER_NAME"
fi

log "${GREEN}Process complete.${RESET}"
log "${GREEN}Open a new terminal or run: zsh${RESET}"
