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

        # GUI
        i3 i3status i3lock xss-lock dmenu polybar kitty zsh
    )

    print_status "Installing ${#packages[@]} packages..."
    apt-get install -y "${packages[@]}"

    print_status "✓ System packages installed"
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
    install_obsidian
    setup_rust
    install_pipx_tools
    setup_python_venv
    create_wrapper_scripts

    # TODO: Add GUI configuration
    # TODO: Add zsh configuration
    # TODO: Add permission fixes
    # TODO: Add verification

    print_section "Installation Complete!"
    print_status "Please restart your terminal for changes to take effect"
    print_status "Run 'source ~/.zshrc' to load new shell configuration"
}

# Run main function
main "$@"
