# Ubuntu Security Tools Installation Script - Specification v3.0

## Overview
Complete rewrite of the installation script with clean, modular, well-tested code.
Keep the excellent i3/zsh/terminal configurations from the original.

## Requirements

### Core Functionality
1. Install security analysis tools for red teaming and pentesting
2. Configure development environment (i3, polybar, kitty, zsh)
3. Set up Python virtual environment with security tools
4. Configure shell with useful aliases and functions

### Tools to Install

#### System Packages (via apt)
- **Build tools**: build-essential, git, curl, wget
- **Python**: python3, python3-pip, python3-venv, pipx
- **Libraries**: libssl-dev, libffi-dev, libpcap-dev, libgmp3-dev, libxml2-dev, libxslt1-dev
- **Network tools**: nmap, ncat, smbclient, dnsutils, proxychains4, net-tools, binwalk
- **System tools**: tmux, fonts-powerline, fonts-font-awesome
- **Security tools**: hashcat, dnsrecon, python3-ldapdomaindump, adcli, nbtscan
- **Java**: default-jre, openjdk-8-jre
- **OpenCL**: ocl-icd-libopencl1, opencl-headers, clinfo
- **GUI**: i3, i3status, i3lock, xss-lock, dmenu, polybar, kitty, zsh
- **Snap**: snapd (for Obsidian)

#### Python Tools (via pipx - user isolation)
- **netexec**: Modern replacement for CrackMapExec
- **impacket**: Python classes for network protocols (AD tools)

#### Python Tools (via pip in venv)
- **impacket** (from source): Latest version with all tools
- **responder** (from source): LLMNR/NBT-NS/mDNS poisoner
- **certipy-ad**: Active Directory certificate abuse
- **Dependencies**: netifaces, aioquic, cryptography, pyasn1, ldap3, ldapdomaindump, flask, pyOpenSSL, pycryptodome

#### GUI/Environment
- **Obsidian**: Note-taking app (via snap)
- **i3 + polybar**: Window manager with status bar
- **kitty**: GPU-accelerated terminal
- **zsh + oh-my-zsh**: Shell with agnoster theme

### Configuration Requirements

#### i3 Configuration
- Set kitty as default terminal
- Configure polybar to replace i3bar
- Copy existing i3 config sections from original script

#### Polybar Configuration
- Status bar with system monitoring
- Modules: workspaces, window title, CPU, memory, network, battery, date/time
- Copy existing polybar config from original script

#### Kitty Configuration
- Set zsh as default shell
- Background opacity 0.95
- 10000 line scrollback
- Copy existing kitty config from original script

#### Zsh Configuration
- Install oh-my-zsh with agnoster theme
- Enable plugins: git, docker, python, pip, nmap, ssh-agent, sudo, tmux, colored-man-pages, command-not-found, extract, z
- Add all 50+ aliases and functions from original script
- Configure PATH properly
- Copy all aliases/functions from original script

### Script Architecture

#### Structure
```
1. Header & Documentation
2. Core Functions
   - print_status, print_error, print_warning
   - check_root
   - check_user
   - install_apt_packages
   - install_pipx_tool
   - setup_venv
   - configure_component
3. Pre-flight Checks
4. System Package Installation
5. Python Tools (pipx)
6. Python Tools (venv)
7. GUI Configuration (i3, polybar, kitty)
8. Shell Configuration (zsh, oh-my-zsh)
9. Permission Fixes
10. Verification
11. Summary Report
```

#### Design Principles
- **Modular**: Each component in its own function
- **Testable**: Each function has single responsibility
- **Robust**: Proper error handling, no silent failures
- **Simple**: No over-engineering, straightforward logic
- **Clean**: Clear naming, minimal comments needed
- **Validated**: Check syntax at each step

### Error Handling
- Exit on critical errors (no sudo, no internet)
- Warn and continue on non-critical errors (optional packages)
- All failures logged clearly
- Return codes checked for all commands

### Testing Requirements
- Syntax validation with `bash -n`
- Dry-run capability (check what would be installed)
- Per-component testing during development
- No commits without passing tests

### Success Criteria
- Script runs without errors on fresh Ubuntu system
- All tools installed and accessible
- i3/polybar/kitty configuration identical to original
- Zsh with all aliases and functions from original
- Proper permissions (user can run all tools)
- Clean, readable, maintainable code

## Implementation Plan
1. Extract i3/polybar/kitty/zsh configs from original (copy verbatim)
2. Create new script skeleton with functions
3. Implement each section incrementally
4. Test after each section
5. Validate syntax continuously
6. Document as we go

## Non-Goals
- System updates (user does this separately)
- Complex retry logic (keep it simple)
- Rate limiting paranoia (not needed)
- Over-engineering (KISS principle)
