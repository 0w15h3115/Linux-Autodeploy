#!/bin/bash

################################################################################
# Ubuntu Security Tools Installation Script v3.0
#
# Purpose: Install security analysis tools and configure development environment
# Author: Matt Chiu
# Tools: nmap, netexec, impacket, responder, certipy, hashcat, and more
# Environment: i3, polybar, kitty, zsh with oh-my-zsh
################################################################################

set -e  # Exit on error
set -o pipefail  # Catch errors in pipes

# Configuration
readonly SCRIPT_VERSION="3.0"
readonly LOG_FILE="/var/log/security-tools-install.log"
readonly SECURITY_VENV="/opt/security-tools-venv"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Logging
exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== Installation started at $(date) ==="
echo "=== Script version: $SCRIPT_VERSION ==="

################################################################################
# Core Functions
################################################################################

print_status() {
    echo -e "${GREEN}[+]${NC} $1"
}

print_error() {
    echo -e "${RED}[!]${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}[*]${NC} $1"
}

print_section() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run with sudo"
        print_error "Usage: sudo $0"
        exit 1
    fi
}

check_sudo_user() {
    if [ -z "$SUDO_USER" ] || [ "$SUDO_USER" = "root" ]; then
        print_error "This script must be run with sudo, not as root directly"
        print_error "Usage: sudo $0"
        exit 1
    fi
}

get_user_info() {
    ACTUAL_USER="$SUDO_USER"
    USER_HOME=$(getent passwd "$ACTUAL_USER" | cut -d: -f6)
    USER_UID=$(id -u "$ACTUAL_USER")
    USER_GID=$(id -g "$ACTUAL_USER")
}

check_internet() {
    if ! ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
        print_error "No internet connectivity detected"
        exit 1
    fi
}

check_disk_space() {
    local available=$(df / | tail -1 | awk '{print $4}')
    if [ "$available" -lt 5000000 ]; then
        print_warning "Less than 5GB disk space available"
    fi
}

################################################################################
# Installation Functions
################################################################################

install_system_packages() {
    print_section "Installing System Packages"

    # Detect Ubuntu version
    . /etc/os-release
    UBUNTU_VERSION="${VERSION_ID}"
    print_status "Detected Ubuntu $UBUNTU_VERSION"

    # Enable universe repository (required for many security tools)
    print_status "Enabling universe repository..."
    add-apt-repository -y universe

    # Update package lists
    print_status "Updating package lists..."
    apt-get update -y

    local packages=(
        # Build tools
        build-essential git curl wget

        # Python
        python3 python3-pip python3-venv pipx

        # Libraries
        libssl-dev libffi-dev libpcap-dev libgmp3-dev libxml2-dev libxslt1-dev
        zlib1g-dev

        # Network tools
        nmap ncat smbclient dnsutils proxychains4 net-tools binwalk iputils-ping

        # System tools
        tmux fonts-powerline fonts-font-awesome

        # Security tools
        hashcat dnsrecon python3-ldapdomaindump adcli nbtscan

        # Java
        default-jre openjdk-8-jre

        # OpenCL
        ocl-icd-libopencl1 opencl-headers clinfo

        # GUI (without polybar - installed separately due to version constraints)
        i3 i3status i3lock xss-lock dmenu kitty zsh
    )

    print_status "Installing ${#packages[@]} packages..."
    apt-get install -y "${packages[@]}"

    print_status "✓ System packages installed"
}

install_polybar() {
    print_section "Installing Polybar"

    # Detect Ubuntu version
    . /etc/os-release
    UBUNTU_VERSION="${VERSION_ID}"

    # polybar is only available in apt for Ubuntu 20.10+
    # For 20.04, use snap; for 22.04+, use apt from universe
    if [[ "$UBUNTU_VERSION" == "20.04" ]]; then
        print_warning "Ubuntu 20.04 detected - polybar not in repos, installing via snap..."
        if ! snap list | grep -q polybar; then
            snap install polybar-git
            print_status "✓ Polybar installed via snap"
        else
            print_status "Polybar already installed"
        fi
    else
        # Ubuntu 22.04+ has polybar in universe repository
        print_status "Installing polybar from universe repository..."
        if ! dpkg -l | grep -q "^ii.*polybar"; then
            apt-get install -y polybar || {
                print_error "Failed to install polybar from apt"
                print_warning "Falling back to snap installation..."
                snap install polybar-git
            }
            print_status "✓ Polybar installed"
        else
            print_status "Polybar already installed"
        fi
    fi
}

install_snapd() {
    print_section "Installing Snap"

    if command -v snap &>/dev/null; then
        print_status "Snap already installed"
        return 0
    fi

    apt-get install -y snapd
    systemctl enable --now snapd.socket
    ln -sf /var/lib/snapd/snap /snap 2>/dev/null || true
    sleep 3

    print_status "✓ Snapd installed"
}

install_obsidian() {
    print_section "Installing Obsidian"

    if command -v obsidian &>/dev/null; then
        print_status "Obsidian already installed"
        return 0
    fi

    snap install obsidian --classic
    print_status "✓ Obsidian installed"
}

setup_rust() {
    print_section "Installing Rust (required for NetExec)"

    su - "$ACTUAL_USER" -c '
        if command -v rustc &>/dev/null; then
            echo "Rust already installed"
            exit 0
        fi
        curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source ~/.cargo/env
    ' || print_warning "Failed to install Rust"

    print_status "✓ Rust setup complete"
}

install_pipx_tools() {
    print_section "Installing Python Tools (pipx)"

    # Ensure pipx is set up for user
    su - "$ACTUAL_USER" -c '
        python3 -m pip install --user --upgrade pipx
        python3 -m pipx ensurepath
    ' 2>/dev/null

    # Install impacket
    print_status "Installing impacket..."
    su - "$ACTUAL_USER" -c '
        source ~/.cargo/env 2>/dev/null || true
        python3 -m pipx install impacket
    ' || print_warning "Failed to install impacket"

    # Install netexec
    print_status "Installing netexec..."
    su - "$ACTUAL_USER" -c '
        source ~/.cargo/env 2>/dev/null || true
        python3 -m pipx install git+https://github.com/Pennyw0rth/NetExec
    ' || print_warning "Failed to install netexec"

    # Create system-wide symlinks
    local user_bin="$USER_HOME/.local/bin"
    if [ -d "$user_bin" ]; then
        for tool in netexec nxc nxcdb secretsdump.py psexec.py smbexec.py wmiexec.py GetNPUsers.py GetUserSPNs.py; do
            if [ -f "$user_bin/$tool" ]; then
                ln -sf "$user_bin/$tool" /usr/local/bin/ 2>/dev/null || true
            fi
        done
    fi

    print_status "✓ Pipx tools installed"
}

setup_python_venv() {
    print_section "Setting Up Python Virtual Environment"

    # Remove old venv if exists
    [ -d "$SECURITY_VENV" ] && rm -rf "$SECURITY_VENV"

    # Create new venv
    python3 -m venv "$SECURITY_VENV" --system-site-packages
    source "$SECURITY_VENV/bin/activate"

    # Upgrade pip
    pip install --upgrade pip setuptools wheel

    # Install Python packages
    local packages=(
        netifaces aioquic cryptography pyasn1 ldap3
        ldapdomaindump flask pyOpenSSL pycryptodome
    )

    print_status "Installing Python packages in venv..."
    for pkg in "${packages[@]}"; do
        pip install "$pkg" || print_warning "Failed to install $pkg"
    done

    # Install impacket from source
    print_status "Installing impacket from source..."
    cd /tmp
    rm -rf impacket 2>/dev/null || true
    if git clone https://github.com/fortra/impacket.git; then
        cd impacket
        pip install . || print_warning "Failed to install impacket"
        cd /tmp
    fi

    # Install Responder from source
    print_status "Installing Responder from source..."
    cd /tmp
    rm -rf Responder 2>/dev/null || true
    if git clone https://github.com/lgandx/Responder.git; then
        cd Responder
        pip install -r requirements.txt || print_warning "Failed to install Responder deps"
        mkdir -p "$SECURITY_VENV/responder"
        cp -r . "$SECURITY_VENV/responder/"
        chmod +x "$SECURITY_VENV/responder/Responder.py"
        cd /tmp
    fi

    # Install certipy-ad
    print_status "Installing certipy-ad..."
    pip install certipy-ad || print_warning "Failed to install certipy-ad"

    deactivate

    # Set ownership
    chown -R "$ACTUAL_USER:$(id -gn $ACTUAL_USER)" "$SECURITY_VENV"
    chmod -R u+rwX,go+rX "$SECURITY_VENV"

    print_status "✓ Python venv configured"
}

create_wrapper_scripts() {
    print_section "Creating Wrapper Scripts"

    # Responder wrapper
    cat > /usr/local/bin/responder << EOF
#!/bin/bash
source "$SECURITY_VENV/bin/activate"
cd "$SECURITY_VENV/responder"
exec python3 Responder.py "\$@"
EOF
    chmod 755 /usr/local/bin/responder

    # Certipy wrapper
    cat > /usr/local/bin/certipy-venv << EOF
#!/bin/bash
source "$SECURITY_VENV/bin/activate"
exec certipy "\$@"
EOF
    chmod 755 /usr/local/bin/certipy-venv

    print_status "✓ Wrapper scripts created"
}

configure_i3_polybar_kitty() {
    print_section "Configuring i3, Polybar, and Kitty"

    # Configure polybar
    local polybar_dir="$USER_HOME/.config/polybar"
    mkdir -p "$polybar_dir"

    # Create polybar launch script
    cat > "$polybar_dir/launch.sh" << 'EOF'
#!/bin/bash
killall -q polybar
while pgrep -u $UID -x polybar >/dev/null; do sleep 1; done
polybar main &
echo "Polybar launched..."
EOF
    chmod +x "$polybar_dir/launch.sh"

    # Create polybar config
    cat > "$polybar_dir/config.ini" << 'EOF'
[colors]
background = #282A2E
background-alt = #373B41
foreground = #C5C8C6
primary = #F0C674
secondary = #8ABEB7
alert = #A54242
disabled = #707880

[bar/main]
width = 100%
height = 24pt
radius = 0
background = ${colors.background}
foreground = ${colors.foreground}
line-size = 3pt
border-size = 0
border-color = #00000000
padding-left = 0
padding-right = 1
module-margin = 1
separator = |
separator-foreground = ${colors.disabled}
font-0 = monospace;2
font-1 = Font Awesome 6 Free:pixelsize=12;2
font-2 = Font Awesome 6 Free Solid:pixelsize=12;2
font-3 = Font Awesome 6 Brands:pixelsize=12;2
modules-left = i3 xwindow
modules-center = date
modules-right = network network-wireless cpu memory battery
cursor-click = pointer
cursor-scroll = ns-resize
enable-ipc = true

[module/i3]
type = internal/i3
pin-workspaces = true
show-urgent = true
strip-wsnumbers = true
index-sort = true
format = <label-state> <label-mode>
label-focused = %index%
label-focused-background = ${colors.background-alt}
label-focused-underline= ${colors.primary}
label-focused-padding = 1
label-unfocused = %index%
label-unfocused-padding = 1
label-visible = %index%
label-visible-underline = ${colors.secondary}
label-visible-padding = 1
label-urgent = %index%
label-urgent-background = ${colors.alert}
label-urgent-padding = 1

[module/xwindow]
type = internal/xwindow
label = %title:0:60:...%

[module/cpu]
type = internal/cpu
interval = 2
format-prefix = "CPU "
format-prefix-foreground = ${colors.primary}
label = %percentage:2%%

[module/memory]
type = internal/memory
interval = 2
format-prefix = "MEM "
format-prefix-foreground = ${colors.primary}
label = %percentage_used:2%%

[module/network]
type = internal/network
interface-type = wired
interval = 3.0
format-connected = <label-connected>
format-connected-prefix = "NET "
format-connected-prefix-foreground = ${colors.primary}
label-connected = %ifname% %local_ip%
format-disconnected = <label-disconnected>
label-disconnected = disconnected
label-disconnected-foreground = ${colors.disabled}

[module/network-wireless]
type = internal/network
interface-type = wireless
interval = 3.0
format-connected = <label-connected>
format-connected-prefix = "WIFI "
format-connected-prefix-foreground = ${colors.primary}
label-connected = %essid% %local_ip%
format-disconnected = <label-disconnected>
label-disconnected = no wifi
label-disconnected-foreground = ${colors.disabled}

[module/battery]
type = internal/battery
battery = BAT0
adapter = AC
full-at = 98
format-charging = <label-charging>
format-charging-prefix = "BAT+ "
format-charging-prefix-foreground = ${colors.secondary}
label-charging = %percentage%%
format-discharging = <label-discharging>
format-discharging-prefix = "BAT "
format-discharging-prefix-foreground = ${colors.primary}
label-discharging = %percentage%%
format-full-prefix = "FULL "
format-full-prefix-foreground = ${colors.secondary}
label-full = %percentage%%

[module/date]
type = internal/date
interval = 1
date = %Y-%m-%d %H:%M:%S
date-alt = %A, %B %d, %Y %H:%M:%S
label = %date%
label-foreground = ${colors.primary}

[settings]
screenchange-reload = true
pseudo-transparency = false
EOF

    chown -R "$ACTUAL_USER:$(id -gn $ACTUAL_USER)" "$polybar_dir"

    # Configure i3
    local i3_dir="$USER_HOME/.config/i3"
    mkdir -p "$i3_dir"

    # Create basic i3 config if doesn't exist
    if [ ! -f "$i3_dir/config" ]; then
        cat > "$i3_dir/config" << 'EOF'
# i3 config file (v4)
set $mod Mod4
font pango:monospace 8
bindsym $mod+Return exec kitty
bindsym $mod+Shift+q kill
bindsym $mod+d exec dmenu_run
exec_always --no-startup-id $HOME/.config/polybar/launch.sh
EOF
    else
        # Update existing config for polybar
        if ! grep -q "polybar/launch.sh" "$i3_dir/config"; then
            echo "exec_always --no-startup-id \$HOME/.config/polybar/launch.sh" >> "$i3_dir/config"
        fi
    fi

    chown -R "$ACTUAL_USER:$(id -gn $ACTUAL_USER)" "$i3_dir"

    # Configure kitty
    local kitty_dir="$USER_HOME/.config/kitty"
    mkdir -p "$kitty_dir"

    cat > "$kitty_dir/kitty.conf" << 'EOF'
# Kitty Configuration
font_family      monospace
font_size        11.0
shell /usr/bin/zsh
shell_integration enabled
enable_audio_bell no
background_opacity 0.95
background #1e1e1e
scrollback_lines 10000
open_url_with default
detect_urls yes
repaint_delay 10
input_delay 3
sync_to_monitor yes
EOF

    chown -R "$ACTUAL_USER:$(id -gn $ACTUAL_USER)" "$kitty_dir"

    # Set kitty as default terminal
    update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/bin/kitty 50
    update-alternatives --set x-terminal-emulator /usr/bin/kitty

    print_status "✓ GUI configuration complete"
}

configure_zsh() {
    print_section "Configuring Zsh and Oh My Zsh"

    # Set zsh as default shell
    chsh -s /usr/bin/zsh
    chsh -s /usr/bin/zsh "$ACTUAL_USER"

    # Install Oh My Zsh for user
    if [ ! -d "$USER_HOME/.oh-my-zsh" ]; then
        su - "$ACTUAL_USER" -c '
            export RUNZSH=no
            export CHSH=no
            export KEEP_ZSHRC=yes
            sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" || \
            sh -c "$(wget -qO- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
        ' || {
            git clone https://github.com/ohmyzsh/ohmyzsh.git "$USER_HOME/.oh-my-zsh"
            cp "$USER_HOME/.oh-my-zsh/templates/zshrc.zsh-template" "$USER_HOME/.zshrc"
        }
    fi

    # Configure .zshrc
    if [ -f "$USER_HOME/.zshrc" ]; then
        cp "$USER_HOME/.zshrc" "$USER_HOME/.zshrc.backup" 2>/dev/null || true

        # Set theme
        sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="agnoster"/' "$USER_HOME/.zshrc"

        # Set plugins
        sed -i 's/plugins=(git)/plugins=(git docker python pip nmap ssh-agent sudo tmux colored-man-pages command-not-found extract z)/' "$USER_HOME/.zshrc"

        # Add aliases and functions (continued in next part due to length)
        cat >> "$USER_HOME/.zshrc" << 'ZSHEOF'

# ==================== Security Tools Configuration ====================
# Added by Ubuntu Security Tools Installation Script

# PATH Configuration - Order matters!
export PATH="$HOME/.local/bin:/opt/security-tools-venv/bin:/snap/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

# Add Rust to PATH if installed
[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"

# ==================== Security Tool Aliases ====================

# Nmap shortcuts
alias nse='ls /usr/share/nmap/scripts/ | grep'
alias nmap-vuln='nmap --script vuln'
alias nmap-full='nmap -sV -sC -O -p-'
alias nmap-quick='nmap -F'

# SMB shortcuts
alias smbmap='smbclient -L'
alias enum4linux='enum4linux -a'

# Hashcat shortcuts
alias hashcat64='hashcat'
alias hashcat-ntlm='hashcat -m 1000'
alias hashcat-md5='hashcat -m 0'

# Web server aliases
alias serve='python3 -m http.server'
alias serve80='sudo python3 -m http.server 80'
alias serve443='sudo python3 -m http.server 443'
alias pyserve='python3 -m http.server'
alias phpserve='php -S 0.0.0.0:8000'

# Network aliases
alias ports='netstat -tulanp'
alias listening='netstat -tlnp'
alias myip='curl -s ifconfig.me'
alias localip='ip addr show | grep "inet " | grep -v 127.0.0.1'
alias netinfo='ifconfig -a'

# Security environment activation
alias activate-security='source /opt/security-tools-venv/bin/activate'
alias sec-env='source /opt/security-tools-venv/bin/activate'
alias venv='source /opt/security-tools-venv/bin/activate'

# Proxychains aliases
alias pchains='proxychains4'
alias pc='proxychains4'
alias pcnmap='proxychains4 nmap'

# Impacket shortcuts
alias secretsdump='secretsdump.py'
alias psexec='psexec.py'
alias smbexec='smbexec.py'
alias wmiexec='wmiexec.py'
alias GetNPUsers='GetNPUsers.py'
alias GetUserSPNs='GetUserSPNs.py'

# NetExec shortcuts
alias nxc='netexec'
alias nxc-smb='netexec smb'
alias nxc-shares='netexec smb --shares'

# Responder shortcuts
alias responder-analyze='responder -I eth0 -A'
alias responder-wpad='responder -I eth0 -wFb'

# Git shortcuts
alias gs='git status'
alias ga='git add'
alias gc='git commit -m'
alias gp='git push'
alias gl='git log --oneline'

# ==================== Useful Functions ====================

# Extract function - handles multiple archive types
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

# Quick hex encode/decode
hex() { echo -n "$1" | xxd -p; }
unhex() { echo -n "$1" | xxd -r -p; }

# Generate random password
genpass() {
    local length=${1:-16}
    tr -dc 'A-Za-z0-9!@#$%^&*' < /dev/urandom | head -c "$length"; echo
}

# Quick nmap scan
quickscan() {
    if [ -z "$1" ]; then
        echo "Usage: quickscan <target>"
        return 1
    fi
    nmap -sV -sC -T4 "$1"
}

# Full nmap scan
fullscan() {
    if [ -z "$1" ]; then
        echo "Usage: fullscan <target>"
        return 1
    fi
    nmap -sV -sC -O -p- -T4 "$1"
}

# SMB enumeration
smbenum() {
    if [ -z "$1" ]; then
        echo "Usage: smbenum <target>"
        return 1
    fi
    echo "Running SMB enumeration on $1..."
    netexec smb "$1" --shares 2>/dev/null || smbclient -L "$1" -N
}

# Tool availability checker
check-tool() {
    if command -v "$1" &> /dev/null; then
        echo "✓ $1 is installed: $(command -v $1)"
        $1 --version 2>/dev/null || echo "  (version info not available)"
    else
        echo "✗ $1 is not installed or not in PATH"
    fi
}

# Check all security tools
check-all-tools() {
    echo "Checking security tools installation..."
    local tools=("nmap" "netexec" "nxc" "secretsdump.py" "responder" "hashcat" "certipy" "proxychains4" "smbclient")
    for tool in "${tools[@]}"; do
        check-tool "$tool"
    done
}

# ==================== Environment Variables ====================

export EDITOR=vim
export VISUAL=vim
export HISTSIZE=10000
export SAVEHIST=10000
export HISTFILE=~/.zsh_history

# ==================== Completion ====================

setopt COMPLETE_ALIASES

# ==================== Welcome Message ====================

if [[ $- == *i* ]]; then
    echo "🔒 Security Tools Environment Loaded"
    echo "💡 Tip: Run 'check-all-tools' to verify installations"
    echo "📚 Run 'sec-env' or 'activate-security' to activate Python tools venv"
fi

ZSHEOF

        chown "$ACTUAL_USER:$(id -gn $ACTUAL_USER)" "$USER_HOME/.zshrc"
    fi

    # Install Oh My Zsh for root as well
    if [ ! -d "/root/.oh-my-zsh" ]; then
        export RUNZSH=no CHSH=no KEEP_ZSHRC=yes
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" 2>/dev/null || \
        git clone https://github.com/ohmyzsh/ohmyzsh.git /root/.oh-my-zsh
    fi

    print_status "✓ Zsh configuration complete"
}

fix_permissions() {
    print_section "Fixing Permissions"

    # Fix home directory
    for dir in .local .cargo .config .oh-my-zsh .ssh; do
        if [ -d "$USER_HOME/$dir" ]; then
            chown -R "$ACTUAL_USER:$(id -gn $ACTUAL_USER)" "$USER_HOME/$dir"
        fi
    done

    # Fix .zshrc
    [ -f "$USER_HOME/.zshrc" ] && chown "$ACTUAL_USER:$(id -gn $ACTUAL_USER)" "$USER_HOME/.zshrc"

    # Fix venv
    if [ -d "$SECURITY_VENV" ]; then
        chown -R "$ACTUAL_USER:$(id -gn $ACTUAL_USER)" "$SECURITY_VENV"
        chmod -R u+rwX,go+rX "$SECURITY_VENV"
        chmod +x "$SECURITY_VENV/bin/"* 2>/dev/null || true
    fi

    # Fix wrapper scripts
    chmod 755 /usr/local/bin/responder /usr/local/bin/certipy-venv 2>/dev/null || true

    # Add user to groups
    usermod -aG sudo "$ACTUAL_USER" 2>/dev/null || true
    usermod -aG adm "$ACTUAL_USER" 2>/dev/null || true

    print_status "✓ Permissions fixed"
}

verify_installation() {
    print_section "Verifying Installation"

    local tools_ok=0
    local tools_fail=0

    # Check system tools
    for tool in nmap ncat smbclient hashcat proxychains4 i3 polybar kitty zsh; do
        if command -v "$tool" &>/dev/null; then
            ((tools_ok++))
        else
            print_warning "✗ $tool not found"
            ((tools_fail++))
        fi
    done

    # Check pipx tools
    if su - "$ACTUAL_USER" -c "command -v netexec" &>/dev/null; then
        ((tools_ok++))
    else
        print_warning "✗ netexec not found"
        ((tools_fail++))
    fi

    # Check venv
    if [ -d "$SECURITY_VENV" ]; then
        ((tools_ok++))
    else
        print_warning "✗ Virtual environment not found"
        ((tools_fail++))
    fi

    echo ""
    print_status "✓ Tools installed: $tools_ok"
    if [ $tools_fail -gt 0 ]; then
        print_warning "✗ Tools missing: $tools_fail"
    fi
}

################################################################################
# Main Execution
################################################################################

main() {
    print_section "Ubuntu Security Tools Installation v$SCRIPT_VERSION"

    # Pre-flight checks
    check_root
    check_sudo_user
    get_user_info
    check_internet
    check_disk_space

    print_status "Installing for user: $ACTUAL_USER"
    print_status "User home: $USER_HOME"
    print_status "Log file: $LOG_FILE"

    # Execute installations
    install_system_packages
    install_snapd
    install_polybar
    install_obsidian
    setup_rust
    install_pipx_tools
    setup_python_venv
    create_wrapper_scripts

    # Configure GUI and shell environment
    configure_i3_polybar_kitty
    configure_zsh

    # Final setup
    fix_permissions
    verify_installation

    print_section "Installation Complete!"
    print_status "Please restart your terminal for changes to take effect"
    print_status "Run 'source ~/.zshrc' to load new shell configuration"
    print_status "Run 'check-all-tools' to verify tool installations"
}

# Run main function
main "$@"
