# Linux-Autodeploy
Automated security tools installation for Ubuntu systems

## Overview
Simple, straightforward script to install and configure essential security analysis tools on Ubuntu. Designed for red teaming, pentesting, and security analysis work.

## Tools Installed

### Network & Recon
- nmap, ncat, netexec, smbclient
- dnsrecon, dnsenum, dnsutils
- proxychains4, net-tools, binwalk

### Python Security Frameworks
- **impacket** (via pipx): Active Directory assessment tools
- **responder**: LLMNR/NBT-NS/mDNS poisoner
- **certipy-ad**: Active Directory certificate abuse

### Password Cracking
- hashcat with OpenCL support

### Development Environment
- i3 window manager with polybar
- kitty terminal
- zsh with oh-my-zsh
- Obsidian note-taking

## Prerequisites

Run system update before using this script:
```bash
sudo apt update && sudo apt upgrade -y
```

## Usage

**Recommended (v3.0 - Clean, modular architecture):**
```bash
sudo ./Ubuntu-Autodeploy-v3.sh
```

**Legacy version:**
```bash
sudo ./Ubuntu-Autodeploy2-Beta.sh
```

**Important**:
- Run with `sudo`, not as root user directly
- Script detects `$SUDO_USER` and installs user-specific tools correctly
- Logs installation to `/var/log/security-tools-install.log`
- v3 script automatically enables universe repository and updates package lists

## Post-Installation

1. **Restart your terminal** for PATH changes to take effect
2. Run `check-all-tools` to verify installations
3. Run `sec-env` to activate Python virtual environment

### Shell Features
The script adds 50+ aliases and helper functions:
- `quickscan <target>` - Fast nmap scan
- `fullscan <target>` - Comprehensive nmap scan
- `smbenum <target>` - SMB enumeration
- `check-all-tools` - Verify tool installations
- `genpass [length]` - Generate random passwords
- Plus many more encoding/decoding helpers

## Tool Locations

- **System tools**: Standard PATH (`/usr/bin`, `/usr/local/bin`)
- **pipx tools**: `~/.local/bin` (netexec, impacket)
- **Python venv**: `/opt/security-tools-venv` (responder, certipy-ad)
- **Wrapper scripts**: `/usr/local/bin` (responder, certipy-venv)

## Troubleshooting

If tools are not found after installation:
```bash
# Verify installations
check-all-tools

# Check pipx tools
pipx list

# Verify PATH
echo $PATH | grep -E 'local|snap|opt'

# Reload shell
source ~/.zshrc
```

## Notes
- Designed for Ubuntu/Debian-based systems
- Some tools may require additional configuration for specific use cases
- Network interfaces may need adjustment (e.g., `eth0` → your interface)
- Virtual environment: `sec-env` or `source /opt/security-tools-venv/bin/activate`
