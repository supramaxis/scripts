#!/bin/bash

# Check if the script is being run as root or with sudo
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root or with sudo."
  exit 1
fi

# Get the username of the user who ran the script with sudo
USER_NAME=${SUDO_USER:-$(whoami)}

# Define color codes
# RED='\033[0;31m'
GREEN='\033[0;32m'
# YELLOW='\033[0;33m'
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

ZSH_CONFIG_FILES=(~/.zshenv ~/.zprofile ~/.zshrc ~/.zlogin ~/.zlogout ~/.oh-my-zsh)

for rc in "${ZSH_CONFIG_FILES[@]}"; do
  if [ -e "$rc" ]; then
    cp -r "$rc" ~/zsh-backup/ && rm -rf "$rc"
  fi
done

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
  mkdir cascadiacode && cd cascadiacode || exit
  log "${GREEN}Installing CascadiaCode font${RESET}"
  wget https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaCode.zip
  unzip CascadiaCode.zip
  mv ./*.ttf /usr/share/fonts
  log "${GREEN}Moved downloaded fonts to /usr/share/fonts${RESET}"
  fc-cache -fv
  cd ..
  rm -rf cascadiacode
fi

log "${GREEN}Downloading Oh My Posh${RESET}"
curl -s https://ohmyposh.dev/install.sh | bash -s


log "${GREEN}Cloning and installing fzf${RESET}"
git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
bash ~/.fzf/install --all

log "${GREEN}Installing zoxide${RESET}"
wget -O - https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash


sudo -u ${USER_NAME} bash << 'EOF'
cd ~
mkdir -p $HOME/.config/ohmyposh/
echo -e "[init] \033[0;32mDownloading .zshrc\033[0m"
wget -O ~/.zshrc https://raw.githubusercontent.com/supramaxis/scripts/main/customization/omp.zshrc
wget -O ~/.config/ohmyposh/spm.toml https://raw.githubusercontent.com/supramaxis/scripts/main/customization/spm.toml
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

log "${GREEN}Installing lsd${RESET}"
wget "$LSD_URL"
dpkg -i "$(basename $LSD_URL)"
rm "$(basename $LSD_URL)"

log "${GREEN}Installing vivid${RESET}"
wget "$VIVID_URL"
dpkg -i "$(basename "$VIVID_URL")"
rm "$(basename "$VIVID_URL")"

cp $HOME/.local/bin/zoxide /usr/local/bin

log "${GREEN}Process complete changing to zsh. Please run source ~/.zshrc${RESET}"

# Determine ZDOTDIR based on whether running as root or not
ZDOTDIR=$([ "$EUID" -eq 0 ] && echo "/root" || echo "/home/${USER_NAME}")

exec zsh -i
