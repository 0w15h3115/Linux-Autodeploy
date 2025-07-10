#!/bin/bash

# Simple Ubuntu Security Tools Installation Script
# Run with: sudo bash install-tools.sh

# Exit on error
set -e

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)"
   exit 1
fi

echo "[+] Starting security tools installation..."

# Update system
echo "[+] Updating system..."
apt update
apt upgrade -y

# Install basic dependencies and tools
echo "[+] Installing basic tools and dependencies..."
apt install -y \
    build-essential \
    python3 \
    python3-pip \
    python3-venv \
    pipx \
    git \
    curl \
    wget \
    tmux \
    nmap \
    netcat-openbsd \
    binwalk \
    smbclient \
    dnsutils \
    hashcat \
    default-jre \
    openjdk-11-jre \
    zsh \
    kitty \
    i3 \
    i3status \
    i3lock \
    dmenu \
    polybar \
    fonts-powerline

# Ensure pipx is in PATH
pipx ensurepath

# Install Python tools
echo "[+] Installing Python security tools..."
pipx install impacket
pip3 install netexec
pip3 install certipy-ad

# Install dnsrecon and dnsenum
echo "[+] Installing DNS enumeration tools..."
pip3 install dnsrecon

# Install dnsenum manually
cd /tmp
git clone https://github.com/fwaeytens/dnsenum.git
cd dnsenum
chmod +x dnsenum.pl
cp dnsenum.pl /usr/local/bin/dnsenum
cd ..
rm -rf dnsenum

# Install Oh My Zsh with custom config
echo "[+] Installing Oh My Zsh..."
if [ -n "$SUDO_USER" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    
    # Install Oh My Zsh
    su - "$SUDO_USER" -c 'sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended'
    
    # Set zsh as default shell
    chsh -s /usr/bin/zsh "$SUDO_USER"
    
    # Configure .zshrc with useful plugins and theme
    if [ -f "$USER_HOME/.zshrc" ]; then
        # Backup original
        cp "$USER_HOME/.zshrc" "$USER_HOME/.zshrc.backup"
        
        # Set theme to agnoster
        sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="agnoster"/' "$USER_HOME/.zshrc"
        
        # Enable useful plugins for security work
        sed -i 's/plugins=(git)/plugins=(git docker python pip nmap ssh-agent sudo tmux colored-man-pages command-not-found extract z)/' "$USER_HOME/.zshrc"
        
        # Add custom aliases for security tools
        cat >> "$USER_HOME/.zshrc" << 'EOF'

# Add local bin to PATH if not already there
export PATH="$HOME/.local/bin:$PATH"

# Security tool aliases
alias nse='ls /usr/share/nmap/scripts/ | grep'
alias smbmap='smbclient -L'
alias hashcat64='hashcat'
alias serve='python3 -m http.server'
alias pyserve='python3 -m http.server'
alias phpserve='php -S 0.0.0.0:8000'

# Network aliases
alias ports='netstat -tulanp'
alias listening='netstat -tlnp'
alias myip='curl -s ifconfig.me'

# Useful functions
extract_all() {
    for file in "$@"; do
        if [ -f "$file" ]; then
            case $file in
                *.tar.bz2)   tar xjf "$file"     ;;
                *.tar.gz)    tar xzf "$file"     ;;
                *.bz2)       bunzip2 "$file"     ;;
                *.rar)       unrar e "$file"     ;;
                *.gz)        gunzip "$file"      ;;
                *.tar)       tar xf "$file"      ;;
                *.tbz2)      tar xjf "$file"     ;;
                *.tgz)       tar xzf "$file"     ;;
                *.zip)       unzip "$file"       ;;
                *.Z)         uncompress "$file"  ;;
                *.7z)        7z x "$file"        ;;
                *)           echo "'$file' cannot be extracted" ;;
            esac
        else
            echo "'$file' is not a valid file"
        fi
    done
}

# Quick base64 encode/decode
b64e() { echo -n "$1" | base64; }
b64d() { echo -n "$1" | base64 -d; }

# Quick URL encode/decode
urlencode() { python3 -c "import urllib.parse; print(urllib.parse.quote('$1'))"; }
urldecode() { python3 -c "import urllib.parse; print(urllib.parse.unquote('$1'))"; }
EOF
        
        chown "$SUDO_USER:$SUDO_USER" "$USER_HOME/.zshrc"
    fi
fi

# Install Oh My Zsh for root too
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

# Configure root's zsh with same settings
if [ -f "/root/.zshrc" ]; then
    sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="agnoster"/' "/root/.zshrc"
    sed -i 's/plugins=(git)/plugins=(git docker python pip nmap ssh-agent sudo tmux colored-man-pages command-not-found extract z)/' "/root/.zshrc"
    
    # Add the same aliases to root's zshrc
    cat >> "/root/.zshrc" << 'EOF'

# Add local bin to PATH if not already there
export PATH="$HOME/.local/bin:$PATH"

# Security tool aliases
alias nse='ls /usr/share/nmap/scripts/ | grep'
alias smbmap='smbclient -L'
alias hashcat64='hashcat'
alias serve='python3 -m http.server'
alias pyserve='python3 -m http.server'
alias phpserve='php -S 0.0.0.0:8000'

# Network aliases
alias ports='netstat -tulanp'
alias listening='netstat -tlnp'
alias myip='curl -s ifconfig.me'

# Useful functions
extract_all() {
    for file in "$@"; do
        if [ -f "$file" ]; then
            case $file in
                *.tar.bz2)   tar xjf "$file"     ;;
                *.tar.gz)    tar xzf "$file"     ;;
                *.bz2)       bunzip2 "$file"     ;;
                *.rar)       unrar e "$file"     ;;
                *.gz)        gunzip "$file"      ;;
                *.tar)       tar xf "$file"      ;;
                *.tbz2)      tar xjf "$file"     ;;
                *.tgz)       tar xzf "$file"     ;;
                *.zip)       unzip "$file"       ;;
                *.Z)         uncompress "$file"  ;;
                *.7z)        7z x "$file"        ;;
                *)           echo "'$file' cannot be extracted" ;;
            esac
        else
            echo "'$file' is not a valid file"
        fi
    done
}

# Quick base64 encode/decode
b64e() { echo -n "$1" | base64; }
b64d() { echo -n "$1" | base64 -d; }

# Quick URL encode/decode
urlencode() { python3 -c "import urllib.parse; print(urllib.parse.quote('$1'))"; }
urldecode() { python3 -c "import urllib.parse; print(urllib.parse.unquote('$1'))"; }
EOF
fi

# Set zsh as default shell for root
chsh -s /usr/bin/zsh

# Set kitty as the default terminal
echo "[+] Setting kitty as default terminal..."
update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/bin/kitty 50
update-alternatives --set x-terminal-emulator /usr/bin/kitty

# Set zsh as default shell for root
chsh -s /usr/bin/zsh

# Set kitty as the default terminal
echo "[+] Setting kitty as default terminal..."
update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/bin/kitty 50
update-alternatives --set x-terminal-emulator /usr/bin/kitty

# Install Obsidian via snap
echo "[+] Installing Obsidian..."
snap install obsidian --classic || echo "Failed to install Obsidian"

# Create basic i3 config to use kitty
if [ -n "$SUDO_USER" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    mkdir -p "$USER_HOME/.config/i3"
    
    # If no config exists, create a simple one
    if [ ! -f "$USER_HOME/.config/i3/config" ]; then
        echo "# i3 config - using kitty as default terminal" > "$USER_HOME/.config/i3/config"
        echo "set \$mod Mod4" >> "$USER_HOME/.config/i3/config"
        echo "bindsym \$mod+Return exec kitty" >> "$USER_HOME/.config/i3/config"
        echo "bindsym \$mod+Shift+q kill" >> "$USER_HOME/.config/i3/config"
        echo "bindsym \$mod+d exec dmenu_run" >> "$USER_HOME/.config/i3/config"
        echo "exec_always --no-startup-id \$HOME/.config/polybar/launch.sh" >> "$USER_HOME/.config/i3/config"
    fi
    
    # Create polybar config
    POLYBAR_CONFIG_DIR="$USER_HOME/.config/polybar"
    mkdir -p "$POLYBAR_CONFIG_DIR"
    
    # Create launch script
    cat > "$POLYBAR_CONFIG_DIR/launch.sh" << 'EOF'
#!/bin/bash
killall -q polybar
while pgrep -u $UID -x polybar >/dev/null; do sleep 1; done
polybar main &
EOF
    chmod +x "$POLYBAR_CONFIG_DIR/launch.sh"
    
    # Create basic polybar config (minimal version)
    cat > "$POLYBAR_CONFIG_DIR/config.ini" << 'EOF'
[colors]
background = #282A2E
foreground = #C5C8C6
primary = #F0C674

[bar/main]
width = 100%
height = 24pt
background = ${colors.background}
foreground = ${colors.foreground}
padding-right = 1
module-margin = 1
font-0 = monospace;2
modules-left = i3
modules-center = date
modules-right = cpu memory

[module/i3]
type = internal/i3
index-sort = true
label-focused = %index%
label-focused-background = #373B41
label-focused-underline= ${colors.primary}
label-focused-padding = 1
label-unfocused = %index%
label-unfocused-padding = 1

[module/cpu]
type = internal/cpu
interval = 2
label = CPU %percentage:2%%

[module/memory]
type = internal/memory
interval = 2
label = MEM %percentage_used:2%%

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d %H:%M:%S
label = %date%
label-foreground = ${colors.primary}
EOF
    
    chown -R "$SUDO_USER:$SUDO_USER" "$USER_HOME/.config"
fi

# Add Python scripts to PATH
echo "[+] Configuring PATH..."
cat > /etc/profile.d/security-tools.sh << 'EOF'
# Add Python user base bin to PATH
if [ -d "$HOME/.local/bin" ]; then
    export PATH="$HOME/.local/bin:$PATH"
fi

# Add Python3 scripts to PATH
if [ -d "/usr/local/bin" ]; then
    export PATH="/usr/local/bin:$PATH"
fi
EOF

chmod +x /etc/profile.d/security-tools.sh

# Quick verification
echo ""
echo "=== Installation Summary ==="
echo "Installed tools:"
echo "- Network: nmap, netcat, smbclient, dnsutils, dnsrecon, dnsenum"
echo "- Binary: binwalk"
echo "- Password: hashcat"
echo "- Python: impacket, netexec, certipy-ad"
echo "- Desktop: i3, polybar, kitty"
echo "- Shell: zsh with Oh My Zsh (agnoster theme + security plugins)"
echo "- Note taking: Obsidian"
echo "- Java: default-jre, openjdk-11"
echo ""
echo "Current shells:"
echo "- Root: $(getent passwd root | cut -d: -f7)"
if [ -n "$SUDO_USER" ]; then
    echo "- $SUDO_USER: $(getent passwd "$SUDO_USER" | cut -d: -f7)"
fi
echo ""
echo ""
echo "[!] IMPORTANT: Next Steps"
echo "[!] 1. Log out and log back in for zsh to become your default shell"
echo "[!] 2. Or run 'exec zsh' to switch to zsh in the current session"
echo "[!] 3. Kitty is now the default terminal - run 'kitty' to open it"
echo "[!] 4. In i3 window manager: Mod+Enter will open kitty"
echo "[!] 5. To start i3: log out and select i3 from login screen"
echo "[!] 6. Run 'source /etc/profile.d/security-tools.sh' to update PATH now"
