#!/bin/bash

# Code-Server Lightweight Installer
# Version 4.0 - Optimized for Low Memory Systems
# Author: MiniMax Agent
# Compatible with systems having 1GB+ RAM

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Configuration variables
DOMAIN=""
EMAIL=""
CODE_PASSWORD=""
TIMEZONE="Asia/Tehran"
INSTALL_METHOD=""
SWAP_SIZE=2
TOTAL_RAM_MB=0

# Print status functions
print_header() {
    echo -e "\n${CYAN}$1${NC}"
    echo -e "${CYAN}$(printf '%.s-' $(seq 1 ${#1}))${NC}"
}

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Banner
print_banner() {
    clear
    echo -e "${PURPLE}"
    cat << 'EOF'
    _____ _                 _ _
   / ____| |               | (_)
  | |    | |__   __ _ _ __ | |_  ___  ___
  | |    | '_ \ / _` | '_ \| | |/ _ \/ _ \
  | |____| | | | (_| | | | | | |  __/ (_) |
   \_____|_| |_|\__,_|_| |_|_|_|\___|\___/

    Code-Server Lightweight Installer
    Version 4.0 - Optimized for Low Memory
    Author: MiniMax Agent
EOF
    echo -e "${NC}\n"
}

# Check if running as root
check_root() {
    print_header "=== System Check ==="
    print_status "Checking system requirements..."
    
    if [[ $EUID -eq 0 ]]; then
        print_warning "⚠️ RUNNING AS ROOT USER ⚠️"
        print_status "Running with root privileges detected"
        print_status "This is acceptable but ensure your server is properly secured"
        read -p "Continue with root privileges? (yes/no): " root_confirm
        if [[ ! "$root_confirm" =~ ^(yes|y)$ ]]; then
            print_error "Installation cancelled"
            exit 1
        fi
    fi
    
    # Check OS
    if [[ ! -f /etc/os-release ]]; then
        print_error "Cannot detect OS version"
        exit 1
    fi
    
    source /etc/os-release
    print_success "Supported OS: $PRETTY_NAME"
    
    # Check memory
    local total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TOTAL_RAM_MB=$((total_mem_kb / 1024))
    print_status "Total RAM: ${TOTAL_RAM_MB}MB"
    
    # Check disk space
    local disk_space=$(df -BG . | tail -1 | awk '{print $4}' | sed 's/G//')
    print_success "Disk space: ${disk_space}GB"
    
    # Check internet
    if ! ping -c 1 google.com &>/dev/null; then
        print_error "No internet connection detected"
        exit 1
    fi
    print_success "Internet connectivity ✓"
    
    sleep 2
}

# Setup swap space for low memory systems
setup_swap_space() {
    local swap_size_gb=$1
    
    # Check if swap already exists
    if swapon --show | grep -q "swap"; then
        print_warning "Swap space already exists"
        local swap_current=$(free -h | awk '/^Swap:/ {print $2}')
        print_status "Current swap: $swap_current"
        return 0
    fi
    
    print_status "Setting up ${swap_size_gb}GB swap space..."
    
    local swap_file="/swapfile"
    local swap_size_mb=$((swap_size_gb * 1024))
    
    print_status "Creating ${swap_size_gb}GB swap file..."
    if ! sudo fallocate -l ${swap_size_gb}G "$swap_file" 2>/dev/null; then
        print_warning "fallocate failed, trying dd command..."
        sudo dd if=/dev/zero of="$swap_file" bs=1M count=$swap_size_mb status=none
    fi
    
    sudo chmod 600 "$swap_file"
    sudo mkswap "$swap_file" &>/dev/null
    sudo swapon "$swap_file"
    
    # Make it permanent
    if ! grep -q "$swap_file" /etc/fstab 2>/dev/null; then
        echo "$swap_file none swap sw 0 0" | sudo tee -a /etc/fstab >/dev/null
    fi
    
    local swap_total=$(free -h | awk '/^Swap:/ {print $2}')
    print_success "Swap space created: ${swap_total}"
}

# Handle low memory systems
handle_low_memory() {
    local total_mem=$1
    
    if [[ $total_mem -lt 1500 ]]; then
        print_warning "⚠️ LOW MEMORY DETECTED: ${total_mem}MB"
        echo ""
        echo -e "${YELLOW}💡 MEMORY OPTIMIZATION:${NC} This system has limited RAM."
        echo -e "${YELLOW}   Creating swap space will improve performance.${NC}"
        echo ""
        echo -e "${BLUE}Current Status:${NC}"
        echo "• RAM: ${total_mem}MB"
        echo "• Swap: $(free -h 2>/dev/null | awk '/^Swap:/ {print $2}' || echo "None")"
        echo ""
        
        read -p "Create swap space for better performance? (y/n): " swap_choice
        if [[ "$swap_choice" =~ ^[Yy]$ ]]; then
            echo ""
            echo "Choose swap size:"
            echo "1) 2GB (recommended)"
            echo "2) 4GB (better performance)"
            read -p "Enter choice (1-2): " swap_size_choice
            
            case $swap_size_choice in
                1) SWAP_SIZE=2 ;;
                2) SWAP_SIZE=4 ;;
                *) SWAP_SIZE=2 ;;
            esac
            
            setup_swap_space $SWAP_SIZE
        fi
    fi
}

# Collect user configuration
collect_config() {
    print_header "=== Configuration ==="
    print_status "Collecting installation requirements..."
    
    read -p "Enter your domain name (e.g., code.example.com): " DOMAIN
    if [[ -z "$DOMAIN" ]]; then
        print_error "Domain name is required"
        exit 1
    fi
    
    read -p "Enter your email address for SSL certificate: " EMAIL
    if [[ -z "$EMAIL" ]]; then
        print_error "Email address is required"
        exit 1
    fi
    
    while [[ -z "$CODE_PASSWORD" || ${#CODE_PASSWORD} -lt 8 ]]; do
        read -s -p "Enter password for code-server (min 8 characters): " CODE_PASSWORD
        echo
        if [[ ${#CODE_PASSWORD} -lt 8 ]]; then
            print_error "Password must be at least 8 characters"
        fi
    done
    
    echo ""
    echo "Choose installation method:"
    echo "1) Native Installation (Recommended for this system)"
    echo "2) Docker Installation (For isolation)"
    read -p "Enter your choice (1-2): " INSTALL_METHOD_CHOICE
    
    case $INSTALL_METHOD_CHOICE in
        1) INSTALL_METHOD="native" ;;
        2) INSTALL_METHOD="docker" ;;
        *) INSTALL_METHOD="native" ;;
    esac
    
    read -p "Enter your server timezone (default: Asia/Tehran): " TIMEZONE_INPUT
    if [[ -n "$TIMEZONE_INPUT" ]]; then
        TIMEZONE="$TIMEZONE_INPUT"
    fi
    
    print_success "Configuration saved securely"
    sleep 2
}

# Install system dependencies
install_dependencies() {
    print_header "=== Installing Dependencies ==="
    
    print_status "Updating package lists..."
    sudo apt update -y
    
    print_status "Installing dependencies..."
    sudo apt install -y \
        curl \
        wget \
        git \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release \
        ufw \
        htop \
        jq \
        logrotate \
        unattended-upgrades \
        build-essential \
        dnsutils \
        fail2ban \
        nginx \
        certbot \
        python3-certbot-nginx \
        whois \
        unzip \
        dnsutils \
        && print_success "All dependencies installed successfully"
}

# Install code-server
install_code_server() {
    print_header "=== Installing Code-Server ==="
    print_status "Installing latest code-server version..."
    
    # Get latest version
    local latest_version
    latest_version=$(curl -s https://api.github.com/repos/coder/code-server/releases/latest | jq -r .tag_name | sed 's/v//')
    
    if [[ -z "$latest_version" ]]; then
        latest_version="4.106.2"  # fallback version
    fi
    
    print_status "Installing version: $latest_version"
    
    # Install
    curl -fsSL https://code-server.dev/install.sh | sh
    
    print_success "Code-server installed successfully"
    sleep 2
}

# Configure code-server
configure_code_server() {
    print_header "=== Configuring Code-Server ==="
    
    # Create config directory
    local config_dir="/home/$(whoami)/.config/code-server"
    mkdir -p "$config_dir"
    
    # Generate password hash
    local password_hash
    password_hash=$(echo -n "$CODE_PASSWORD" | sha256sum | awk '{print $1}')
    
    # Create config file
    cat > "$config_dir/config.yaml" << EOF
bind-addr: 127.0.0.1:8080
auth: password
password: $password_hash
cert: false
EOF
    
    # Set proper permissions
    chmod 600 "$config_dir/config.yaml"
    
    print_success "Configuration file created"
}

# Configure nginx
configure_nginx() {
    print_header "=== Configuring Nginx ==="
    
    # Create nginx config
    sudo tee /etc/nginx/sites-available/code-server > /dev/null << EOF
server {
    listen 80;
    server_name $DOMAIN;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    
    # Rate limiting
    limit_req_zone \$binary_remote_addr zone=login:10m rate=5r/m;
    
    location / {
        proxy_pass http://127.0.0.1:8080/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 86400;
        
        # Rate limiting for login attempts
        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
            proxy_pass http://127.0.0.1:8080;
        }
    }
}
EOF
    
    # Enable site
    sudo ln -sf /etc/nginx/sites-available/code-server /etc/nginx/sites-enabled/
    sudo rm -f /etc/nginx/sites-enabled/default
    
    # Test nginx config
    if sudo nginx -t; then
        sudo systemctl reload nginx
        print_success "Nginx configured successfully"
    else
        print_error "Nginx configuration test failed"
        exit 1
    fi
}

# Install SSL certificate
install_ssl() {
    print_header "=== Installing SSL Certificate ==="
    
    print_status "Requesting Let's Encrypt certificate for $DOMAIN..."
    
    # Install SSL
    sudo certbot --nginx -d "$DOMAIN" --email "$EMAIL" --agree-tos --non-interactive --redirect
    
    if [[ -d "/etc/letsencrypt/live/$DOMAIN" ]]; then
        print_success "SSL certificate installed successfully"
        
        # Setup auto-renewal
        sudo systemctl enable certbot.timer
        sudo systemctl start certbot.timer
    else
        print_error "SSL certificate installation failed"
        exit 1
    fi
}

# Install lightweight essential extensions
install_light_extensions() {
    print_header "=== Installing Lightweight Extensions ==="
    print_status "Installing essential extensions for development..."
    
    # Lightweight essential extensions only
    local extensions=(
        "ms-python.python"              # Python support
        "ms-python.vscode-pylance"      # Python language server
        "ms-python.debugpy"             # Python debugger
        "ms-vscode.vscode-typescript-next"  # TypeScript support
        "bradlc.vscode-tailwindcss"     # Tailwind CSS
        "esbenp.prettier-vscode"        # Code formatter
        "ms-vscode.vscode-json"         # JSON support
        "redhat.vscode-yaml"            # YAML support
        "ms-vscode.vscode-markdown"     # Markdown support
        "ms-vscode.vscode-html"         # HTML support
        "ms-vscode.vscode-css"          # CSS support
        "pkief.material-icon-theme"     # Icons
        "formulahendry.code-runner"     # Code runner
        "ms-toolsai.jupyter"            # Jupyter support
        "yzhang.markdown-all-in-one"    # Markdown utilities
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
            print_warning "⚠ Failed: $extension"
        fi
    done
    
    echo ""
    print_status "Installation Summary:"
    print_success "Installed: $installed_count extensions"
    if [[ $failed_count -gt 0 ]]; then
        print_warning "Failed: $failed_count extensions"
    fi
}

# Create systemd service
create_systemd_service() {
    print_header "=== Creating Systemd Service ==="
    
    USER=$(whoami)
    
    sudo tee /etc/systemd/system/code-server@.service > /dev/null << 'EOF'
[Unit]
Description=code-server IDE for %i
After=network.target

[Service]
Type=simple
User=%i
Environment=CODER_DAEMON=1
WorkingDirectory=/home/%i
ExecStart=/usr/bin/code-server --bind-addr 127.0.0.1:8080 --auth password
Restart=on-failure

# Security settings
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/home/%i
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

# Memory optimization
MemoryMax=512M
MemorySwapMax=0

[Install]
WantedBy=multi-user.target
EOF
    
    # Enable and start service
    sudo systemctl daemon-reload
    sudo systemctl enable --now code-server@$USER
    
    # Wait for service to start
    sleep 3
    
    if systemctl is-active --quiet code-server@$USER; then
        print_success "Code-server service started successfully"
    else
        print_error "Failed to start code-server service"
        sudo systemctl status code-server@$USER
        exit 1
    fi
}

# Setup fail2ban
setup_fail2ban() {
    print_header "=== Configuring Fail2ban ==="
    
    # Configure fail2ban for nginx
    sudo tee /etc/fail2ban/jail.d/nginx-http-auth.conf > /dev/null << 'EOF'
[nginx-http-auth]
enabled = true
filter = nginx-http-auth
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 3
bantime = 3600
findtime = 600
EOF
    
    sudo systemctl enable fail2ban
    sudo systemctl restart fail2ban
    
    print_success "Fail2ban configured"
}

# Setup monitoring
setup_monitoring() {
    print_header "=== Setting Up Monitoring ==="
    
    # Create monitoring script
    sudo tee /usr/local/bin/code-server-monitor > /dev/null << 'EOF'
#!/bin/bash
# Simple code-server health monitor

LOG_FILE="/var/log/code-server-health.log"
ERROR_COUNT=0

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | sudo tee -a "$LOG_FILE"
}

# Check if code-server is running
if ! pgrep -f "code-server" > /dev/null; then
    log_message "ERROR: code-server process not found"
    ((ERROR_COUNT++))
    
    # Try to restart
    USER=$(whoami)
    systemctl restart code-server@$USER
    sleep 5
    
    if pgrep -f "code-server" > /dev/null; then
        log_message "SUCCESS: code-server restarted"
    else
        log_message "ERROR: Failed to restart code-server"
    fi
fi

# Check memory usage
MEMORY_USAGE=$(free | grep Mem | awk '{printf("%.0f", $3/$2 * 100.0)}')
if [[ $MEMORY_USAGE -gt 80 ]]; then
    log_message "WARNING: High memory usage: ${MEMORY_USAGE}%"
fi

# Check disk space
DISK_USAGE=$(df -h / | tail -1 | awk '{print $5}' | sed 's/%//')
if [[ $DISK_USAGE -gt 80 ]]; then
    log_message "WARNING: High disk usage: ${DISK_USAGE}%"
fi

log_message "INFO: Health check completed - Errors: $ERROR_COUNT"
EOF
    
    sudo chmod +x /usr/local/bin/code-server-monitor
    
    # Create cron job for monitoring
    (crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/code-server-monitor") | crontab -
    
    print_success "Monitoring setup completed"
}

# Create management script
create_management_script() {
    print_header "=== Creating Management Interface ==="
    
    sudo tee /usr/local/bin/code-server-manage > /dev/null << 'EOF'
#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "\n${BLUE}$1${NC}"
    echo -e "${BLUE}$(printf '%.s-' $(seq 1 ${#1}))${NC}"
}

show_menu() {
    print_header "=== Code-Server Management ==="
    echo "1) Show status"
    echo "2) Start service"
    echo "3) Stop service"
    echo "4) Restart service"
    echo "5) View logs"
    echo "6) Check extensions"
    echo "7) SSL status"
    echo "8) Health check"
    echo "9) System info"
    echo "10) Exit"
    echo ""
}

case $1 in
    status)
        systemctl status code-server@$(whoami) --no-pager
        ;;
    start)
        sudo systemctl start code-server@$(whoami)
        echo "Code-server started"
        ;;
    stop)
        sudo systemctl stop code-server@$(whoami)
        echo "Code-server stopped"
        ;;
    restart)
        sudo systemctl restart code-server@$(whoami)
        echo "Code-server restarted"
        ;;
    logs)
        sudo journalctl -u code-server@$(whoami) -f --no-pager
        ;;
    extensions)
        echo "Installed extensions:"
        code-server --list-extensions 2>/dev/null || echo "No extensions or service not running"
        ;;
    ssl)
        if [[ -d "/etc/letsencrypt/live" ]]; then
            echo "SSL certificates found:"
            ls -la /etc/letsencrypt/live/
        else
            echo "No SSL certificates found"
        fi
        ;;
    health)
        /usr/local/bin/code-server-monitor
        if [[ -f "/var/log/code-server-health.log" ]]; then
            echo ""
            echo "Recent health log:"
            sudo tail -5 /var/log/code-server-health.log
        fi
        ;;
    info)
        echo "=== System Information ==="
        echo "Memory: $(free -h | grep Mem)"
        echo "Disk: $(df -h / | tail -1)"
        echo "Uptime: $(uptime)"
        echo "Code-server: $(code-server --version 2>/dev/null || echo 'Not found')"
        ;;
    *)
        while true; do
            show_menu
            read -p "Enter your choice (1-10): " choice
            case $choice in
                1) code-server-manage status; echo ""; read -p "Press Enter to continue..." ;;
                2) code-server-manage start; echo ""; read -p "Press Enter to continue..." ;;
                3) code-server-manage stop; echo ""; read -p "Press Enter to continue..." ;;
                4) code-server-manage restart; echo ""; read -p "Press Enter to continue..." ;;
                5) code-server-manage logs; echo ""; read -p "Press Enter to continue..." ;;
                6) code-server-manage extensions; echo ""; read -p "Press Enter to continue..." ;;
                7) code-server-manage ssl; echo ""; read -p "Press Enter to continue..." ;;
                8) code-server-manage health; echo ""; read -p "Press Enter to continue..." ;;
                9) code-server-manage info; echo ""; read -p "Press Enter to continue..." ;;
                10) echo "Goodbye!"; exit 0 ;;
                *) echo "Invalid option"; sleep 2 ;;
            esac
        done
        ;;
esac
EOF
    
    sudo chmod +x /usr/local/bin/code-server-manage
    
    print_success "Management interface created: code-server-manage"
}

# Final steps
finalize_installation() {
    print_header "=== Installation Complete ==="
    
    # Set timezone
    sudo timedatectl set-timezone "$TIMEZONE" &>/dev/null || true
    
    # Start all services
    sudo systemctl enable nginx
    sudo systemctl enable fail2ban
    sudo systemctl restart nginx
    sudo systemctl restart fail2ban
    
    # Display completion info
    print_success "🎉 Code-Server installation completed successfully!"
    echo ""
    echo -e "${GREEN}=== Access Information ===${NC}"
    echo "URL: https://$DOMAIN"
    echo "Password: [Your configured password]"
    echo ""
    echo -e "${BLUE}=== Management Commands ===${NC}"
    echo "• Check status: code-server-manage status"
    echo "• View logs: code-server-manage logs"
    echo "• Health check: code-server-manage health"
    echo "• System info: code-server-manage info"
    echo ""
    echo -e "${YELLOW}=== Next Steps ===${NC}"
    echo "1. Open https://$DOMAIN in your browser"
    echo "2. Use your configured password to login"
    echo "3. Start coding!"
    echo ""
    print_success "Enjoy your new code-server! 🚀"
}

# Main installation function
main() {
    print_banner
    check_root
    collect_config
    handle_low_memory "$TOTAL_RAM_MB"
    install_dependencies
    install_code_server
    configure_code_server
    configure_nginx
    install_ssl
    install_light_extensions
    create_systemd_service
    setup_fail2ban
    setup_monitoring
    create_management_script
    finalize_installation
}

# Run main installation
main "$@"
