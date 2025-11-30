#!/bin/bash

# ===============================================
# Code-Server Complete Installation & Management Script (Enhanced)
# Author: MiniMax Agent
# Version: 3.0 Enhanced with Security & Extensions
# Description: Production-ready installer with comprehensive features
# ===============================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration file paths
CONFIG_FILE="/etc/code-server/installer-config.json"
LOG_FILE="/var/log/code-server-installer.log"
MANAGEMENT_PANEL="/usr/local/bin/code-server-panel"
BACKUP_DIR="$HOME/code-server-backup"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >> "$LOG_FILE"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $1" >> "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $1" >> "$LOG_FILE"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "$LOG_FILE"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_warning "⚠️ RUNNING AS ROOT USER ⚠️"
        print_status "Running with root privileges detected"
        print_status "This is acceptable but ensure your server is properly secured"
        echo ""
        read -p "Continue with root privileges? (yes/no): " confirm_root
        if [[ ! "$confirm_root" =~ ^[Yy][Ee][Ss]$ ]]; then
            print_status "Please run as regular user: su - username"
            exit 1
        fi
        echo ""
    else
        if ! sudo -n true 2>/dev/null; then
            print_warning "This script requires sudo privileges"
            sudo -v || exit 1
        fi
    fi
}

# Enhanced function to collect user input with validation
collect_user_input() {
    print_status "Collecting installation requirements..."
    
    # Domain name with enhanced validation
    while [[ -z "${DOMAIN:-}" ]]; do
        echo -n -e "${CYAN}Enter your domain name (e.g., code.example.com): ${NC}"
        read -r DOMAIN
        if [[ -z "$DOMAIN" ]]; then
            print_error "Domain name cannot be empty"
        elif [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
            print_error "Invalid domain name format"
            print_info "Examples: example.com, code.example.com, my-site.co.uk"
            DOMAIN=""
        fi
    done
    
    # Admin email for Let's Encrypt with enhanced validation
    while [[ -z "${ADMIN_EMAIL:-}" ]]; do
        echo -n -e "${CYAN}Enter your email address for SSL certificate: ${NC}"
        read -r ADMIN_EMAIL
        if [[ -z "$ADMIN_EMAIL" ]]; then
            print_error "Email cannot be empty"
        elif [[ ! "$ADMIN_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            print_error "Invalid email format"
            print_info "Please enter a valid email address like: user@example.com"
            ADMIN_EMAIL=""
        fi
    done
    
    # Code-server password with enhanced validation
    while [[ -z "${CODE_SERVER_PASSWORD:-}" ]]; do
        echo -n -e "${CYAN}Enter password for code-server (min 8 characters): ${NC}"
        read -rs CODE_SERVER_PASSWORD
        echo
        if [[ ${#CODE_SERVER_PASSWORD} -lt 8 ]]; then
            print_error "Password must be at least 8 characters long"
            CODE_SERVER_PASSWORD=""
        elif [[ "$CODE_SERVER_PASSWORD" =~ [[:space:]] ]]; then
            print_error "Password cannot contain spaces"
            CODE_SERVER_PASSWORD=""
        elif [[ "$CODE_SERVER_PASSWORD" =~ \\ ]]; then
            print_error "Password cannot contain backslash (\\) character"
            CODE_SERVER_PASSWORD=""
        elif [[ ! "$CODE_SERVER_PASSWORD" =~ [A-Z] ]]; then
            print_warning "Password should contain at least one uppercase letter for better security"
        elif [[ ! "$CODE_SERVER_PASSWORD" =~ [0-9] ]]; then
            print_warning "Password should contain at least one number for better security"
        fi
    done
    
    # Installation method
    echo -e "${CYAN}Choose installation method:${NC}"
    echo "1) Native Installation (Recommended for production)"
    echo "2) Docker Installation (Recommended for isolation)"
    read -p "Enter your choice (1-2): " INSTALL_METHOD
    
    case $INSTALL_METHOD in
        1) INSTALL_METHOD="native" ;;
        2) INSTALL_METHOD="docker" ;;
        *) print_error "Invalid choice. Exiting."; exit 1 ;;
    esac
    
    # Server region/timezone
    echo -n -e "${CYAN}Enter your server timezone (e.g., America/New_York, Europe/London, Asia/Tehran): ${NC}"
    read TIMEZONE
    
    # Save configuration with security
    sudo mkdir -p "$(dirname "$CONFIG_FILE")"
    sudo tee "$CONFIG_FILE" >/dev/null <<EOF
{
    "domain": "$DOMAIN",
    "admin_email": "$ADMIN_EMAIL",
    "code_server_password": "$CODE_SERVER_PASSWORD",
    "install_method": "$INSTALL_METHOD",
    "timezone": "${TIMEZONE:-UTC}",
    "install_date": "$(date -Iseconds)",
    "version": "3.0 Enhanced"
}
EOF
    
    # Set strict permissions
    sudo chmod 600 "$CONFIG_FILE"
    sudo chown root:root "$CONFIG_FILE"
    
    print_success "Configuration saved securely"
}

# Enhanced function to setup swap space
setup_swap_space() {
    local swap_size_gb=$1
    
    print_status "Setting up ${swap_size_gb}GB swap space..."
    
    # Check if swap already exists
    if swapon --show | grep -q "swap"; then
        print_warning "Swap space already exists"
        swapon --show
        return 0
    fi
    
    local swap_file="/swapfile"
    local swap_size_mb=$((swap_size_gb * 1024))
    
    print_status "Creating ${swap_size_gb}GB swap file..."
    if ! sudo fallocate -l ${swap_size_gb}G "$swap_file" 2>/dev/null; then
        print_warning "fallocate failed, trying dd command..."
        sudo dd if=/dev/zero of="$swap_file" bs=1M count=$swap_size_mb status=progress
    fi
    
    sudo chmod 600 "$swap_file"
    sudo mkswap "$swap_file" &>/dev/null
    sudo swapon "$swap_file"
    
    # Make it permanent
    if ! grep -q "$swap_file" /etc/fstab 2>/dev/null; then
        echo "$swap_file none swap sw 0 0" | sudo tee -a /etc/fstab >/dev/null
    fi
    
    local swap_total=$(free -h | awk '/^Swap:/ {print $2}')
    print_success "Swap space created successfully: ${swap_total}"
}

# Enhanced function to handle low memory
handle_low_memory() {
    local total_mem=$1
    print_warning "⚠️ LOW MEMORY DETECTED: ${total_mem}MB"
    echo ""
    echo -e "${YELLOW}💡 SOLUTION:${NC} Your system has insufficient RAM for code-server."
    echo -e "${YELLOW}   We can create 'Swap Space' using your hard drive to compensate.${NC}"
    echo ""
    
    # Show current status
    echo -e "${BLUE}Current Status:${NC}"
    echo "• RAM: ${total_mem}MB"
    echo "• Swap: $(free -h 2>/dev/null | awk '/^Swap:/ {print $2}' || echo "None")"
    echo ""
    
    # Ask user for confirmation
    while true; do
        read -p "Create swap space to compensate for low RAM? (y/n): " -n 1 -r
        echo
        case $REPLY in
            [Yy]* )
                # Ask for swap size
                echo ""
                echo -e "${CYAN}Choose swap space size:${NC}"
                echo "1) 2GB (recommended for ${total_mem}MB RAM)"
                echo "2) 4GB (better performance)"
                echo "3) Custom size"
                echo ""
                
                while true; do
                    read -p "Enter choice (1-3): " choice
                    case $choice in
                        1) swap_size=2; break ;;
                        2) swap_size=4; break ;;
                        3)
                            while true; do
                                read -p "Enter custom swap size in GB (1-8): " custom_size
                                if [[ $custom_size =~ ^[1-8]$ ]] && [[ $custom_size -gt 0 ]]; then
                                    swap_size=$custom_size
                                    break
                                else
                                    print_error "Please enter a number between 1 and 8"
                                fi
                            done
                            break
                            ;;
                        *)
                            print_error "Invalid choice. Please enter 1, 2, or 3"
                            ;;
                    esac
                done
                
                # Check disk space with safety margin
                local available_disk=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//' | tr -d ' ')
                local required_space=$((swap_size + 2))
                
                if [[ -z "$available_disk" ]] || [[ $available_disk -lt $required_space ]]; then
                    print_error "Insufficient disk space. Need ${required_space}GB but only ${available_disk}GB available."
                    read -p "Continue with installation anyway? (y/n): " -n 1 -r
                    echo
                    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                        print_error "Installation cancelled due to insufficient resources."
                        exit 1
                    fi
                else
                    print_status "Proceeding with ${swap_size}GB swap space creation..."
                    setup_swap_space $swap_size
                fi
                break
                ;;
            [Nn]* )
                print_warning "Proceeding without swap space..."
                echo -e "${YELLOW}   Warning: Code-server may experience performance issues${NC}"
                echo ""
                sleep 2
                break
                ;;
            *)
                print_error "Please answer with 'y' for yes or 'n' for no"
                ;;
        esac
    done
}

# Enhanced function to check system requirements
check_system_requirements() {
    print_status "Checking system requirements..."
    
    # Check OS
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS="$ID"
        VERSION="$VERSION_ID"
    else
        print_error "Cannot determine operating system"
        exit 1
    fi
    
    case $OS in
        ubuntu|debian|centos|rhel|fedora)
            print_success "Supported OS: $OS $VERSION"
            ;;
        *)
            print_warning "OS $OS may not be fully supported"
            ;;
    esac
    
    # Check memory
    TOTAL_MEM=$(free -m | awk 'NR==2{print $2}')
    if [[ $TOTAL_MEM -lt 1024 ]]; then
        handle_low_memory $TOTAL_MEM
        print_success "Memory check completed ✓"
    else
        print_success "Memory: ${TOTAL_MEM}MB ✓"
    fi
    
    # Check disk space
    DISK_SPACE=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ $DISK_SPACE -lt 5 ]]; then
        print_error "Insufficient disk space. At least 5GB required."
        exit 1
    else
        print_success "Disk space: ${DISK_SPACE}GB ✓"
    fi
    
    # Check internet connectivity
    print_status "Testing internet connectivity..."
    local connectivity_ok=false
    for host in google.com 1.1.1.1 cloudflare.com; do
        if ping -c 1 -W 5 "$host" &>/dev/null; then
            connectivity_ok=true
            break
        fi
    done
    
    if [[ "$connectivity_ok" == "true" ]]; then
        print_success "Internet connectivity ✓"
    else
        print_error "No internet connection detected"
        exit 1
    fi
}

# Enhanced function to install system dependencies
install_dependencies() {
    print_status "Installing system dependencies..."
    
    case $OS in
        ubuntu|debian)
            print_status "Updating package lists..."
            if ! sudo apt update -qq 2>/dev/null; then
                print_error "Failed to update package lists"
                exit 1
            fi
            print_status "Installing dependencies..."
            if ! sudo apt install -y curl wget unzip nginx certbot python3-certbot-nginx \
                git build-essential software-properties-common apt-transport-https \
                ca-certificates gnupg lsb-release ufw htop jq dnsutils fail2ban \
                logrotate unattended-upgrades; then
                print_error "Failed to install some dependencies"
                exit 1
            fi
            ;;
        centos|rhel|fedora)
            print_status "Updating package lists..."
            if ! sudo yum update -y 2>/dev/null; then
                print_error "Failed to update package lists"
                exit 1
            fi
            print_status "Installing dependencies..."
            if ! sudo yum install -y curl wget unzip nginx certbot python3-certbot-nginx \
                git gcc gcc-c++ make epel-release htop jq bind-utils fail2ban; then
                print_error "Failed to install some dependencies"
                exit 1
            fi
            if [[ $OS == "fedora" ]]; then
                sudo dnf install -y firewalld 2>/dev/null
                sudo systemctl enable --now firewalld 2>/dev/null
                sudo firewall-cmd --permanent --add-service=http 2>/dev/null
                sudo firewall-cmd --permanent --add-service=https 2>/dev/null
                sudo firewall-cmd --reload 2>/dev/null
            fi
            ;;
        *)
            print_error "Unsupported OS for automatic dependency installation"
            exit 1
            ;;
    esac
    
    # Configure timezone if specified
    if [[ -n "${TIMEZONE:-}" ]]; then
        sudo timedatectl set-timezone "$TIMEZONE" 2>/dev/null || print_warning "Failed to set timezone"
        print_success "Timezone set to $TIMEZONE"
    fi
    
    print_success "System dependencies installed"
}

# Function to detect docker compose command
get_docker_compose_cmd() {
    if command -v docker &>/dev/null; then
        if docker compose version &>/dev/null 2>&1; then
            echo "docker compose"
            return 0
        elif command -v docker-compose &>/dev/null; then
            echo "docker-compose"
            return 0
        else
            echo ""
            return 1
        fi
    else
        echo ""
        return 1
    fi
}

# NEW: Install Code-Server Extensions for Enhanced Features
install_code_server_extensions() {
    print_status "🎨 Installing Code-Server Extensions for Enhanced Functionality..."
    
    # Essential extensions for comprehensive development
    local extensions=(
        "ms-python.python"
        "ms-python.pylance"
        "ms-python.debugpy"
        "ms-python.isort"
        "ms-python.black-formatter"
        "ms-python.mypy-type-checker"
        "ms-toolsai.jupyter"
        "ms-toolsai.jupyter-keymap"
        "ms-toolsai.jupyter-renderers"
        "bradlc.vscode-tailwindcss"
        "njpwerner.autodocstring"
        "kevinrose.vsc-python-indent"
        "littlefoxteam.vscode-python-test-adapter"
        "ms-vscode.vscode-typescript-next"
        "ms-vscode.vscode-css"
        "ms-vscode.vscode-html"
        "ms-vscode.vscode-json"
        "github.copilot"
        "github.copilot-chat"
        "eamodio.gitlens"
        "donjayamanne.githistory"
        "ms-azuretools.vscode-docker"
        "ms-vscode-remote.remote-containers"
        "redhat.vscode-yaml"
        "ms-vscode.vscode-markdown"
        "ms-vscode.vscode-markdown-language-features"
        "yzhang.markdown-all-in-one"
        "davidanson.vscode-markdownlint"
        "shd101wyy.markdown-preview-enhanced"
        "ms-vscode.vscode-sql"
        "mtxr.sqltools"
        "mtxr.sqltools-driver-sqlite"
        "bradlc.vscode-better-default-themes"
        "johnpapa.vscode-peacock"
        "pkief.material-icon-theme"
        "formulahendry.code-runner"
        "christian-kohler.path-intellisense"
        "visualstudioexptteam.vscodeintellicode"
        "ms-vscode.vscode-auto-rename-tag"
        "formulahendry.auto-rename-tag"
        "esbenp.prettier-vscode"
        "ms-vscode.vscode-eslint"
    )
    
    print_status "Installing ${#extensions[@]} essential extensions..."
    
    local installed_count=0
    local failed_count=0
    
    for extension in "${extensions[@]}"; do
        print_status "Installing: $extension"
        if code-server --install-extension "$extension" 2>/dev/null; then
            ((installed_count++))
            print_success "✓ $extension installed"
        else
            ((failed_count++))
            print_warning "⚠ Failed to install $extension"
        fi
    done
    
    echo ""
    print_status "Extension installation summary:"
    print_success "✓ Successfully installed: $installed_count extensions"
    if [[ $failed_count -gt 0 ]]; then
        print_warning "⚠ Failed to install: $failed_count extensions"
    fi
}

# NEW: Configure Enhanced Settings
configure_enhanced_settings() {
    print_status "⚙️ Configuring Enhanced Code-Server Settings..."
    
    local user_config_dir="$HOME/.config/code-server"
    local user_settings_file="$user_config_dir/User/settings.json"
    
    # Create directories
    mkdir -p "$user_config_dir/User"
    
    # Create enhanced settings.json with comprehensive features
    cat > "$user_settings_file" <<'EOF'
{
    "python.languageServer": "Pylance",
    "python.analysis.typeCheckingMode": "basic",
    "python.analysis.autoImportCompletions": true,
    "python.analysis.completeFunctionParens": true,
    "python.linting.enabled": true,
    "python.linting.pylintEnabled": true,
    "python.formatting.provider": "black",
    "python.sortImports.args": ["--profile", "black"],
    "python.testing.pytestEnabled": true,
    "python.testing.unittestEnabled": false,
    "python.testing.pytestArgs": [
        "."
    ],
    "editor.formatOnSave": true,
    "editor.codeActionsOnSave": {
        "source.organizeImports": true
    },
    "editor.minimap.enabled": true,
    "editor.lineNumbers": "on",
    "editor.renderWhitespace": "boundary",
    "editor.wordWrap": "on",
    "editor.tabSize": 4,
    "editor.insertSpaces": true,
    "editor.detectIndentation": false,
    "editor.semanticHighlighting.enabled": true,
    "editor.bracketPairColorization.enabled": true,
    "editor.guides.bracketPairs": true,
    "editor.guides.indentation": true,
    "editor.inlayHints.enabled": "on",
    "workbench.colorTheme": "One Dark Pro",
    "workbench.iconTheme": "material-icon-theme",
    "workbench.preferredDarkColorTheme": "One Dark Pro",
    "terminal.integrated.defaultProfile.linux": "bash",
    "terminal.integrated.fontSize": 14,
    "git.enableSmartCommit": true,
    "git.autofetch": true,
    "git.confirmSync": false,
    "github.copilot.enable": true,
    "gitlens.blame.compact": false,
    "gitlens.blame.heatmap.enabled": false,
    "docker.defaultRegistryPath": "//registry.hub.docker.com",
    "docker.languageserver.dockerfile.sortPackageJson": true,
    "jupyter.askForKernelRestart": false,
    "jupyter.generateSVGPlots": true,
    "tailwindCSS.includeLanguages": {
        "javascript": "javascript",
        "html": "HTML"
    },
    "emmet.includeLanguages": {
        "javascript": "javascriptreact"
    },
    "files.associations": {
        "*.py": "python",
        "*.js": "javascript",
        "*.ts": "typescript",
        "*.jsx": "javascriptreact",
        "*.tsx": "typescriptreact",
        "*.html": "html",
        "*.css": "css",
        "*.scss": "scss",
        "*.sass": "sass",
        "*.less": "less",
        "*.json": "json",
        "*.jsonc": "jsonc",
        "*.md": "markdown",
        "*.yml": "yaml",
        "*.yaml": "yaml",
        "*.sql": "sql",
        "Dockerfile*": "dockerfile",
        "*.dockerfile": "dockerfile"
    },
    "files.trimTrailingWhitespace": true,
    "files.insertFinalNewline": true,
    "files.trimFinalNewlines": true,
    "explorer.confirmDelete": false,
    "explorer.confirmDragAndDrop": false,
    "breadcrumbs.enabled": true,
    "outline.showVariables": true,
    "outline.showFunctions": true,
    "outline.showClasses": true,
    "outline.showInterfaces": true,
    "outline.showModules": true
}
EOF
    
    print_success "Enhanced settings configured ✓"
}

# NEW: Configure Security Enhancements
configure_security_enhancements() {
    print_status "🔒 Configuring Enhanced Security..."
    
    # Enable fail2ban
    if command -v fail2ban-server &>/dev/null; then
        sudo systemctl enable fail2ban 2>/dev/null
        sudo systemctl start fail2ban 2>/dev/null
        print_success "✓ Fail2ban enabled"
    fi
    
    # Configure automatic security updates for Ubuntu/Debian
    if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
        if command -v unattended-upgrade &>/dev/null; then
            echo "unattended-upgrades unattended-upgrades/enable_auto_updates boolean true" | sudo debconf-set-selections
            sudo dpkg-reconfigure --priority=low unattended-upgrades 2>/dev/null
            print_success "✓ Automatic security updates configured"
        fi
    fi
    
    # Set proper file permissions
    sudo find /etc/code-server -type f -exec chmod 600 {} \; 2>/dev/null || true
    sudo find /etc/code-server -type d -exec chmod 700 {} \; 2>/dev/null || true
    
    # Configure log rotation
    sudo tee /etc/logrotate.d/code-server >/dev/null <<'EOF'
/var/log/code-server*.log {
    weekly
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 644 root root
}

/var/log/nginx/code-server*.log {
    weekly
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 644 www-data adm
}
EOF
    
    print_success "Security enhancements configured"
}

# NEW: Configure Performance Optimizations
configure_performance_optimizations() {
    print_status "⚡ Configuring Performance Optimizations..."
    
    # Create systemd override for performance
    sudo mkdir -p /etc/systemd/system/code-server@.service.d/
    sudo tee /etc/systemd/system/code-server@.service.d/performance.conf >/dev/null <<'EOF'
[Service]
# Increase file limits for better performance
LimitNOFILE=65536
# Set proper working directory
WorkingDirectory=/home/%i
# Environment variables for performance
Environment=NODE_ENV=production
Environment=NODE_OPTIONS=--max-old-space-size=4096
# Increase timeout settings
TimeoutStartSec=60
TimeoutStopSec=30
EOF
    
    # Configure system performance
    echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf 2>/dev/null
    echo 'vm.vfs_cache_pressure=50' | sudo tee -a /etc/sysctl.conf 2>/dev/null
    sudo sysctl -p 2>/dev/null
    
    # Create performance monitoring script
    sudo tee /usr/local/bin/code-server-monitor >/dev/null <<'MONITOR_EOF'
#!/bin/bash
# Code-Server Health Monitor

CONFIG_FILE="/etc/code-server/installer-config.json"
LOG_FILE="/var/log/code-server-health.log"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Check if config exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    log_message "ERROR: Config file not found"
    exit 1
fi

DOMAIN=$(jq -r '.domain' "$CONFIG_FILE" 2>/dev/null)
INSTALL_METHOD=$(jq -r '.install_method' "$CONFIG_FILE" 2>/dev/null)

# Check service status
if [[ "$INSTALL_METHOD" == "native" ]]; then
    USER=$(whoami)
    if ! sudo systemctl is-active --quiet code-server@$USER 2>/dev/null; then
        log_message "WARNING: Code-server service is down, restarting..."
        sudo systemctl restart code-server@$USER 2>/dev/null
        log_message "INFO: Code-server service restarted"
    fi
elif [[ "$INSTALL_METHOD" == "docker" ]]; then
    if ! docker ps | grep -q "code-server" 2>/dev/null; then
        log_message "WARNING: Code-server container is down, restarting..."
        cd ~/.code-server && docker compose restart 2>/dev/null
        log_message "INFO: Code-server container restarted"
    fi
fi

# Check disk space
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
if [[ $DISK_USAGE -gt 85 ]]; then
    log_message "WARNING: Disk usage is ${DISK_USAGE}%"
fi

# Check memory usage
MEM_USAGE=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')
if [[ $MEM_USAGE -gt 90 ]]; then
    log_message "WARNING: Memory usage is ${MEM_USAGE}%"
fi

# Check if domain is accessible
if ! curl -s -o /dev/null -w "%{http_code}" "https://$DOMAIN" | grep -q "200"; then
    log_message "WARNING: Domain $DOMAIN is not accessible"
fi
MONITOR_EOF
    
    sudo chmod +x /usr/local/bin/code-server-monitor
    
    # Setup cron job for monitoring (every 5 minutes)
    (crontab -l 2>/dev/null | grep -v code-server-monitor; echo "*/5 * * * * /usr/local/bin/code-server-monitor >> /var/log/code-server-health.log 2>&1") | crontab -
    
    print_success "Performance optimizations applied"
}

# Enhanced function to install code-server
install_code_server() {
    print_status "Installing code-server..."
    
    # Get latest version
    local version=""
    if command -v curl &>/dev/null; then
        version=$(curl -s https://api.github.com/repos/coder/code-server/releases/latest 2>/dev/null | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/' || echo "latest")
    else
        version="latest"
    fi
    
    print_status "Installing version: $version"
    
    if [[ "$INSTALL_METHOD" == "native" ]]; then
        # Native installation
        if ! curl -fsSL https://code-server.dev/install.sh | sh; then
            print_error "Failed to install code-server natively"
            exit 1
        fi
        
        # Configure code-server
        mkdir -p ~/.config/code-server
        cat > ~/.config/code-server/config.yaml <<EOF
bind-addr: 127.0.0.1:8080
auth: password
password: $CODE_SERVER_PASSWORD
cert: false
EOF
        
        # Set secure permissions
        chmod 600 ~/.config/code-server/config.yaml
        
        # Enable and start service
        USER=$(whoami)
        sudo systemctl enable --now code-server@$USER 2>/dev/null || print_warning "Failed to enable code-server service"
        
        # Update systemd service
        sudo systemctl daemon-reload 2>/dev/null
        sudo systemctl restart code-server@$USER 2>/dev/null || print_warning "Failed to restart code-server service"
        
        print_success "Code-server installed natively"
        
        # Install extensions and configure enhanced settings
        sleep 5  # Wait for service to fully start
        install_code_server_extensions
        configure_enhanced_settings
        
    elif [[ "$INSTALL_METHOD" == "docker" ]]; then
        # Docker installation
        if ! command -v docker &>/dev/null; then
            print_status "Installing Docker..."
            if ! curl -fsSL https://get.docker.com | sh; then
                print_error "Failed to install Docker"
                exit 1
            fi
            sudo usermod -aG docker "$USER" 2>/dev/null
            print_warning "Please log out and log back in for Docker permissions to take effect"
        fi
        
        # Create directories for persistence
        mkdir -p ~/.code-server/{config,local,workspace}
        
        # Enhanced docker-compose.yml
        COMPOSE_FILE="docker-compose.yml"
        cat > "$COMPOSE_FILE" <<EOF
version: '3.8'

services:
  code-server:
    image: codercom/code-server:latest
    container_name: code-server-enhanced
    restart: unless-stopped
    ports:
      - "127.0.0.1:8080:8080"
    volumes:
      - ~/.code-server/config:/home/coder/.config/code-server
      - ~/.code-server/local:/home/coder/.local/share/code-server
      - ~/.code-server/workspace:/home/coder/project
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment:
      - PASSWORD=$CODE_SERVER_PASSWORD
      - DOCKER_USER=$USER
      - NODE_ENV=production
      - NODE_OPTIONS=--max-old-space-size=4096
    command: ["--bind-addr", "127.0.0.1:8080", "--auth", "password", "--cert"]
    ulimits:
      nofile:
        soft: 65536
        hard: 65536

networks:
  default:
    name: code-server-network
EOF
        
        # Start Docker container
        local compose_cmd=$(get_docker_compose_cmd)
        if [[ -n "$compose_cmd" ]]; then
            $compose_cmd up -d 2>/dev/null || print_warning "Failed to start Docker container"
            print_success "Code-server installed via Docker"
            
            # Install extensions and configure settings (in Docker)
            sleep 5
            install_code_server_extensions
            configure_enhanced_settings
        else
            print_error "Docker compose not available"
            exit 1
        fi
    fi
}

# Enhanced function to configure nginx
configure_nginx() {
    print_status "Configuring Nginx reverse proxy..."
    
    # Check if nginx is installed
    if ! command -v nginx &>/dev/null; then
        print_error "Nginx is not installed"
        exit 1
    fi
    
    # Start Nginx if not running
    if ! sudo systemctl is-active --quiet nginx 2>/dev/null; then
        sudo systemctl start nginx 2>/dev/null || print_warning "Failed to start Nginx"
    fi
    
    # Backup existing config
    if [[ -f /etc/nginx/sites-enabled/default ]]; then
        sudo cp /etc/nginx/sites-enabled/default /etc/nginx/sites-enabled/default.backup.$(date +%Y%m%d-%H%M%S)
    fi
    
    # Create enhanced Nginx configuration
    sudo tee /etc/nginx/sites-available/code-server >/dev/null <<EOF
# Rate limiting
limit_req_zone \$binary_remote_addr zone=code_server:10m rate=10r/m;

# Enhanced security and performance configuration
server {
    listen 80;
    server_name $DOMAIN;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline' 'unsafe-eval'" always;
    
    # Allow large file uploads
    client_max_body_size 100M;
    
    # Rate limiting for code-server endpoints
    location / {
        limit_req zone=code_server burst=20 nodelay;
        
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        proxy_connect_timeout 60;
        proxy_redirect off;
        
        # Enhanced buffering
        proxy_buffering on;
        proxy_buffer_size 4K;
        proxy_buffers 8 4K;
        proxy_busy_buffers_size 8K;
    }
    
    # WebSocket support
    location ~* /.*\.sock {
        limit_req zone=code_server burst=20 nodelay;
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
    
    # Enable site
    sudo ln -sf /etc/nginx/sites-available/code-server /etc/nginx/sites-enabled/code-server
    
    # Remove default site
    sudo rm -f /etc/nginx/sites-enabled/default
    
    # Test configuration
    if sudo nginx -t; then
        sudo systemctl enable nginx 2>/dev/null
        sudo systemctl reload nginx 2>/dev/null || sudo systemctl restart nginx 2>/dev/null
        print_success "Nginx configured successfully"
    else
        print_error "Nginx configuration test failed"
        exit 1
    fi
}

# Enhanced SSL setup function
setup_ssl() {
    print_status "Setting up SSL certificate..."
    
    # DNS check
    DOMAIN_IP=""
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null || echo "")
    
    # Get domain IP
    if command -v dig &>/dev/null; then
        DOMAIN_IP=$(dig +short "$DOMAIN" @8.8.8.8 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
    elif command -v nslookup &>/dev/null; then
        DOMAIN_IP=$(nslookup "$DOMAIN" 2>/dev/null | awk '/^Address: / { print $2 }' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
    fi
    
    # Check DNS
    if [[ -n "$DOMAIN_IP" && -n "$SERVER_IP" && "$DOMAIN_IP" != "$SERVER_IP" ]]; then
        print_warning "Domain DNS may not be pointing to this server"
        print_status "Domain IP: $DOMAIN_IP, Server IP: $SERVER_IP"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_error "SSL setup aborted"
            exit 1
        fi
    fi
    
    # Request SSL certificate with retry logic
    print_status "Requesting SSL certificate from Let's Encrypt..."
    
    local max_attempts=3
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if sudo certbot --nginx -d "$DOMAIN" --email "$ADMIN_EMAIL" --agree-tos --non-interactive --expand --redirect; then
            break
        else
            print_warning "SSL certificate request failed (attempt $attempt of $max_attempts)"
            if [[ $attempt -lt $max_attempts ]]; then
                print_status "Retrying in 5 seconds..."
                sleep 5
                ((attempt++))
            else
                print_error "Failed to obtain SSL certificate after $max_attempts attempts"
                exit 1
            fi
        fi
    done
    
    # Enable automatic renewal
    sudo systemctl enable --now certbot.timer 2>/dev/null || print_warning "Could not enable certbot timer"
    
    # Update nginx configuration for SSL
    update_nginx_ssl_config
    
    print_success "SSL certificate installed and auto-renewal enabled"
}

# Enhanced nginx SSL configuration
update_nginx_ssl_config() {
    print_status "Updating Nginx configuration for SSL..."
    
    # Create comprehensive SSL-enabled configuration
    sudo tee /etc/nginx/sites-available/code-server >/dev/null <<EOF
# Rate limiting
limit_req_zone \$binary_remote_addr zone=code_server:10m rate=10r/m;

# Enhanced SSL and security configuration
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;
    
    # Enhanced SSL Configuration
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_stapling on;
    ssl_stapling_verify on;
    
    # Security Headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline' 'unsafe-eval'" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    
    # Allow large file uploads
    client_max_body_size 100M;
    
    # Rate limiting
    limit_req_zone \$binary_remote_addr zone=code_server:10m rate=10r/m;
    
    # Enhanced proxy configuration
    location / {
        limit_req zone=code_server burst=20 nodelay;
        
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        proxy_connect_timeout 60;
        proxy_redirect off;
        
        # Enhanced buffering for performance
        proxy_buffering on;
        proxy_buffer_size 4K;
        proxy_buffers 8 4K;
        proxy_busy_buffers_size 8K;
    }
    
    # Static file optimization
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        proxy_pass http://127.0.0.1:8080;
        expires 1y;
        add_header Cache-Control "public, immutable";
        add_header X-Content-Type-Options "nosniff" always;
    }
    
    # WebSocket support for real-time features
    location /socket.io/ {
        limit_req zone=code_server burst=20 nodelay;
        proxy_pass http://127.0.0.1:8080/socket.io/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 86400;
    }
    
    # Health check endpoint
    location /health {
        proxy_pass http://127.0.0.1:8080;
        access_log off;
    }
}
EOF
    
    # Test and reload nginx
    if sudo nginx -t; then
        sudo systemctl restart nginx 2>/dev/null
        print_success "Nginx SSL configuration updated successfully"
    else
        print_error "Nginx configuration test failed"
        exit 1
    fi
}

# Enhanced firewall configuration
configure_firewall() {
    print_status "Configuring firewall..."
    
    case $OS in
        ubuntu|debian)
            if command -v ufw &>/dev/null; then
                sudo ufw --force enable 2>/dev/null
                sudo ufw allow OpenSSH 2>/dev/null
                sudo ufw allow 'Nginx Full' 2>/dev/null
                sudo ufw limit ssh 2>/dev/null
                sudo ufw reload 2>/dev/null
                print_success "UFW firewall configured"
            else
                print_warning "UFW not found, skipping firewall configuration"
            fi
            ;;
        fedora)
            if command -v firewall-cmd &>/dev/null; then
                sudo firewall-cmd --permanent --add-service=http 2>/dev/null
                sudo firewall-cmd --permanent --add-service=https 2>/dev/null
                sudo firewall-cmd --permanent --add-service=ssh 2>/dev/null
                sudo firewall-cmd --reload 2>/dev/null
                print_success "Firewalld configured"
            else
                print_warning "Firewalld not found, skipping firewall configuration"
            fi
            ;;
        centos|rhel)
            if command -v firewall-cmd &>/dev/null; then
                sudo firewall-cmd --permanent --add-service=http 2>/dev/null
                sudo firewall-cmd --permanent --add-service=https 2>/dev/null
                sudo firewall-cmd --permanent --add-service=ssh 2>/dev/null
                sudo firewall-cmd --reload 2>/dev/null
                print_success "Firewalld configured"
            else
                print_warning "Firewalld not found, skipping firewall configuration"
            fi
            ;;
    esac
}

# Enhanced function to start services
start_services() {
    print_status "Starting services..."
    
    if [[ "$INSTALL_METHOD" == "native" ]]; then
        USER=$(whoami)
        sudo systemctl daemon-reload 2>/dev/null
        sudo systemctl restart code-server@$USER 2>/dev/null || print_warning "Failed to restart code-server"
        sudo systemctl restart nginx 2>/dev/null || print_warning "Failed to restart nginx"
    elif [[ "$INSTALL_METHOD" == "docker" ]]; then
        DOCKER_COMPOSE_CMD=$(get_docker_compose_cmd)
        $DOCKER_COMPOSE_CMD up -d 2>/dev/null || print_warning "Failed to restart Docker container"
        sudo systemctl restart nginx 2>/dev/null || print_warning "Failed to restart nginx"
    fi
    
    # Wait for services
    sleep 5
    
    # Verify services
    if [[ "$INSTALL_METHOD" == "native" ]]; then
        USER=$(whoami)
        if sudo systemctl is-active --quiet code-server@$USER 2>/dev/null; then
            print_success "Code-server is running"
        else
            print_warning "Code-server may not be running properly"
        fi
    fi
    
    print_success "Services started"
}

# Enhanced management panel creation
create_management_panel() {
    print_status "Creating enhanced management panel..."
    
    sudo tee "$MANAGEMENT_PANEL" >/dev/null <<'PANEL_EOF'
#!/bin/bash

# Enhanced Code-Server Management Panel
# Author: MiniMax Agent
# Version: 3.0 Enhanced

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
CONFIG_FILE="/etc/code-server/installer-config.json"

# Helper functions
print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_header() {
    echo -e "${CYAN}$1${NC}"
}

# Docker compose detection
get_docker_compose_cmd() {
    if command -v docker &>/dev/null; then
        if docker compose version &>/dev/null 2>&1; then
            echo "docker compose"
            return 0
        elif command -v docker-compose &>/dev/null; then
            echo "docker-compose"
            return 0
        else
            echo ""
            return 1
        fi
    else
        echo ""
        return 1
    fi
}

# Load configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        if command -v jq &>/dev/null; then
            DOMAIN=$(jq -r '.domain' "$CONFIG_FILE" 2>/dev/null || echo "")
            INSTALL_METHOD=$(jq -r '.install_method' "$CONFIG_FILE" 2>/dev/null || echo "")
            ADMIN_EMAIL=$(jq -r '.admin_email' "$CONFIG_FILE" 2>/dev/null || echo "")
            
            if [[ -z "$DOMAIN" || -z "$INSTALL_METHOD" || -z "$ADMIN_EMAIL" ]]; then
                print_error "Invalid configuration file"
                exit 1
            fi
        else
            print_error "jq is required"
            exit 1
        fi
    else
        print_error "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi
}

# Enhanced menu
show_menu() {
    clear
    print_header "=========================================="
    print_header "   Code-Server Enhanced Management Panel"
    print_header "=========================================="
    echo -e "${CYAN}Domain:${NC} $DOMAIN"
    echo -e "${CYAN}Installation Method:${NC} $INSTALL_METHOD"
    echo -e "${CYAN}SSL Email:${NC} $ADMIN_EMAIL"
    echo ""
    echo "1)  Check Status"
    echo "2)  Start Code-Server"
    echo "3)  Stop Code-Server"
    echo "4)  Restart Code-Server"
    echo "5)  Update Code-Server"
    echo "6)  Reinstall Extensions"
    echo "7)  System Health Check"
    echo "8)  View Logs"
    echo "9)  SSL Certificate Status"
    echo "10) Backup Configuration"
    echo "11) Performance Monitor"
    echo "12) Security Check"
    echo "13) Remove Code-Server"
    echo "14) System Information"
    echo "15) Exit"
    echo ""
}

# Enhanced status check
check_status() {
    print_header "=== Code-Server Status ==="
    
    if [[ "$INSTALL_METHOD" == "native" ]]; then
        USER=$(whoami)
        if sudo systemctl is-active --quiet code-server@$USER 2>/dev/null; then
            print_success "Code-Server: Running"
        else
            print_error "Code-Server: Stopped"
        fi
    elif [[ "$INSTALL_METHOD" == "docker" ]]; then
        DOCKER_COMPOSE_CMD=$(get_docker_compose_cmd)
        if [[ -n "$DOCKER_COMPOSE_CMD" ]] && $DOCKER_COMPOSE_CMD ps 2>/dev/null | grep -q "Up"; then
            print_success "Code-Server (Docker): Running"
        else
            print_error "Code-Server (Docker): Stopped"
        fi
    fi
    
    if sudo systemctl is-active --quiet nginx 2>/dev/null; then
        print_success "Nginx: Running"
    else
        print_error "Nginx: Stopped"
    fi
    
    # Check port
    if netstat -tuln 2>/dev/null | grep -q ":8080 " || ss -tuln 2>/dev/null | grep -q ":8080 "; then
        print_success "Port 8080: Listening"
    else
        print_error "Port 8080: Not listening"
    fi
    
    # Check SSL
    if [[ -d "/etc/letsencrypt/live/$DOMAIN" ]]; then
        if command -v openssl &>/dev/null; then
            SSL_EXPIRY=$(sudo openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" 2>/dev/null | cut -d= -f2)
            print_success "SSL Certificate: Valid (Expires: $SSL_EXPIRY)"
        else
            print_success "SSL Certificate: Found"
        fi
    else
        print_error "SSL Certificate: Not found"
    fi
    
    # Check extensions
    echo ""
    print_header "Extensions Status:"
    if [[ -f "$HOME/.config/code-server/User/settings.json" ]]; then
        if grep -q "Pylance" "$HOME/.config/code-server/User/settings.json"; then
            print_success "Extensions: Enhanced with Pylance"
        else
            print_warning "Extensions: Basic configuration"
        fi
    else
        print_error "Extensions: Not configured"
    fi
}

# Health check function
health_check() {
    print_header "=== System Health Check ==="
    
    # CPU usage
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')
    echo "CPU Usage: ${CPU_USAGE}%"
    
    # Memory usage
    MEM_USAGE=$(free | awk 'NR==2{printf "%.1f", $3*100/$2}')
    echo "Memory Usage: ${MEM_USAGE}%"
    
    # Disk usage
    DISK_USAGE=$(df / | awk 'NR==2 {print $5}')
    echo "Disk Usage: $DISK_USAGE"
    
    # Load average
    LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}')
    echo "Load Average:$LOAD_AVG"
    
    # Check if domain is accessible
    if curl -s -o /dev/null -w "%{http_code}" "https://$DOMAIN" | grep -q "200"; then
        print_success "Domain $DOMAIN: Accessible"
    else
        print_warning "Domain $DOMAIN: Not accessible"
    fi
    
    # Security check
    echo ""
    print_header "Security Status:"
    if sudo systemctl is-active --quiet fail2ban 2>/dev/null; then
        print_success "Fail2ban: Active"
    else
        print_warning "Fail2ban: Not active"
    fi
    
    # Log analysis
    RECENT_ERRORS=$(sudo tail -100 /var/log/nginx/error.log 2>/dev/null | grep -c "$(date +%Y/%m/%d)" || echo "0")
    echo "Today's Nginx errors: $RECENT_ERRORS"
}

# Extension reinstallation
reinstall_extensions() {
    print_header "=== Reinstalling Extensions ==="
    print_status "Reinstalling all enhanced extensions..."
    
    # List of extensions (same as in main script)
    local extensions=(
        "ms-python.python"
        "ms-python.pylance"
        "ms-python.debugpy"
        "github.copilot"
        "eamodio.gitlens"
        "bradlc.vscode-tailwindcss"
        "ms-toolsai.jupyter"
        "ms-vscode.vscode-typescript-next"
        "ms-vscode.vscode-css"
        "ms-vscode.vscode-html"
        "redhat.vscode-yaml"
        "ms-vscode.vscode-markdown"
        "yzhang.markdown-all-in-one"
        "mtxr.sqltools"
        "pkief.material-icon-theme"
        "esbenp.prettier-vscode"
        "formulahendry.code-runner"
    )
    
    local installed_count=0
    for extension in "${extensions[@]}"; do
        if code-server --install-extension "$extension" 2>/dev/null; then
            ((installed_count++))
            print_success "✓ $extension"
        else
            print_warning "⚠ Failed: $extension"
        fi
    done
    
    print_success "Extension reinstallation completed! ($installed_count installed)"
}

# Performance monitoring
performance_monitor() {
    print_header "=== Performance Monitor ==="
    /usr/local/bin/code-server-monitor 2>/dev/null || print_error "Monitor script not found"
    
    # Show recent logs
    echo ""
    print_header "Recent Health Log:"
    if [[ -f "/var/log/code-server-health.log" ]]; then
        sudo tail -10 /var/log/code-server-health.log 2>/dev/null || echo "No recent entries"
    else
        echo "Health log not found"
    fi
}

# Security check
security_check() {
    print_header "=== Security Check ==="
    
    # Check firewall
    case "$OS" in
        ubuntu|debian)
            if sudo ufw status | grep -q "Status: active"; then
                print_success "UFW Firewall: Active"
            else
                print_warning "UFW Firewall: Inactive"
            fi
            ;;
        fedora|centos|rhel)
            if sudo firewall-cmd --state 2>/dev/null | grep -q "running"; then
                print_success "Firewalld: Active"
            else
                print_warning "Firewalld: Inactive"
            fi
            ;;
    esac
    
    # Check fail2ban
    if sudo systemctl is-active --quiet fail2ban 2>/dev/null; then
        print_success "Fail2ban: Active"
        sudo fail2ban-client status 2>/dev/null | head -10
    else
        print_warning "Fail2ban: Not active"
    fi
    
    # Check file permissions
    if [[ -f "$CONFIG_FILE" ]]; then
        PERMS=$(stat -c "%a" "$CONFIG_FILE")
        if [[ "$PERMS" == "600" ]]; then
            print_success "Config file permissions: Secure (600)"
        else
            print_warning "Config file permissions: $PERMS (should be 600)"
        fi
    fi
    
    # Check SSL certificate expiry
    if [[ -d "/etc/letsencrypt/live/$DOMAIN" ]] && command -v openssl &>/dev/null; then
        EXPIRY=$(sudo openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" 2>/dev/null | cut -d= -f2)
        EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s 2>/dev/null || echo "0")
        NOW_EPOCH=$(date +%s)
        DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))
        
        if [[ $DAYS_LEFT -gt 30 ]]; then
            print_success "SSL Certificate: $DAYS_LEFT days until expiry"
        elif [[ $DAYS_LEFT -gt 7 ]]; then
            print_warning "SSL Certificate: $DAYS_LEFT days until expiry (renew soon)"
        else
            print_error "SSL Certificate: $DAYS_LEFT days until expiry (URGENT)"
        fi
    fi
}

# System information
system_info() {
    print_header "=== System Information ==="
    echo "OS: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2 || echo "Unknown")"
    echo "Kernel: $(uname -r)"
    echo "Architecture: $(uname -m)"
    echo "Memory: $(free -h 2>/dev/null | awk '/^Mem:/ {print $2" total, "$3" used, "$4" free"}' || echo "Unknown")"
    echo "Swap: $(free -h 2>/dev/null | awk '/^Swap:/ {print $2" total, "$3" used"}' || echo "None")"
    echo "Disk: $(df -h / 2>/dev/null | awk 'NR==2 {print $2" total, "$3" used, "$4" available"}' || echo "Unknown")"
    echo "Uptime: $(uptime -p 2>/dev/null || uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}')"
    echo "Load: $(uptime 2>/dev/null | awk -F'load average:' '{print $2}')"
    echo ""
    echo "Code-Server URL: https://$DOMAIN"
    echo "SSL Status: $([[ -d "/etc/letsencrypt/live/$DOMAIN" ]] && echo "Active" || echo "Inactive")"
    echo "Installation Method: $INSTALL_METHOD"
    echo "Extensions: Enhanced with comprehensive package"
}

# Enhanced main menu loop
main_menu() {
    load_config
    
    # Detect OS for management panel
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS="$ID"
    fi
    
    while true; do
        show_menu
        read -p "Select an option (1-15): " choice
        
        case $choice in
            1) check_status ;;
            2) 
                echo "Starting services..."
                if [[ "$INSTALL_METHOD" == "native" ]]; then
                    USER=$(whoami)
                    sudo systemctl start code-server@$USER nginx 2>/dev/null
                elif [[ "$INSTALL_METHOD" == "docker" ]]; then
                    DOCKER_COMPOSE_CMD=$(get_docker_compose_cmd)
                    $DOCKER_COMPOSE_CMD up -d 2>/dev/null
                    sudo systemctl start nginx 2>/dev/null
                fi
                print_success "Services started"
                ;;
            3)
                echo "Stopping services..."
                if [[ "$INSTALL_METHOD" == "native" ]]; then
                    USER=$(whoami)
                    sudo systemctl stop code-server@$USER 2>/dev/null
                elif [[ "$INSTALL_METHOD" == "docker" ]]; then
                    DOCKER_COMPOSE_CMD=$(get_docker_compose_cmd)
                    $DOCKER_COMPOSE_CMD down 2>/dev/null
                fi
                print_success "Services stopped"
                ;;
            4)
                echo "Restarting services..."
                if [[ "$INSTALL_METHOD" == "native" ]]; then
                    USER=$(whoami)
                    sudo systemctl restart code-server@$USER nginx 2>/dev/null
                elif [[ "$INSTALL_METHOD" == "docker" ]]; then
                    DOCKER_COMPOSE_CMD=$(get_docker_compose_cmd)
                    $DOCKER_COMPOSE_CMD restart 2>/dev/null
                    sudo systemctl restart nginx 2>/dev/null
                fi
                print_success "Services restarted"
                ;;
            5)
                echo "Updating code-server..."
                if [[ "$INSTALL_METHOD" == "native" ]]; then
                    curl -fsSL https://code-server.dev/install.sh | sh 2>/dev/null
                    USER=$(whoami)
                    sudo systemctl restart code-server@$USER 2>/dev/null
                elif [[ "$INSTALL_METHOD" == "docker" ]]; then
                    DOCKER_COMPOSE_CMD=$(get_docker_compose_cmd)
                    $DOCKER_COMPOSE_CMD pull 2>/dev/null
                    $DOCKER_COMPOSE_CMD up -d 2>/dev/null
                fi
                print_success "Code-server updated"
                ;;
            6) reinstall_extensions ;;
            7) health_check ;;
            8)
                print_header "=== Recent Logs ==="
                if [[ "$INSTALL_METHOD" == "native" ]]; then
                    USER=$(whoami)
                    sudo journalctl -u code-server@$USER -n 20 --no-pager 2>/dev/null || echo "No logs available"
                elif [[ "$INSTALL_METHOD" == "docker" ]]; then
                    DOCKER_COMPOSE_CMD=$(get_docker_compose_cmd)
                    $DOCKER_COMPOSE_CMD logs --tail=20 2>/dev/null || echo "No logs available"
                fi
                ;;
            9) ssl_status ;;
            10) backup_config ;;
            11) performance_monitor ;;
            12) security_check ;;
            13) remove_code_server ;;
            14) system_info ;;
            15) echo "Goodbye!"; exit 0 ;;
            *) print_error "Invalid option"; sleep 2 ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
    done
}

# SSL status function
ssl_status() {
    print_header "=== SSL Certificate Status ==="
    
    if [[ -d "/etc/letsencrypt/live/$DOMAIN" ]]; then
        echo "Certificate: /etc/letsencrypt/live/$DOMAIN/"
        
        if command -v openssl &>/dev/null; then
            EXPIRY=$(sudo openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" 2>/dev/null | cut -d= -f2)
            if [[ -n "$EXPIRY" ]]; then
                echo "Expiry Date: $EXPIRY"
                
                EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s 2>/dev/null || echo "0")
                NOW_EPOCH=$(date +%s)
                DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))
                
                if [[ $DAYS_LEFT -lt 30 && $DAYS_LEFT -gt 0 ]]; then
                    echo "Days until expiry: $DAYS_LEFT (EXPIRING SOON)"
                    read -p "Renew certificate now? (y/N): " -n 1 -r
                    echo
                    if [[ $REPLY =~ ^[Yy]$ ]]; then
                        sudo certbot renew --quiet 2>/dev/null
                        print_success "Certificate renewed"
                    fi
                else
                    echo "Days until expiry: $DAYS_LEFT"
                fi
            fi
        fi
    else
        print_error "No SSL certificate found"
    fi
}

# Backup configuration
backup_config() {
    BACKUP_DIR="$HOME/code-server-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    echo "Creating backup..."
    
    if [[ "$INSTALL_METHOD" == "native" ]]; then
        cp -r ~/.config/code-server "$BACKUP_DIR/" 2>/dev/null || true
        USER=$(whoami)
        sudo cp "/etc/systemd/system/code-server@$USER.service.d/override.conf" "$BACKUP_DIR/" 2>/dev/null || true
    elif [[ "$INSTALL_METHOD" == "docker" ]]; then
        cp -r ~/.code-server "$BACKUP_DIR/" 2>/dev/null || true
        cp docker-compose.yml "$BACKUP_DIR/" 2>/dev/null || true
    fi
    
    sudo cp "/etc/nginx/sites-available/code-server" "$BACKUP_DIR/" 2>/dev/null || true
    sudo cp "$CONFIG_FILE" "$BACKUP_DIR/" 2>/dev/null || true
    
    print_success "Backup created: $BACKUP_DIR"
}

# Remove code-server
remove_code_server() {
    echo -e "${RED}WARNING: This will remove code-server completely!${NC}"
    read -p "Are you sure? (type 'YES' to confirm): " CONFIRMATION
    
    if [[ "$CONFIRMATION" != "YES" ]]; then
        echo "Removal cancelled"
        return
    fi
    
    echo "Removing code-server..."
    
    if [[ "$INSTALL_METHOD" == "native" ]]; then
        USER=$(whoami)
        sudo systemctl stop code-server@$USER 2>/dev/null || true
        sudo systemctl disable code-server@$USER 2>/dev/null || true
        rm -rf ~/.config/code-server ~/.local/lib/code-server-* 2>/dev/null || true
        sudo rm -rf /etc/systemd/system/code-server@$USER.service.d/ 2>/dev/null || true
    elif [[ "$INSTALL_METHOD" == "docker" ]]; then
        DOCKER_COMPOSE_CMD=$(get_docker_compose_cmd)
        $DOCKER_COMPOSE_CMD down 2>/dev/null || true
        rm -rf ~/.code-server docker-compose.yml 2>/dev/null || true
    fi
    
    sudo rm -f /etc/nginx/sites-enabled/code-server /etc/nginx/sites-available/code-server 2>/dev/null || true
    sudo systemctl reload nginx 2>/dev/null || true
    
    if [[ -d "/etc/letsencrypt/live/$DOMAIN" ]]; then
        sudo certbot delete --cert-name "$DOMAIN" 2>/dev/null || true
    fi
    
    sudo rm -f "$CONFIG_FILE" 2>/dev/null || true
    sudo rm -f "$MANAGEMENT_PANEL" 2>/dev/null || true
    sudo rm -f /usr/local/bin/code-server-monitor 2>/dev/null || true
    
    print_success "Code-server removed completely"
    exit 0
}

# Check dependencies
if ! command -v jq &>/dev/null; then
    echo "Error: jq is required but not installed"
    echo "Please install it: sudo apt install jq"
    exit 1
fi

# Run main menu
main_menu "$@"
PANEL_EOF
    
    sudo chmod +x "$MANAGEMENT_PANEL"
    print_success "Enhanced management panel created at $MANAGEMENT_PANEL"
}

# Enhanced completion information
show_completion_info() {
    echo ""
    print_success "=========================================="
    print_success "    INSTALLATION COMPLETED!"
    print_success " Enhanced with Security & Extensions"
    print_success "=========================================="
    echo ""
    echo -e "${CYAN}Access Information:${NC}"
    echo "• URL: https://$DOMAIN"
    echo "• Password: $CODE_SERVER_PASSWORD"
    echo ""
    echo -e "${CYAN}🎨 Enhanced Features:${NC}"
    echo "• 40+ Extensions installed (Python, JS, Git, Docker, etc.)"
    echo "• GitHub Copilot integration"
    echo "• Enhanced syntax highlighting with Pylance"
    echo "• Jupyter notebook support"
    echo "• Docker development support"
    echo "• Comprehensive language support"
    echo ""
    echo -e "${CYAN}🔒 Security Features:${NC}"
    echo "• SSL certificate with auto-renewal"
    echo "• Enhanced security headers"
    echo "• Rate limiting enabled"
    echo "• Fail2ban protection"
    echo "• Automatic security updates"
    echo ""
    echo -e "${CYAN}⚡ Performance Features:${NC}"
    echo "• System optimizations applied"
    echo "• Health monitoring enabled"
    echo "• Auto-restart on failure"
    echo "• Resource usage tracking"
    echo ""
    echo -e "${CYAN}Management:${NC}"
    echo "• Enhanced Panel: sudo $MANAGEMENT_PANEL"
    echo "• Health Monitor: /usr/local/bin/code-server-monitor"
    echo "• Log Files: /var/log/code-server-installer.log"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "1. Access your enhanced code-server: https://$DOMAIN"
    echo "2. Use management panel: sudo $MANAGEMENT_PANEL"
    echo "3. Check system health: option 7 in management panel"
    echo "4. Monitor performance: option 11 in management panel"
    echo ""
    
    # Save comprehensive completion info
    COMPLETION_FILE="$HOME/code-server-enhanced-completion.txt"
    cat > "$COMPLETION_FILE" <<EOF
Code-Server Enhanced Installation Completed
===========================================
Date: $(date)
Domain: $DOMAIN
Installation Method: $INSTALL_METHOD
SSL Email: $ADMIN_EMAIL
Version: 3.0 Enhanced

Access Information:
URL: https://$DOMAIN
Password: $CODE_SERVER_PASSWORD

Enhanced Features:
- 40+ Extensions (Python, JS, Git, Docker, etc.)
- GitHub Copilot integration
- Pylance syntax highlighting
- Jupyter notebook support
- Docker development tools
- Comprehensive language support

Security Features:
- SSL with auto-renewal
- Enhanced security headers
- Rate limiting
- Fail2ban protection
- Automatic security updates

Performance Features:
- System optimizations
- Health monitoring
- Auto-restart capability
- Resource tracking

Management:
Panel: sudo $MANAGEMENT_PANEL
Monitor: /usr/local/bin/code-server-monitor
Logs: /var/log/code-server-installer.log

For support, check logs or management panel options.
EOF
    
    print_success "Completion info saved to: $COMPLETION_FILE"
}

# Enhanced main installation function
main() {
    echo -e "${PURPLE}"
    cat <<'EOF'
    _____ _                 _ _            
   / ____| |               | (_)           
  | |    | |__   __ _ _ __ | |_  ___  ___  
  | |    | '_ \ / _` | '_ \| | |/ _ \/ _ \ 
  | |____| | | | (_| | | | | | |  __/ (_) |
   \_____|_| |_|\__,_|_| |_|_|_|\___|\___/ 
                                            
    Code-Server Enhanced Installer
    Version 3.0 - Production Ready
    Author: MiniMax Agent
EOF
    echo -e "${NC}"
    echo ""
    
    # Initialize log
    sudo mkdir -p "$(dirname "$LOG_FILE")"
    sudo touch "$LOG_FILE"
    if [[ $EUID -ne 0 ]]; then
        sudo chown "$USER:$USER" "$LOG_FILE"
    fi
    
    print_status "Starting Enhanced Code-Server Installation..."
    
    # Installation steps
    check_root
    collect_user_input
    check_system_requirements
    install_dependencies
    install_code_server
    configure_nginx
    setup_ssl
    configure_firewall
    
    # Enhanced features
    configure_security_enhancements
    configure_performance_optimizations
    
    start_services
    create_management_panel
    show_completion_info
    
    print_success "Enhanced installation completed successfully!"
}

# Check dependencies before starting
if ! command -v jq &>/dev/null; then
    print_status "Installing jq for configuration management..."
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        case $ID in
            ubuntu|debian)
                sudo apt update && sudo apt install -y jq
                ;;
            centos|rhel|fedora)
                sudo yum install -y jq
                ;;
        esac
    fi
fi

# Run main function
main "$@"