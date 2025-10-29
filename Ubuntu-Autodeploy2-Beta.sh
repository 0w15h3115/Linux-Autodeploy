#!/bin/bash

# Ubuntu Security Tools Installation Script
# This script installs various security analysis tools on Ubuntu
# Tools: nmap, ncat, ping, binwalk, impacket, obsidian, smbclient,
#        netexec, certipy, dnstool, i3, hashcat, java, zsh + oh-my-zsh,
#        kitty, polybar, proxychains, net-tools, responder

set -e  # Exit on error
set -o pipefail  # Catch errors in pipes

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Installation log
LOG_FILE="/var/log/security-tools-install.log"
touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/security-tools-install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo -e "${BLUE}[INFO]${NC} Logging installation to $LOG_FILE"
echo -e "${BLUE}[INFO]${NC} Installation started at $(date)"

# Function to print colored output
print_status() {
    echo -e "${GREEN}[+]${NC} $1"
}

print_error() {
    echo -e "${RED}[!]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[*]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

# Verify SUDO_USER is set
if [ -z "$SUDO_USER" ] || [ "$SUDO_USER" = "root" ]; then
    print_error "This script must be run with sudo, not as root user directly"
    print_error "Usage: sudo ./$(basename $0)"
    exit 1
fi

# Get user information
ACTUAL_USER="$SUDO_USER"
USER_HOME=$(getent passwd "$ACTUAL_USER" | cut -d: -f6)
USER_UID=$(id -u "$ACTUAL_USER")
USER_GID=$(id -g "$ACTUAL_USER")

print_status "Starting security tools installation..."
print_status "Installing for user: $ACTUAL_USER"
print_status "User home directory: $USER_HOME"

# Pre-flight checks
print_status "Running pre-flight checks..."

# Check internet connectivity
if ! ping -c 1 8.8.8.8 &> /dev/null; then
    print_error "No internet connectivity detected"
    exit 1
fi

# Check disk space (need at least 5GB free)
AVAILABLE_SPACE=$(df / | tail -1 | awk '{print $4}')
if [ "$AVAILABLE_SPACE" -lt 5000000 ]; then
    print_warning "Less than 5GB disk space available. Installation may fail."
fi

print_status "Pre-flight checks passed"

# Function to run apt commands with retry logic and rate limiting
apt_with_retry() {
    local max_attempts=5
    local attempt=1
    local wait_time=30
    local command="$@"

    while [ $attempt -le $max_attempts ]; do
        print_status "Running: apt $command (Attempt $attempt/$max_attempts)"

        if apt $command; then
            print_status "APT command succeeded"
            return 0
        else
            if [ $attempt -lt $max_attempts ]; then
                print_warning "APT command failed. Waiting ${wait_time}s before retry $((attempt + 1))..."
                sleep $wait_time
                # Exponential backoff - double the wait time for next attempt
                wait_time=$((wait_time * 2))
                attempt=$((attempt + 1))
            else
                print_error "APT command failed after $max_attempts attempts"
                return 1
            fi
        fi
    done
}

# Configure APT to use multiple retries and timeout settings
print_status "Configuring APT for better reliability..."
cat > /etc/apt/apt.conf.d/99retry << 'EOF'
Acquire::Retries "5";
Acquire::http::Timeout "120";
Acquire::https::Timeout "120";
Acquire::ftp::Timeout "120";
Acquire::Queue-Mode "host";
Acquire::http::Pipeline-Depth "0";
EOF

# Optional: Try to use a mirror selector if available
if command -v netselect-apt &> /dev/null; then
    print_status "Using netselect-apt to find fastest mirror..."
    netselect-apt -n -o /etc/apt/sources.list.netselect || print_warning "Mirror selection failed, continuing with default mirrors"
fi

# Add a small delay to avoid immediate rate limiting
print_status "Adding initial delay to avoid rate limiting..."
sleep 10

# Update system with retry logic
print_status "Updating package lists (with retry logic)..."
apt_with_retry update

print_status "Upgrading existing packages (with retry logic)..."
apt_with_retry upgrade -y

# Install essential build tools and dependencies
print_status "Installing essential dependencies (this may take several attempts due to rate limiting)..."

# Add delay before large install to avoid rate limiting
sleep 5

apt_with_retry "install -y \
    build-essential \
    python3 \
    python3-pip \
    python3-venv \
    pipx \
    git \
    curl \
    wget \
    libssl-dev \
    libffi-dev \
    python3-dev \
    python3-setuptools \
    libpcap-dev \
    libgmp3-dev \
    libxml2-dev \
    libxslt1-dev \
    zlib1g-dev \
    ocl-icd-libopencl1 \
    opencl-headers \
    clinfo \
    fonts-powerline \
    fonts-font-awesome \
    tmux \
    ncat \
    nmap \
    iputils-ping \
    binwalk \
    smbclient \
    dnsutils \
    default-jre \
    openjdk-8-jre \
    dnsrecon \
    python3-ldapdomaindump \
    adcli \
    nbtscan \
    python3-certipy \
    proxychains4 \
    net-tools"

# Add a delay after large install
print_status "Package installation complete, adding cooldown period..."
sleep 10

# 12. Install Python-based tools
print_status "Setting up Python environment for security tools..."

# Create symbolic links for Python tools if needed
print_status "Creating symbolic links for Python tools..."

# Determine the correct user and paths
if [ -n "$SUDO_USER" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    USER_LOCAL_BIN="$USER_HOME/.local/bin"
else
    USER_LOCAL_BIN="$HOME/.local/bin"
fi

# Check if pipx tools were installed and create system-wide symlinks
if [ -d "$USER_LOCAL_BIN" ]; then
    print_status "Found pipx installation directory: $USER_LOCAL_BIN"
    
    # Create symlinks for commonly used tools
    for tool in netexec nxc nxcdb; do
        if [ -f "$USER_LOCAL_BIN/$tool" ]; then
            ln -sf "$USER_LOCAL_BIN/$tool" /usr/local/bin/
            print_status "Created system-wide symlink for $tool"
        fi
    done
    
    # Create symlinks for impacket tools
    for script in $(find "$USER_LOCAL_BIN" -name "*impacket*" -o -name "Get*" -o -name "psexec*" -o -name "smbexec*" -o -name "wmiexec*" -o -name "secretsdump*" -o -name "ntlmrelayx*" -o -name "smbserver*" -o -name "ticketer*" -o -name "mimikatz*" -o -name "goldenPac*" -o -name "lookupsid*" -o -name "rpcdump*" -o -name "samrdump*" -o -name "reg*" -o -name "atexec*" -o -name "dcomexec*" 2>/dev/null); do
        if [ -f "$script" ] && [ -x "$script" ]; then
            script_name=$(basename "$script")
            if [ ! -f "/usr/local/bin/$script_name" ]; then
                ln -sf "$script" /usr/local/bin/
                print_status "Created system-wide symlink for $script_name"
            fi
        fi
    done
else
    print_warning "Could not locate pipx installation directory"
fi

# Install pipx tools as the actual user (not root)
if [ -n "$SUDO_USER" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    
    # Install Rust for the user first (required for NetExec)
    print_status "Installing Rust for user $SUDO_USER (required for NetExec)..."
    su - "$SUDO_USER" -c "
        if ! command -v rustc &> /dev/null; then
            curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
            source ~/.cargo/env
        fi
    " || print_warning "Failed to install Rust for user"
    
    # Ensure pipx is available for the user
    print_status "Setting up pipx for user $SUDO_USER..."
    su - "$SUDO_USER" -c "
        python3 -m pip install --user pipx
        python3 -m pipx ensurepath
    " 2>/dev/null || print_warning "Failed to setup pipx for user"
    
    # Install impacket via pipx as user
    print_status "Installing impacket via pipx for user $SUDO_USER..."
    su - "$SUDO_USER" -c "
        source ~/.cargo/env 2>/dev/null || true
        python3 -m pipx install impacket
    " || print_warning "Failed to install impacket via pipx"
    
    # Install netexec via pipx as user
    print_status "Installing netexec via pipx for user $SUDO_USER..."
    su - "$SUDO_USER" -c "
        source ~/.cargo/env 2>/dev/null || true
        python3 -m pipx install git+https://github.com/Pennyw0rth/NetExec
    " || {
        print_warning "Failed to install netexec from GitHub for user $SUDO_USER"
        print_warning "This may be due to missing dependencies or Rust installation issues"
    }
    
    print_status "Pipx installations completed for user $SUDO_USER"
else
    print_warning "No SUDO_USER detected, installing pipx tools as root (may not be accessible to regular users)"
    
    # Fallback: install as root if no sudo user detected
    if ! command -v rustc &> /dev/null; then
        print_warning "Rust not found, installing Rust (required for NetExec)..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env" 2>/dev/null || true
    fi
    
    pipx install impacket || print_warning "Failed to install impacket via pipx"
    pipx install git+https://github.com/Pennyw0rth/NetExec || print_warning "Failed to install netexec via pipx"
fi

# Create dedicated Python environment for additional security tools
print_status "Creating dedicated Python environment for advanced security tools..."
SECURITY_VENV="/opt/security-tools-venv"

# Remove old venv if exists to ensure clean install
if [ -d "$SECURITY_VENV" ]; then
    print_warning "Removing existing virtual environment..."
    rm -rf "$SECURITY_VENV"
fi

python3 -m venv "$SECURITY_VENV" --system-site-packages

# Set proper ownership for the virtual environment
chown -R "$ACTUAL_USER:$(id -gn $ACTUAL_USER)" "$SECURITY_VENV"
print_status "Set ownership of virtual environment to $ACTUAL_USER"

# Activate the virtual environment for the rest of the installations
source "$SECURITY_VENV/bin/activate"

# Upgrade pip in the virtual environment
print_status "Upgrading pip in security tools environment..."
pip install --upgrade pip setuptools wheel

# Verify activation
if [ -z "$VIRTUAL_ENV" ]; then
    print_error "Failed to activate virtual environment"
    exit 1
fi
print_status "Virtual environment activated: $VIRTUAL_ENV"

# Install Python packages in the virtual environment with proper error handling
print_status "Installing Python packages in security environment..."

# Install packages one by one with verification
PYTHON_PACKAGES=(
    "netifaces"
    "aioquic"
    "cryptography"
    "pyasn1"
    "ldap3"
    "ldapdomaindump"
    "flask"
    "pyOpenSSL"
    "pycryptodome"
)

for package in "${PYTHON_PACKAGES[@]}"; do
    print_status "Installing $package..."
    if pip install "$package"; then
        print_status "✓ $package installed successfully"
    else
        print_warning "Failed to install $package, continuing..."
    fi
done

# Try to install pyrebase4 but don't fail if it doesn't work
print_status "Attempting to install pyrebase4 (optional)..."
pip install pyrebase4 || {
    print_warning "Failed to install pyrebase4, continuing without it..."
}

# Install impacket from source (for latest features)
print_status "Installing impacket from source in security environment..."
cd /tmp
if [ -d "impacket" ]; then
    rm -rf impacket
fi

if git clone https://github.com/fortra/impacket.git; then
    cd impacket
    if pip install .; then
        print_status "✓ Impacket installed from source successfully"
        # Verify impacket installation
        python3 -c "import impacket; print(f'Impacket version: {impacket.version.BANNER}')" || print_warning "Impacket import failed"
    else
        print_warning "Failed to install impacket"
    fi
    cd /tmp
else
    print_warning "Failed to clone impacket repository"
fi

# Install responder from source
print_status "Installing Responder from source..."
cd /tmp
if [ -d "Responder" ]; then
    rm -rf Responder
fi

if git clone https://github.com/lgandx/Responder.git; then
    cd Responder
    if pip install -r requirements.txt; then
        # Install responder to the virtual environment
        mkdir -p "$SECURITY_VENV/responder"
        cp -r . "$SECURITY_VENV/responder/"
        chmod +x "$SECURITY_VENV/responder/Responder.py"
        # Set ownership
        chown -R "$ACTUAL_USER:$(id -gn $ACTUAL_USER)" "$SECURITY_VENV/responder"
        print_status "✓ Responder installed from source successfully"

        # Verify responder
        if [ -f "$SECURITY_VENV/responder/Responder.py" ]; then
            python3 "$SECURITY_VENV/responder/Responder.py" --version 2>/dev/null || print_status "Responder ready"
        fi
    else
        print_warning "Failed to install Responder dependencies"
    fi
    cd /tmp
else
    print_warning "Failed to clone Responder repository"
fi

# Install certipy in the virtual environment (in addition to apt version)
print_status "Installing certipy-ad in security environment..."
if pip install certipy-ad; then
    print_status "✓ certipy-ad installed successfully"
    # Verify certipy installation
    certipy -h >/dev/null 2>&1 && print_status "certipy command verified" || print_warning "certipy command not found in venv"
else
    print_warning "Failed to install certipy-ad"
fi

# Deactivate virtual environment
deactivate
print_status "Virtual environment deactivated"

# Create wrapper scripts for virtual environment tools
print_status "Creating wrapper scripts for security tools..."
mkdir -p /usr/local/bin

# Create impacket wrapper scripts for venv version
for script in $(find "$SECURITY_VENV/bin" -name "*impacket*" -o -name "Get*" -o -name "add*" -o -name "atexec*" -o -name "dcom*" -o -name "dpapi*" -o -name "find*" -o -name "get*" -o -name "golden*" -o -name "karmaSMB*" -o -name "kint*" -o -name "lookupsid*" -o -name "mimikatz*" -o -name "mqtt*" -o -name "mssql*" -o -name "net*" -o -name "nmb*" -o -name "ntfs*" -o -name "ntlm*" -o -name "ping*" -o -name "psexec*" -o -name "raiseChild*" -o -name "rdp*" -o -name "reg*" -o -name "rpcdump*" -o -name "rpc*" -o -name "sambaPipe*" -o -name "samr*" -o -name "secret*" -o -name "service*" -o -name "smbclient*" -o -name "smbexec*" -o -name "smbpasswd*" -o -name "smbserver*" -o -name "sniff*" -o -name "split*" -o -name "ticketer*" -o -name "tick*" -o -name "wmi*" 2>/dev/null); do
    if [ -f "$script" ] && [ -x "$script" ]; then
        script_name=$(basename "$script")
        # Create venv version with -venv suffix to avoid conflicts
        cat > "/usr/local/bin/$script_name-venv" << EOF
#!/bin/bash
source "$SECURITY_VENV/bin/activate"
exec "$script" "\$@"
EOF
        chmod +x "/usr/local/bin/$script_name-venv"
    fi
done

# Create responder wrapper
cat > "/usr/local/bin/responder" << EOF
#!/bin/bash
source "$SECURITY_VENV/bin/activate"
cd "$SECURITY_VENV/responder"
exec python3 Responder.py "\$@"
EOF
chmod +x "/usr/local/bin/responder"

# Create certipy wrapper (for the venv version)
cat > "/usr/local/bin/certipy-venv" << EOF
#!/bin/bash
source "$SECURITY_VENV/bin/activate"
exec certipy "\$@"
EOF
chmod +x "/usr/local/bin/certipy-venv"

# 6. Install hashcat
print_status "Installing hashcat..."
sleep 3
apt_with_retry "install -y hashcat" || {
    print_warning "Hashcat not found in repositories, installing from source..."
    # Install hashcat from source as fallback
    cd /tmp
    git clone https://github.com/hashcat/hashcat.git
    cd hashcat
    make
    make install
    cd ..
    rm -rf hashcat
}

# 7. Install DNS enumeration tools
print_status "Installing DNS enumeration tools..."
# Install dnsrecon via pip
python3 -m pip install dnsrecon || print_warning "Failed to install dnsrecon"

# Install dnsenum manually
print_status "Installing dnsenum..."
cd /tmp
git clone https://github.com/fwaeytens/dnsenum.git || print_warning "Failed to clone dnsenum"
if [ -d "dnsenum" ]; then
    cd dnsenum
    chmod +x dnsenum.pl
    cp dnsenum.pl /usr/local/bin/dnsenum
    cd ..
    rm -rf dnsenum
fi

# 8. Install i3 window manager
print_status "Installing i3 window manager..."
sleep 3
apt_with_retry "install -y i3 i3status i3lock xss-lock dmenu"

# 9. Install polybar
print_status "Installing polybar..."
sleep 3
apt_with_retry "install -y polybar"

# Create basic polybar config
print_status "Configuring polybar..."
if [ -n "$SUDO_USER" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    POLYBAR_CONFIG_DIR="$USER_HOME/.config/polybar"
    mkdir -p "$POLYBAR_CONFIG_DIR"
    
    # Create launch script
    cat > "$POLYBAR_CONFIG_DIR/launch.sh" << 'EOF'
#!/bin/bash

# Terminate already running bar instances
killall -q polybar

# Wait until the processes have been shut down
while pgrep -u $UID -x polybar >/dev/null; do sleep 1; done

# Launch polybar
polybar main &

echo "Polybar launched..."
EOF
    chmod +x "$POLYBAR_CONFIG_DIR/launch.sh"
    
    # Create basic polybar config
    cat > "$POLYBAR_CONFIG_DIR/config.ini" << 'EOF'
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
    
    # Update i3 config to use polybar instead of i3status
    USER_I3_CONFIG="$USER_HOME/.config/i3/config"
    if [ -f "$USER_I3_CONFIG" ]; then
        # Comment out i3bar section
        sed -i '/^bar {/,/^}/ s/^/#/' "$USER_I3_CONFIG"
        
        # Add polybar launch command
        if ! grep -q "polybar/launch.sh" "$USER_I3_CONFIG"; then
            echo ""
echo "=== Troubleshooting ==="
echo "If tools are not found after restarting terminal:"
echo "1. Check pipx installations: pipx list"
echo "2. Check PATH: echo \$PATH | grep -E 'local|snap|opt'"
echo "3. Manual PATH fix: source ~/.zshrc"
echo "4. Check tool locations:"
echo "   ls -la ~/.local/bin/"
echo "   ls -la /snap/bin/"
echo "   ls -la /opt/security-tools-venv/bin/"
echo "5. If still broken, reinstall as user:"
echo "   pipx install git+https://github.com/Pennyw0rth/NetExec"
echo "   pipx install impacket"
echo "6. For snap apps: snap list" >> "$USER_I3_CONFIG"
            echo "# Launch polybar" >> "$USER_I3_CONFIG"
            echo "exec_always --no-startup-id \$HOME/.config/polybar/launch.sh" >> "$USER_I3_CONFIG"
        fi
    else
        # If i3 config doesn't exist yet, make sure it will launch polybar when created
        mkdir -p "$USER_HOME/.config/i3"
        echo "# Launch polybar" > "$USER_HOME/.config/i3/polybar-autostart"
        echo "exec_always --no-startup-id \$HOME/.config/polybar/launch.sh" >> "$USER_HOME/.config/i3/polybar-autostart"
        chown -R "$SUDO_USER:$SUDO_USER" "$USER_HOME/.config/i3"
    fi
    
    chown -R "$SUDO_USER:$SUDO_USER" "$POLYBAR_CONFIG_DIR"
fi

# 10. Install zsh and make it default shell
print_status "Installing zsh..."
sleep 3
apt_with_retry "install -y zsh"

# Set zsh as default shell for root and current sudo user
print_status "Setting zsh as default shell..."
chsh -s /usr/bin/zsh
if [ -n "$SUDO_USER" ]; then
    chsh -s /usr/bin/zsh "$SUDO_USER"
    print_status "Set zsh as default shell for $SUDO_USER"
fi

# Install Oh My Zsh
print_status "Installing Oh My Zsh..."
# Function to install Oh My Zsh for a specific user
install_oh_my_zsh() {
    local USER_NAME=$1
    local USER_HOME=$2
    
    if [ -d "$USER_HOME/.oh-my-zsh" ]; then
        print_warning "Oh My Zsh already installed for $USER_NAME"
        return
    fi
    
    # Download and install Oh My Zsh non-interactively
    su - "$USER_NAME" -c "
        export RUNZSH=no
        export CHSH=no
        export KEEP_ZSHRC=yes
        sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\" || \
        sh -c \"\$(wget -qO- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\"
    " || {
        print_warning "Failed to install Oh My Zsh for $USER_NAME, trying alternative method..."
        # Alternative method: clone directly
        git clone https://github.com/ohmyzsh/ohmyzsh.git "$USER_HOME/.oh-my-zsh"
        cp "$USER_HOME/.oh-my-zsh/templates/zshrc.zsh-template" "$USER_HOME/.zshrc"
        chown -R "$USER_NAME:$USER_NAME" "$USER_HOME/.oh-my-zsh" "$USER_HOME/.zshrc"
    }
    
    # Configure .zshrc with useful plugins and theme
    if [ -f "$USER_HOME/.zshrc" ]; then
        # Backup original
        cp "$USER_HOME/.zshrc" "$USER_HOME/.zshrc.backup"
        
        # Set theme to agnoster (good for security work)
        sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="agnoster"/' "$USER_HOME/.zshrc"
        
        # Enable useful plugins for security work
        sed -i 's/plugins=(git)/plugins=(git docker python pip nmap ssh-agent sudo tmux colored-man-pages command-not-found extract z)/' "$USER_HOME/.zshrc"
        
        # Add custom aliases for security tools
        cat >> "$USER_HOME/.zshrc" << 'EOF'

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
alias updog='updog'  # Alternative web server

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

# Impacket shortcuts (if installed via pipx or venv)
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

# Git shortcuts for operations
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

# Set default editor
export EDITOR=vim
export VISUAL=vim

# History settings
export HISTSIZE=10000
export SAVEHIST=10000
export HISTFILE=~/.zsh_history

# ==================== Completion ====================

# Enable command completion for aliases
setopt COMPLETE_ALIASES

# ==================== Welcome Message ====================

# Display security tools welcome message (only on interactive shells)
if [[ $- == *i* ]]; then
    echo "🔒 Security Tools Environment Loaded"
    echo "💡 Tip: Run 'check-all-tools' to verify installations"
    echo "📚 Run 'sec-env' or 'activate-security' to activate Python tools venv"
fi

EOF
        
        chown "$USER_NAME:$USER_NAME" "$USER_HOME/.zshrc"
    fi
}

# Install for root
install_oh_my_zsh "root" "/root"

# Install for sudo user
if [ -n "$SUDO_USER" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    install_oh_my_zsh "$SUDO_USER" "$USER_HOME"
fi

# 11. Install kitty terminal
print_status "Installing kitty terminal..."
sleep 3
apt_with_retry "install -y kitty"

# Configure kitty as default terminal for i3
print_status "Configuring kitty as default terminal for i3..."
# Create i3 config directory if it doesn't exist
I3_CONFIG_DIR="/etc/i3"
if [ -d "$I3_CONFIG_DIR" ]; then
    # Backup original config
    cp "$I3_CONFIG_DIR/config" "$I3_CONFIG_DIR/config.backup" 2>/dev/null || true
    
    # Update terminal binding in system-wide i3 config
    sed -i 's/bindsym \$mod+Return exec i3-sensible-terminal/bindsym \$mod+Return exec kitty/' "$I3_CONFIG_DIR/config" 2>/dev/null || true
    sed -i 's/bindsym \$mod+Return exec terminal/bindsym \$mod+Return exec kitty/' "$I3_CONFIG_DIR/config" 2>/dev/null || true
fi

# Also create user config template
if [ -n "$SUDO_USER" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    USER_I3_DIR="$USER_HOME/.config/i3"
    mkdir -p "$USER_I3_DIR"
    chown "$SUDO_USER:$SUDO_USER" "$USER_I3_DIR"
    
    # Create a basic i3 config with kitty as default if it doesn't exist
    if [ ! -f "$USER_I3_DIR/config" ]; then
        cat > "$USER_I3_DIR/config" << 'EOF'
# i3 config file (v4)
# Set mod key (Mod1=Alt, Mod4=Windows key)
set $mod Mod4

# Font for window titles
font pango:monospace 8

# Start kitty terminal
bindsym $mod+Return exec kitty

# Kill focused window
bindsym $mod+Shift+q kill

# Start dmenu
bindsym $mod+d exec dmenu_run

# Launch polybar
exec_always --no-startup-id $HOME/.config/polybar/launch.sh

# Copy remaining config from system default
EOF
        # Append the rest of the default config, skipping the terminal binding and i3bar
        if [ -f "$I3_CONFIG_DIR/config" ]; then
            grep -v "bindsym \$mod+Return" "$I3_CONFIG_DIR/config" | \
            grep -v "^#.*config file" | \
            grep -v "^set \$mod" | \
            grep -v "^font pango" | \
            grep -v "bindsym \$mod+d exec dmenu" | \
            grep -v "bindsym \$mod+Shift+q kill" | \
            sed '/^bar {/,/^}/ d' >> "$USER_I3_DIR/config"
        fi
        chown "$SUDO_USER:$SUDO_USER" "$USER_I3_DIR/config"
    fi
fi

# Set kitty as the default x-terminal-emulator alternative
update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/bin/kitty 50
update-alternatives --set x-terminal-emulator /usr/bin/kitty

# Create basic kitty config for better defaults
if [ -n "$SUDO_USER" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    KITTY_CONFIG_DIR="$USER_HOME/.config/kitty"
    mkdir -p "$KITTY_CONFIG_DIR"
    
    if [ ! -f "$KITTY_CONFIG_DIR/kitty.conf" ]; then
        cat > "$KITTY_CONFIG_DIR/kitty.conf" << 'EOF'
# Kitty Configuration
# Font configuration
font_family      monospace
font_size        11.0

# Shell integration
shell /usr/bin/zsh
shell_integration enabled

# Terminal bell
enable_audio_bell no

# Theme
background_opacity 0.95
background #1e1e1e

# Scrollback
scrollback_lines 10000

# URL handling
open_url_with default
detect_urls yes

# Performance
repaint_delay 10
input_delay 3
sync_to_monitor yes
EOF
        chown -R "$SUDO_USER:$SUDO_USER" "$KITTY_CONFIG_DIR"
    fi
fi

# 13. Install Obsidian
print_status "Installing Obsidian..."
# Check if snap is installed, if not install it
if ! command -v snap &> /dev/null; then
    print_warning "Snap not found, installing..."
    sleep 3
    apt_with_retry "install -y snapd"
    systemctl enable --now snapd.socket
    # Create symlink for classic snap support
    ln -s /var/lib/snapd/snap /snap 2>/dev/null || true
    # Wait for snap to initialize
    sleep 5
fi

# Install Obsidian via snap
snap install obsidian --classic

# Add Python scripts to PATH
print_status "Configuring PATH..."

# Create profile.d script to ensure Python scripts are in PATH
cat > /etc/profile.d/security-tools.sh << 'EOF'
# Security Tools PATH Configuration

# Ensure standard system directories are in PATH
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

# Add snap bin directory to PATH
if [ -d "/snap/bin" ]; then
    export PATH="/snap/bin:$PATH"
fi

# Add user's local bin to PATH (where pipx installs tools)
if [ -d "$HOME/.local/bin" ]; then
    export PATH="$HOME/.local/bin:$PATH"
fi

# Add security tools virtual environment to PATH
if [ -d "/opt/security-tools-venv/bin" ]; then
    export PATH="/opt/security-tools-venv/bin:$PATH"
fi
EOF

chmod +x /etc/profile.d/security-tools.sh

# Also add to the user's zshrc for immediate availability
if [ -n "$SUDO_USER" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    if [ -f "$USER_HOME/.zshrc" ]; then
        # Check if our PATH exports are already in zshrc, if not add them
        if ! grep -q "# Security Tools PATH" "$USER_HOME/.zshrc"; then
            cat >> "$USER_HOME/.zshrc" << 'EOF'

# Security Tools PATH (added by installation script)
# Ensure standard system directories are in PATH
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
# Add snap bin directory to PATH
export PATH="/snap/bin:$PATH"
# Add user's local bin to PATH (where pipx installs tools)
export PATH="$HOME/.local/bin:$PATH"
# Add security tools virtual environment to PATH
export PATH="/opt/security-tools-venv/bin:$PATH"
EOF
            chown "$SUDO_USER:$SUDO_USER" "$USER_HOME/.zshrc"
            print_status "Added security tools PATH to $SUDO_USER's .zshrc"
        fi
    fi
fi

# Ensure pipx path is in PATH for the user
if [ -n "$SUDO_USER" ]; then
    su - "$SUDO_USER" -c "python3 -m pipx ensurepath" || print_warning "Failed to run pipx ensurepath for user"
else
    pipx ensurepath
fi

# ==================== Fix Permissions ====================
print_status "Fixing permissions for all installed tools..."

# Fix ownership of user home directory files (prevent root-owned files)
if [ -n "$ACTUAL_USER" ] && [ -d "$USER_HOME" ]; then
    print_status "Fixing ownership of $USER_HOME..."

    # Fix .local directory
    if [ -d "$USER_HOME/.local" ]; then
        chown -R "$ACTUAL_USER:$(id -gn $ACTUAL_USER)" "$USER_HOME/.local"
        print_status "✓ Fixed .local directory ownership"
    fi

    # Fix .cargo directory (Rust)
    if [ -d "$USER_HOME/.cargo" ]; then
        chown -R "$ACTUAL_USER:$(id -gn $ACTUAL_USER)" "$USER_HOME/.cargo"
        print_status "✓ Fixed .cargo directory ownership"
    fi

    # Fix .zshrc
    if [ -f "$USER_HOME/.zshrc" ]; then
        chown "$ACTUAL_USER:$(id -gn $ACTUAL_USER)" "$USER_HOME/.zshrc"
        chmod 644 "$USER_HOME/.zshrc"
        print_status "✓ Fixed .zshrc ownership"
    fi

    # Fix config directories
    for config_dir in .config .oh-my-zsh .ssh; do
        if [ -d "$USER_HOME/$config_dir" ]; then
            chown -R "$ACTUAL_USER:$(id -gn $ACTUAL_USER)" "$USER_HOME/$config_dir"
            print_status "✓ Fixed $config_dir ownership"
        fi
    done
fi

# Fix virtual environment permissions
if [ -d "$SECURITY_VENV" ]; then
    print_status "Fixing virtual environment permissions..."
    chown -R "$ACTUAL_USER:$(id -gn $ACTUAL_USER)" "$SECURITY_VENV"
    chmod -R u+rwX,go+rX "$SECURITY_VENV"
    chmod +x "$SECURITY_VENV/bin/"*
    print_status "✓ Fixed virtual environment permissions"
fi

# Make wrapper scripts executable by all
if [ -d "/usr/local/bin" ]; then
    print_status "Fixing wrapper script permissions..."
    for script in /usr/local/bin/responder /usr/local/bin/certipy-venv /usr/local/bin/*-venv; do
        if [ -f "$script" ]; then
            chmod 755 "$script"
            print_status "✓ Made $script executable"
        fi
    done
fi

# Fix pipx tool permissions
if [ -d "$USER_HOME/.local/bin" ]; then
    print_status "Fixing pipx tool permissions..."
    chown -R "$ACTUAL_USER:$(id -gn $ACTUAL_USER)" "$USER_HOME/.local/bin"
    chmod -R 755 "$USER_HOME/.local/bin"
    print_status "✓ Fixed pipx tools permissions"
fi

# Add user to necessary groups for tool execution
print_status "Adding $ACTUAL_USER to necessary groups..."
usermod -aG sudo "$ACTUAL_USER" 2>/dev/null || true
usermod -aG adm "$ACTUAL_USER" 2>/dev/null || true
usermod -aG dialout "$ACTUAL_USER" 2>/dev/null || true
print_status "✓ User groups updated"

print_status "Permission fixes complete"

# ==================== Comprehensive Installation Verification ====================
print_status "Running comprehensive installation verification..."
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║              Installation Verification Report                  ║"
echo "╚════════════════════════════════════════════════════════════════╝"

# Function to check if command exists with detailed verification
check_tool() {
    local tool_name=$1
    local test_command=${2:-"$tool_name --version"}

    if command -v "$tool_name" &> /dev/null; then
        local tool_path=$(command -v "$tool_name")
        echo -e "${GREEN}✓${NC} $tool_name"
        echo -e "  └─ Path: $tool_path"

        # Skip version check for tools that don't support standard version flags
        case $tool_name in
            nslookup|dig|ping|netstat|ncat)
                echo -e "  └─ Status: Available"
                ;;
            *)
                local version_output=$(eval "$test_command" 2>&1 | head -1)
                if [ -n "$version_output" ]; then
                    echo -e "  └─ $version_output"
                else
                    echo -e "  └─ Status: Installed (version info unavailable)"
                fi
                ;;
        esac
        return 0
    else
        echo -e "${RED}✗${NC} $tool_name - NOT FOUND"
        return 1
    fi
}

# Function to check Python package
check_python_package() {
    local package=$1
    local import_name=${2:-$package}

    if python3 -c "import $import_name" 2>/dev/null; then
        local version=$(python3 -c "import $import_name; print(getattr($import_name, '__version__', 'unknown'))" 2>/dev/null)
        echo -e "${GREEN}✓${NC} $package (version: $version)"
        return 0
    else
        echo -e "${RED}✗${NC} $package - NOT FOUND"
        return 1
    fi
}

# Counter for installed vs failed
TOOLS_INSTALLED=0
TOOLS_FAILED=0

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Core System Tools"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
check_tool nmap && ((TOOLS_INSTALLED++)) || ((TOOLS_FAILED++))
check_tool ncat && ((TOOLS_INSTALLED++)) || ((TOOLS_FAILED++))
check_tool smbclient && ((TOOLS_INSTALLED++)) || ((TOOLS_FAILED++))
check_tool hashcat && ((TOOLS_INSTALLED++)) || ((TOOLS_FAILED++))
check_tool proxychains4 && ((TOOLS_INSTALLED++)) || ((TOOLS_FAILED++))
check_tool netstat && ((TOOLS_INSTALLED++)) || ((TOOLS_FAILED++))
check_tool binwalk && ((TOOLS_INSTALLED++)) || ((TOOLS_FAILED++))
check_tool java && ((TOOLS_INSTALLED++)) || ((TOOLS_FAILED++))

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  GUI/Terminal Environment"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
check_tool i3 && ((TOOLS_INSTALLED++)) || ((TOOLS_FAILED++))
check_tool polybar && ((TOOLS_INSTALLED++)) || ((TOOLS_FAILED++))
check_tool zsh && ((TOOLS_INSTALLED++)) || ((TOOLS_FAILED++))
check_tool kitty && ((TOOLS_INSTALLED++)) || ((TOOLS_FAILED++))
check_tool obsidian && ((TOOLS_INSTALLED++)) || ((TOOLS_FAILED++))

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Python Tools (pipx - User: $ACTUAL_USER)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
# Check netexec
if su - "$ACTUAL_USER" -c "command -v netexec" &>/dev/null; then
    NXC_VER=$(su - "$ACTUAL_USER" -c "netexec --version 2>&1 | head -1" 2>/dev/null || echo "unknown")
    echo -e "${GREEN}✓${NC} netexec"
    echo -e "  └─ Version: $NXC_VER"
    echo -e "  └─ Accessible by: $ACTUAL_USER"
    ((TOOLS_INSTALLED++))
else
    echo -e "${RED}✗${NC} netexec - NOT FOUND"
    ((TOOLS_FAILED++))
fi

# Check impacket tools
if su - "$ACTUAL_USER" -c "command -v secretsdump.py" &>/dev/null; then
    echo -e "${GREEN}✓${NC} impacket (pipx)"
    echo -e "  └─ Sample tools:"
    for tool in secretsdump.py psexec.py smbexec.py GetNPUsers.py; do
        if su - "$ACTUAL_USER" -c "command -v $tool" &>/dev/null; then
            echo -e "     • $tool"
        fi
    done
    echo -e "  └─ Accessible by: $ACTUAL_USER"
    ((TOOLS_INSTALLED++))
else
    echo -e "${RED}✗${NC} impacket (pipx) - NOT FOUND"
    ((TOOLS_FAILED++))
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  DNS/Recon Tools"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if python3 -m pip show dnsrecon &>/dev/null || command -v dnsrecon &>/dev/null; then
    echo -e "${GREEN}✓${NC} dnsrecon"
    ((TOOLS_INSTALLED++))
else
    echo -e "${RED}✗${NC} dnsrecon - NOT FOUND"
    ((TOOLS_FAILED++))
fi

if command -v dnsenum &>/dev/null; then
    echo -e "${GREEN}✓${NC} dnsenum"
    ((TOOLS_INSTALLED++))
else
    echo -e "${RED}✗${NC} dnsenum - NOT FOUND"
    ((TOOLS_FAILED++))
fi

check_tool dig && ((TOOLS_INSTALLED++)) || ((TOOLS_FAILED++))
check_tool nslookup && ((TOOLS_INSTALLED++)) || ((TOOLS_FAILED++))

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Security Tools Virtual Environment (/opt/security-tools-venv)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ -d "$SECURITY_VENV" ]; then
    echo -e "${GREEN}✓${NC} Virtual environment exists"
    echo -e "  └─ Path: $SECURITY_VENV"
    echo -e "  └─ Owner: $(stat -c '%U' $SECURITY_VENV)"
    echo -e "  └─ Permissions: $(stat -c '%a' $SECURITY_VENV)"

    # Check tools in virtual environment
    source "$SECURITY_VENV/bin/activate"

    echo -e "\n  Python Packages in venv:"

    if python -c "import impacket" 2>/dev/null; then
        IMPACKET_VER=$(python -c "import impacket; print(impacket.version.BANNER)" 2>/dev/null | grep -oP 'v\d+\.\d+\.\d+' || echo "installed")
        echo -e "  ${GREEN}✓${NC} impacket ($IMPACKET_VER)"
        ((TOOLS_INSTALLED++))
    else
        echo -e "  ${RED}✗${NC} impacket"
        ((TOOLS_FAILED++))
    fi

    for pkg in netifaces aioquic cryptography ldap3 flask; do
        if python -c "import $pkg" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} $pkg"
            ((TOOLS_INSTALLED++))
        else
            echo -e "  ${RED}✗${NC} $pkg"
            ((TOOLS_FAILED++))
        fi
    done

    if python -c "import pyrebase" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} pyrebase4 (optional)"
    else
        echo -e "  ${YELLOW}⚠${NC} pyrebase4 (optional - not installed)"
    fi

    if command -v certipy &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} certipy-ad"
        ((TOOLS_INSTALLED++))
    else
        echo -e "  ${RED}✗${NC} certipy-ad"
        ((TOOLS_FAILED++))
    fi

    if [ -d "$SECURITY_VENV/responder" ] && [ -f "$SECURITY_VENV/responder/Responder.py" ]; then
        echo -e "  ${GREEN}✓${NC} Responder"
        ((TOOLS_INSTALLED++))
    else
        echo -e "  ${RED}✗${NC} Responder"
        ((TOOLS_FAILED++))
    fi

    deactivate
else
    echo -e "${RED}✗${NC} Security tools virtual environment NOT FOUND"
    ((TOOLS_FAILED+=10))
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Wrapper Scripts & System Integration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -f "/usr/local/bin/responder" ]; then
    echo -e "${GREEN}✓${NC} responder wrapper"
    echo -e "  └─ Path: /usr/local/bin/responder"
    echo -e "  └─ Permissions: $(stat -c '%a' /usr/local/bin/responder)"
    ((TOOLS_INSTALLED++))
else
    echo -e "${RED}✗${NC} responder wrapper NOT FOUND"
    ((TOOLS_FAILED++))
fi

if [ -f "/usr/local/bin/certipy-venv" ]; then
    echo -e "${GREEN}✓${NC} certipy-venv wrapper"
    echo -e "  └─ Path: /usr/local/bin/certipy-venv"
    ((TOOLS_INSTALLED++))
else
    echo -e "${RED}✗${NC} certipy-venv wrapper NOT FOUND"
    ((TOOLS_FAILED++))
fi

# Show Java versions
echo ""
echo "Java versions installed:"
update-alternatives --list java 2>/dev/null || echo "No Java alternatives configured"

# Show shell information
echo ""
echo "Shell configuration:"
echo "Current shell: $SHELL"
echo "Zsh location: $(which zsh)"
if [ -n "$SUDO_USER" ]; then
    echo "Default shell for $SUDO_USER: $(getent passwd "$SUDO_USER" | cut -d: -f7)"
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    [ -d "$USER_HOME/.oh-my-zsh" ] && echo -e "${GREEN}✓${NC} Oh My Zsh installed for $SUDO_USER" || echo -e "${RED}✗${NC} Oh My Zsh not found for $SUDO_USER"
fi
[ -d "/root/.oh-my-zsh" ] && echo -e "${GREEN}✓${NC} Oh My Zsh installed for root" || echo -e "${RED}✗${NC} Oh My Zsh not found for root"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                   Installation Summary                         ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo -e "  ${GREEN}✓ Tools Successfully Installed:${NC} $TOOLS_INSTALLED"
echo -e "  ${RED}✗ Tools Failed/Missing:${NC} $TOOLS_FAILED"
echo ""

if [ $TOOLS_FAILED -eq 0 ]; then
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}            🎉 All tools installed successfully! 🎉${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
elif [ $TOOLS_FAILED -lt 5 ]; then
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}     Installation completed with minor issues ($TOOLS_FAILED failed)${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════════${NC}"
else
    echo -e "${RED}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}   Installation completed with $TOOLS_FAILED failed installations${NC}"
    echo -e "${RED}   Please review the log above for details${NC}"
    echo -e "${RED}═══════════════════════════════════════════════════════════════════${NC}"
fi

echo ""
print_status "Installation complete!"
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                   IMPORTANT NEXT STEPS                         ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "  1. ${YELLOW}START A NEW TERMINAL SESSION${NC} for PATH changes to take effect"
echo "  2. All tools are installed for user: ${GREEN}$ACTUAL_USER${NC}"
echo "  3. Run 'check-all-tools' to verify tool accessibility"
echo "  4. Run 'sec-env' to activate Python virtual environment"
echo ""
echo "  Installation log saved to: $LOG_FILE"
echo ""

# Additional notes
echo ""
echo "=== Additional Notes ==="
echo "1. Security Tools Virtual Environment: /opt/security-tools-venv"
echo "   - Contains: impacket, responder, certipy-ad, netifaces, aioquic"
echo "   - Optional: pyrebase4 (may have failed to install, but script continues)"
echo "   - Owned by: $SUDO_USER (not root)"
echo "   - Activate with: source /opt/security-tools-venv/bin/activate"
echo "   - Or use alias: activate-security / sec-env"
echo "2. Tool Installation Methods:"
echo "   - netexec: Installed via pipx for user $SUDO_USER"
echo "   - impacket: Installed via pipx for user $SUDO_USER"
echo "   - python3-certipy: Installed via apt (system-wide)"
echo "   - certipy-ad: Installed in virtual environment (use certipy-venv wrapper)"
echo "   - responder: Installed from source in virtual environment"
echo "   - proxychains4: Installed via apt"
echo "   - net-tools: Installed via apt (provides netstat, ifconfig, etc.)"
echo "3. PATH Configuration:"
echo "   - Standard system directories: /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
echo "   - Snap applications: /snap/bin"
echo "   - User pipx tools: /home/$SUDO_USER/.local/bin"
echo "   - Virtual environment: /opt/security-tools-venv/bin"
echo "   - Configuration file: /etc/profile.d/security-tools.sh"
echo "   - Also added to: /home/$SUDO_USER/.zshrc"
echo "   - python3-certipy: Installed via apt (system-wide)"
echo "   - certipy-ad: Installed in virtual environment (use certipy-venv wrapper)"
echo "   - impacket: Installed from source in virtual environment"
echo "   - responder: Installed from source in virtual environment"
echo "   - proxychains4: Installed via apt"
echo "   - net-tools: Installed via apt (provides netstat, ifconfig, etc.)"
echo "3. Wrapper Scripts (in /usr/local/bin):"
echo "   - responder: Runs Responder from the virtual environment"
echo "   - certipy-venv: Runs certipy-ad from the virtual environment"
echo "   - Various impacket scripts: Auto-generated wrappers for venv tools"
echo "4. Virtual Environment Tools Usage:"
echo "   - Direct: source /opt/security-tools-venv/bin/activate && certipy"
echo "   - Via wrapper: certipy-venv (already in PATH)"
echo "   - Responder: responder -I eth0 (wrapper script)"
echo "5. Proxychains Configuration:"
echo "   - Config file: /etc/proxychains4.conf"
echo "   - Usage: proxychains4 <command> or use aliases: pchains/pc"
echo "6. Network Tools:"
echo "   - netstat, ifconfig, route: Available via net-tools package"
echo "   - netifaces: Python library for network interface detection (in venv)"
echo "   - aioquic: QUIC protocol support (in venv)"
echo "7. Zsh Configuration Updates:"
echo "   - Added aliases for security environment activation"
echo "   - Added proxychains shortcuts (pchains, pc)"
echo "   - All previous aliases and functions remain available"
echo "8. Python Environment Structure:"
echo "   - System Python: Basic tools, dnsrecon, apt packages"
echo "   - pipx: Isolated tools like netexec"
echo "   - Security venv: Advanced tools requiring specific dependencies"
echo "9. For Obsidian, if using AppImage, you may need to install additional dependencies"
echo "10. Some tools may require additional configuration for full functionality"
echo "11. i3 window manager: Kitty is set as default terminal. Config locations:"
echo "    - System: /etc/i3/config"
echo "    - User: ~/.config/i3/config"
echo "12. Java: Installed default JRE and OpenJDK 8. To switch versions use: sudo update-alternatives --config java"
echo "13. Hashcat: For NVIDIA GPUs, install CUDA. For AMD GPUs, install ROCm for better performance"
echo "14. Polybar: Configured to replace i3bar with system monitoring modules"
echo "    - Config: ~/.config/polybar/config.ini"
echo "    - Launch script: ~/.config/polybar/launch.sh"
echo "    - Modules: workspaces, window title, CPU, memory, network, battery, date/time"
echo "15. pyrebase4: This package may fail to install due to dependency issues."
echo "    If you need Firebase functionality, consider installing it manually or using alternative packages."
echo "16. netexec: Requires Rust compiler. Script will attempt to install Rust automatically."
echo "    If installation still fails, manually install Rust and restart shell:"
echo "    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
echo "    source ~/.cargo/env"
echo "    Then try: pipx install git+https://github.com/Pennyw0rth/NetExec"
echo ""
echo "=== Quick Start Commands ==="
echo "Activate security environment: activate-security"
echo "Run Responder: responder -I eth0"
echo "Run netexec: netexec smb <target>"
echo "Run certipy (venv): certipy-venv find -u user@domain"
echo "Run certipy (apt): certipy find -u user@domain"
echo "Use proxychains: pchains nmap <target>"
echo "Check network interfaces: python3 -c 'import netifaces; print(netifaces.interfaces())'"
