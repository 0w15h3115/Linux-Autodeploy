# Linux-Autodeploy
Script for Autodeploying security tools on barebones linux

## Overview
This script automates the installation and configuration of various security analysis tools on Ubuntu systems. It includes comprehensive error handling and rate-limiting protection for reliable deployment.

## Features
- **Automatic retry logic**: APT operations retry up to 5 times with exponential backoff
- **Rate limiting protection**: Built-in delays prevent 429 errors from Ubuntu mirrors
- **Comprehensive tool installation**: Includes red teaming, network analysis, and pentesting tools
- **Environment setup**: Configures zsh, i3, polybar, and kitty terminal
- **Multiple installation methods**: Uses apt, pipx, pip, and source installations as appropriate

## Tools Installed
- **Network tools**: nmap, ncat, netexec, smbclient, dnsrecon, dnsenum
- **Python frameworks**: impacket, responder, certipy-ad
- **Password cracking**: hashcat
- **Window manager**: i3, polybar, dmenu
- **Terminal**: kitty with zsh and oh-my-zsh
- **Note-taking**: Obsidian
- **Utilities**: proxychains4, net-tools, binwalk, and more

## Usage
```bash
sudo ./Ubuntu-Autodeploy2-Beta.sh
```

**Important**: Run with sudo, but not as root user directly. The script detects the SUDO_USER and installs user-specific tools correctly.

## Rate Limiting Handling
The script includes several mechanisms to handle APT rate limiting:

1. **Retry logic**: Each APT command retries up to 5 times with exponential backoff (30s, 60s, 120s, 240s, 480s)
2. **APT configuration**: Sets timeout and retry parameters in `/etc/apt/apt.conf.d/99retry`
3. **Delays**: Strategic delays between package installations to avoid triggering rate limits
4. **Queue mode**: Uses host-based queue mode to reduce concurrent connections

If you encounter "429 Too Many Requests" errors:
- The script will automatically retry with increasing wait times
- Wait times double after each failure (30s → 60s → 120s → 240s → 480s)
- After 5 failed attempts, the script will report an error

## Post-Installation
After installation completes:

1. **Restart your terminal** for PATH changes to take effect
2. Run `source ~/.zshrc` to load new shell configuration
3. Tools installed via pipx are in `~/.local/bin`
4. Virtual environment tools are in `/opt/security-tools-venv`

## Troubleshooting
If tools are not found after installation:
```bash
# Check pipx installations
pipx list

# Verify PATH
echo $PATH | grep -E 'local|snap|opt'

# Manually reload shell config
source ~/.zshrc

# Check tool locations
ls -la ~/.local/bin/
ls -la /opt/security-tools-venv/bin/
```

## Notes
- The script is designed for Ubuntu systems
- Some tools may require additional configuration
- Virtual environment can be activated with: `source /opt/security-tools-venv/bin/activate`
- Network interfaces may need to be adjusted for Responder and other tools
