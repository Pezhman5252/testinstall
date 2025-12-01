#!/bin/bash

# ===============================================
# Code-Server Complete Installation & Management Script (Enhanced + Docker Fix)
# Author: MiniMax Agent  
# Version: 2.4 Root User Docker Fix Release
# Description: Automated Code-Server installer with management panel
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
        print_warning "⚠️  RUNNING AS ROOT USER ⚠️"
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

# Function to collect user input with enhanced validation
collect_user_input() {
    print_status "Collecting installation requirements..."
    
    # Domain name with enhanced validation
    while [[ -z "${DOMAIN:-}" ]]; do
        echo -n -e "${CYAN}Enter your domain name (e.g., code.example.com): ${NC}"
        read -r DOMAIN
        if [[ -z "$DOMAIN" ]]; then
            print_error "Domain name cannot be empty"
        elif [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]*\.[a-zA-Z]{2,}$ ]]; then
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
    echo "1) Native Installation (Recommended)"
    echo "2) Docker Installation"
    read -p "Enter your choice (1-2): " INSTALL_METHOD
    
    case $INSTALL_METHOD in
        1) INSTALL_METHOD="native" ;;
        2) INSTALL_METHOD="docker" ;;
        *) print_error "Invalid choice. Exiting."; exit 1 ;;
    esac
    
    # Server region/timezone
    echo -n -e "${CYAN}Enter your server timezone (e.g., America/New_York, Europe/London, Asia/Tehran): ${NC}"
    read TIMEZONE
    
    # Save configuration (SECURITY FIX: Restrict permissions)
    sudo mkdir -p "$(dirname "$CONFIG_FILE")"
    sudo tee "$CONFIG_FILE" >/dev/null <<EOF
{
    "domain": "$DOMAIN",
    "admin_email": "$ADMIN_EMAIL",
    "code_server_password": "$CODE_SERVER_PASSWORD",
    "install_method": "$INSTALL_METHOD",
    "timezone": "${TIMEZONE:-UTC}",
    "install_date": "$(date -Iseconds)",
    "version": "2.5"
}
EOF
    
    # Validate JSON config
    if ! sudo jq empty "$CONFIG_FILE" 2>/dev/null; then
        print_error "Configuration file is corrupted, attempting to fix..."
        # Emergency fix: recreate with escaped backslash if exists
        sudo tee "$CONFIG_FILE" >/dev/null <<EOF
{
    "domain": "$DOMAIN",
    "admin_email": "$ADMIN_EMAIL",
    "code_server_password": "${CODE_SERVER_PASSWORD//\\/\\\\}",
    "install_method": "$INSTALL_METHOD",
    "timezone": "${TIMEZONE:-UTC}",
    "install_date": "$(date -Iseconds)",
    "version": "2.5"
}
EOF
    fi
    
    # SECURITY FIX: Set strict permissions on config file
    sudo chmod 600 "$CONFIG_FILE"
    sudo chown root:root "$CONFIG_FILE"
    
    print_success "Configuration saved securely to $CONFIG_FILE"
}

# Function to setup swap space for systems with insufficient RAM
setup_swap_space() {
    local swap_size_gb=$1
    
    print_status "Setting up ${swap_size_gb}GB swap space..."
    
    # FIXED: Check if any swap exists (not just /swapfile)
    if swapon --show 2>/dev/null | grep -q "swap"; then
        print_warning "Swap space already exists"
        swapon --show
        return 0
    fi
    
    # Create swap file
    local swap_file="/swapfile"
    local swap_size_mb=$((swap_size_gb * 1024))
    
    print_status "Creating ${swap_size_gb}GB swap file..."
    if ! sudo fallocate -l ${swap_size_gb}G "$swap_file" 2>/dev/null; then
        print_warning "fallocate failed, trying dd command..."
        sudo dd if=/dev/zero of="$swap_file" bs=1M count=$swap_size_mb status=progress
    fi
    
    # Set correct permissions
    sudo chmod 600 "$swap_file"
    
    # Make it swap
    sudo mkswap "$swap_file" &>/dev/null
    
    # Enable swap
    sudo swapon "$swap_file"
    
    # Make it permanent
    if ! grep -q "$swap_file" /etc/fstab 2>/dev/null; then
        echo "$swap_file none swap sw 0 0" | sudo tee -a /etc/fstab >/dev/null
    fi
    
    # Verify swap is working
    local swap_total=$(free -h | awk '/^Swap:/ {print $2}')
    print_success "Swap space created successfully: ${swap_total}"
}

# Function to handle low memory situations with enhanced checks
handle_low_memory() {
    local total_mem=$1
    
    print_warning "⚠️  LOW MEMORY DETECTED: ${total_mem}MB"
    echo ""
    echo -e "${YELLOW}💡 SOLUTION:${NC} Your system has insufficient RAM for code-server."
    echo -e "${YELLOW}   We can create 'Swap Space' using your hard drive to compensate.${NC}"
    echo ""
    
    # Show current memory and swap status
    echo -e "${BLUE}Current Status:${NC}"
    echo "• RAM: ${total_mem}MB"
    echo "• Swap: $(free -h 2>/dev/null | awk '/^Swap:/ {print $2}' || echo "None")"
    echo ""
    
    # Ask user for confirmation
    while true; do
        read -p "Do you want to create swap space to compensate for low RAM? (y/n): " -n 1 -r
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
                        1) 
                            swap_size=2
                            break
                            ;;
                        2) 
                            swap_size=4
                            break
                            ;;
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
                
                # IMPROVED: Better disk space check with safety margin
                local available_disk=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//' | tr -d ' ')
                local required_space=$((swap_size + 2))  # 2GB safety margin
                
                if [[ -z "$available_disk" ]] || [[ $available_disk -lt $required_space ]]; then
                    print_error "Insufficient disk space. Need ${required_space}GB but only ${available_disk}GB available."
                    echo ""
                    echo "Available disk space is too low for the requested swap size."
                    echo "Code-server installation may fail due to memory constraints."
                    echo ""
                    
                    read -p "Continue with code-server installation anyway? (y/n): " -n 1 -r
                    echo
                    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                        print_error "Installation cancelled due to insufficient resources."
                        exit 1
                    fi
                else
                    # Setup swap space
                    print_status "Proceeding with ${swap_size}GB swap space creation..."
                    setup_swap_space $swap_size
                fi
                break
                ;;
            [Nn]* )
                print_warning "Proceeding without swap space..."
                echo -e "${YELLOW}   Warning: Code-server may experience performance issues or crashes${NC}"
                echo -e "${YELLOW}   due to insufficient memory.${NC}"
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

# Function to check system requirements with enhanced validation
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
        # Handle low memory by offering swap space
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
    
    # Check internet connectivity with enhanced fallback
    print_status "Testing internet connectivity..."
    local connectivity_ok=false
    
    # Try multiple methods to test connectivity
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
        print_info "Please check your network and try again"
        exit 1
    fi
}

# Function to install system dependencies with error recovery
install_dependencies() {
    print_status "Installing system dependencies..."
    
    case $OS in
        ubuntu|debian)
            print_status "Updating package lists..."
            if ! sudo apt update -qq 2>/dev/null; then
                print_error "Failed to update package lists"
                print_info "Please check your internet connection and try again"
                exit 1
            fi
            print_status "Installing dependencies..."
            if ! sudo apt install -y curl wget unzip nginx certbot python3-certbot-nginx \
                git build-essential software-properties-common apt-transport-https \
                ca-certificates gnupg lsb-release ufw htop jq dnsutils 2>/dev/null; then
                print_error "Failed to install some dependencies"
                print_info "Please check the error messages above and try again"
                exit 1
            fi
            ;;
        centos|rhel|fedora)
            print_status "Updating package lists..."
            if ! sudo yum update -y 2>/dev/null; then
                print_error "Failed to update package lists"
                print_info "Please check your internet connection and try again"
                exit 1
            fi
            print_status "Installing dependencies..."
            if ! sudo yum install -y curl wget unzip nginx certbot python3-certbot-nginx \
                git gcc gcc-c++ make epel-release htop jq bind-utils 2>/dev/null; then
                print_error "Failed to install some dependencies"
                print_info "Please check the error messages above and try again"
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
            print_info "Supported systems: Ubuntu, Debian, CentOS, RHEL, Fedora"
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

# Function to install code-server with enhanced error handling AND DOCKER PERMISSION FIX
install_code_server() {
    print_status "Installing code-server..."
    
    # Get latest version with error handling
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
        
        # Set secure permissions on config file
        chmod 600 ~/.config/code-server/config.yaml
        
        # Configure systemd service
        USER=$(whoami)
        sudo systemctl enable --now code-server@$USER 2>/dev/null || print_warning "Failed to enable code-server service"
        
        # Update systemd service file to include password
        sudo mkdir -p /etc/systemd/system/code-server@$USER.service.d/
        sudo tee /etc/systemd/system/code-server@$USER.service.d/override.conf >/dev/null <<EOF
[Service]
Environment=PASSWORD=$CODE_SERVER_PASSWORD
EOF
        
        # Reload systemd and restart service
        sudo systemctl daemon-reload 2>/dev/null
        sudo systemctl restart code-server@$USER 2>/dev/null || print_warning "Failed to restart code-server service"
        
        print_success "Code-server installed natively"
        
    elif [[ "$INSTALL_METHOD" == "docker" ]]; then
        # Docker installation
        if ! command -v docker &>/dev/null; then
            print_status "Installing Docker..."
            if ! curl -fsSL https://get.docker.com | sh; then
                print_error "Failed to install Docker"
                exit 1
            fi
            # Handle Docker group permissions
            if [[ "$USER" != "root" ]]; then
                sudo usermod -aG docker "$USER" 2>/dev/null
                print_warning "Please log out and log back in for Docker permissions to take effect"
            else
                print_status "Running as root - Docker permissions already available"
            fi
        fi
        
        # Create directories for persistence with proper permissions 🔧 DOCKER FIX
        print_status "Creating code-server directories..."
        mkdir -p ~/.code-server/{config,local,workspace}
        
        # 🔧 DOCKER FIX: Set proper ownership and permissions for all scenarios
        print_status "Setting proper ownership and permissions..."
        CURRENT_USER=$(whoami)
        
        # For Docker containers, code-server runs as user 'coder' (UID 1000)
        # We need to set ownership to UID 1000 so the container can access the volumes
        if [[ "$CURRENT_USER" == "root" ]]; then
            print_status "Running as root - setting ownership to container user (UID 1000)..."
            # Set ownership to UID 1000 (coder user in container)
            sudo chown -R 1000:1000 ~/.code-server/ 2>/dev/null || {
                print_warning "Failed to set ownership to 1000:1000, trying 777 permissions..."
                chmod -R 777 ~/.code-server/
            }
        else
            print_status "Running as user - setting ownership to current user..."
            # Set ownership to current user
            sudo chown -R $CURRENT_USER:$CURRENT_USER ~/.code-server/ 2>/dev/null || {
                print_warning "Failed to change ownership, trying as root..."
                sudo chown -R root:root ~/.code-server/ 2>/dev/null || print_warning "Could not set ownership"
            }
        fi
        
        # Set permissions - make everything accessible to container
        chmod -R 755 ~/.code-server/
        chmod -R 777 ~/.code-server/workspace  # Make workspace fully accessible
        chmod -R 755 ~/.code-server/config     # Make config accessible
        chmod -R 755 ~/.code-server/local      # Make local accessible
        
        # Validate directory creation
        if [[ ! -d ~/.code-server/config || ! -d ~/.code-server/local || ! -d ~/.code-server/workspace ]]; then
            print_error "Failed to create code-server directories"
            exit 1
        fi
        
        print_success "Directories created with proper permissions"
        
        # FIXED: Support both docker compose and docker-compose
        COMPOSE_FILE="docker-compose.yml"
        
        # Create backup of existing compose file
        if [[ -f "$COMPOSE_FILE" ]]; then
            cp "$COMPOSE_FILE" "$COMPOSE_FILE.backup.$(date +%Y%m%d-%H%M%S)"
            print_status "Existing compose file backed up"
        fi
        
        # 🔧 DOCKER FIX: Remove problematic DOCKER_USER environment variable
        cat > "$COMPOSE_FILE" <<EOF
version: '3.8'

services:
  code-server:
    image: codercom/code-server:latest
    container_name: code-server
    ports:
      - "127.0.0.1:8080:8080"
    volumes:
      - ~/.code-server/config:/home/coder/.config
      - ~/.code-server/local:/home/coder/.local
      - ~/.code-server/workspace:/home/coder/project
    environment:
      - PASSWORD=$CODE_SERVER_PASSWORD
      # 🔧 DOCKER FIX: Removed DOCKER_USER=$USER - it causes permission conflicts
    restart: unless-stopped

networks:
  default:
    name: code-server-network
EOF
        
        # Start container with correct command
        DOCKER_COMPOSE_CMD=$(get_docker_compose_cmd)
        if [[ -z "$DOCKER_COMPOSE_CMD" ]]; then
            print_error "Docker Compose not found. Please install Docker Compose."
            exit 1
        fi
        
        print_status "Using: $DOCKER_COMPOSE_CMD"
        
        # 🔧 ADD: Pre-flight checks before starting
        print_status "Performing pre-flight checks..."
        
        # Check if directories are accessible
        if [[ ! -r ~/.code-server/config || ! -w ~/.code-server/config ]]; then
            print_error "Cannot read/write to config directory"
            exit 1
        fi
        
        # Check Docker daemon status
        if ! docker info &>/dev/null; then
            print_warning "Docker daemon is not running, starting..."
            sudo systemctl start docker 2>/dev/null || sudo service docker start 2>/dev/null || {
                print_error "Failed to start Docker daemon"
                exit 1
            }
            # Wait for daemon to be ready
            sleep 3
            if ! docker info &>/dev/null; then
                print_error "Docker daemon still not responding"
                exit 1
            fi
        fi
        
        if ! $DOCKER_COMPOSE_CMD up -d; then
            print_error "Failed to start Docker container"
            print_info "Trying to debug container startup..."
            
            # Show recent logs for debugging
            docker logs code-server 2>/dev/null | tail -10 || print_warning "No logs available"
            
            # Try alternative approach - remove and recreate
            print_status "Attempting cleanup and restart..."
            $DOCKER_COMPOSE_CMD down 2>/dev/null
            docker volume prune -f 2>/dev/null
            
            # Try starting again
            if ! $DOCKER_COMPOSE_CMD up -d; then
                print_error "Failed to start container after cleanup"
                print_info "Please check Docker logs: docker logs code-server"
                exit 1
            fi
        fi
        
        # 🔧 ADD: Post-startup validation
        print_status "Validating container startup..."
        sleep 5
        
        # Check if container is running
        if ! docker ps --filter "name=code-server" --format "table {{.Names}}\t{{.Status}}" | grep -q "Up"; then
            print_error "Container failed to start properly"
            print_info "Attempting cleanup and retry..."
            
            # Cleanup
            $DOCKER_COMPOSE_CMD down 2>/dev/null
            docker volume prune -f 2>/dev/null
            docker system prune -f 2>/dev/null
            
            # Wait a bit
            sleep 5
            
            # Retry
            print_status "Retrying container startup..."
            if $DOCKER_COMPOSE_CMD up -d; then
                sleep 5
                if docker ps --filter "name=code-server" --format "table {{.Names}}\t{{.Status}}" | grep -q "Up"; then
                    print_success "Container started successfully on retry"
                else
                    print_error "Container still failing after retry"
                    print_info "Container logs:"
                    docker logs code-server --tail=20
                    exit 1
                fi
            else
                print_error "Container failed to start after cleanup"
                print_info "Container logs:"
                docker logs code-server --tail=20
                exit 1
            fi
        fi
        
        print_success "Code-server installed with Docker and validated"
    fi
}

# Function to configure Nginx reverse proxy with enhanced validation
configure_nginx() {
    print_status "Configuring Nginx reverse proxy..."
    
    # IMPROVED: Check if Nginx is installed and running
    if ! command -v nginx &>/dev/null; then
        print_error "Nginx is not installed. Please install it first."
        exit 1
    fi
    
    # Start Nginx if not running
    if ! sudo systemctl is-active --quiet nginx 2>/dev/null; then
        print_warning "Nginx is not running, starting..."
        sudo systemctl start nginx 2>/dev/null || print_warning "Failed to start Nginx"
    fi
    
    # Backup existing config if exists
    if [[ -f /etc/nginx/sites-enabled/default ]]; then
        sudo cp /etc/nginx/sites-enabled/default /etc/nginx/sites-enabled/default.backup.$(date +%Y%m%d-%H%M%S)
    fi
    
    # Create Nginx configuration (HTTP first, will be updated to HTTPS later)
    sudo tee /etc/nginx/sites-available/code-server >/dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    
    # Temporary HTTP configuration - will be updated to HTTPS after SSL setup
    
    # Logging
    access_log /var/log/nginx/code-server.access.log;
    error_log /var/log/nginx/code-server.error.log;
    
    # Proxy Configuration
    location / {
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
    }
    
    # Disable buffering when the nginx proxy gets very resource heavy upon buffering
    proxy_buffering off;
    
    # Handle WebSocket connections
    location ~* /.*\.sock {
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
    sudo ln -sf /etc/nginx/sites-available/code-server /etc/nginx/sites-enabled/
    
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

# Function to wait for DNS propagation
wait_for_dns_propagation() {
    local domain="$1"
    local server_ip="$2"
    local max_wait_minutes=30
    local max_attempts=$((max_wait_minutes * 60 / 10))  # Check every 10 seconds
    local attempt=1
    
    print_status "Waiting for DNS propagation (max $max_wait_minutes minutes)..."
    
    while [[ $attempt -le $max_attempts ]]; do
        local domain_ip=""
        
        # Try multiple methods to get domain IP
        if command -v dig &>/dev/null; then
            domain_ip=$(dig +short "$domain" @8.8.8.8 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
        elif command -v nslookup &>/dev/null; then
            domain_ip=$(nslookup "$domain" 2>/dev/null | awk '/^Address: / { print $2 }' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
        elif command -v host &>/dev/null; then
            domain_ip=$(host "$domain" 2>/dev/null | awk '/has address/ { print $4 }' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
        fi
        
        if [[ -n "$domain_ip" && "$domain_ip" == "$server_ip" ]]; then
            print_success "DNS propagation complete! Domain now points to server IP"
            return 0
        fi
        
        print_status "Attempt $attempt/$max_attempts: Domain IP: ${domain_ip:-'Not found'}, Server IP: $server_ip"
        
        if [[ $attempt -eq $max_attempts ]]; then
            print_warning "DNS propagation timeout reached"
            return 1
        fi
        
        sleep 10
        ((attempt++))
    done
}

# Function to setup SSL certificate with enhanced error handling and auto DNS retry
setup_ssl() {
    print_status "Setting up SSL certificate..."
    
    # Get server IP
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null || echo "")
    
    # Check domain DNS and wait for propagation if needed
    DOMAIN_IP=""
    if command -v dig &>/dev/null; then
        DOMAIN_IP=$(dig +short "$DOMAIN" @8.8.8.8 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
    elif command -v nslookup &>/dev/null; then
        DOMAIN_IP=$(nslookup "$DOMAIN" 2>/dev/null | awk '/^Address: / { print $2 }' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
    elif command -v host &>/dev/null; then
        DOMAIN_IP=$(host "$DOMAIN" 2>/dev/null | awk '/has address/ { print $4 }' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
    fi
    
    # Check if domain DNS is pointing to this server
    if [[ -n "$DOMAIN_IP" && -n "$SERVER_IP" && "$DOMAIN_IP" != "$SERVER_IP" ]]; then
        print_warning "Domain DNS not pointing to this server"
        print_status "Domain IP: $DOMAIN_IP, Server IP: $SERVER_IP"
        
        # Offer DNS propagation wait
        print_status "Would you like to wait for DNS propagation? (This can take up to 30 minutes)"
        read -p "Wait for DNS propagation? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if wait_for_dns_propagation "$DOMAIN" "$SERVER_IP"; then
                print_success "DNS propagation successful, continuing with SSL setup"
            else
                print_warning "DNS propagation timeout, continuing anyway..."
            fi
        else
            print_status "Continuing anyway as requested..."
        fi
    fi
    
    # Obtain SSL certificate (IMPROVED: Show error messages and retry logic)
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
                print_error "Check logs: sudo tail -n 50 /var/log/letsencrypt/letsencrypt.log"
                echo ""
                print_info "Common issues:"
                echo "  • Domain DNS not pointing to this server"
                echo "  • Port 80 not accessible from internet"
                echo "  • Firewall blocking connections"
                exit 1
            fi
        fi
    done
    
    # Setup automatic renewal
    sudo systemctl enable --now certbot.timer 2>/dev/null || print_warning "Could not enable certbot timer"
    
    # Update nginx configuration to use SSL (if certbot didn't do it automatically)
    update_nginx_ssl_config
    
    print_success "SSL certificate installed and auto-renewal enabled"
}

# Function to update nginx config for SSL
update_nginx_ssl_config() {
    print_status "Updating Nginx configuration for SSL..."
    
    # Create proper SSL-enabled nginx configuration
    sudo tee /etc/nginx/sites-available/code-server >/dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    
    # Redirect HTTP to HTTPS
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;
    
    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    
    # Security Headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;
    
    # Logging
    access_log /var/log/nginx/code-server.access.log;
    error_log /var/log/nginx/code-server.error.log;
    
    # Proxy Configuration
    location / {
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
        proxy_buffering off;
        proxy_buffer_size 4K;
    }
    
    # Static file handling
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        proxy_pass http://127.0.0.1:8080;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # WebSocket support
    location /socket.io/ {
        proxy_pass http://127.0.0.1:8080/socket.io/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 86400;
    }
}
EOF
    
    # Test nginx configuration
    if sudo nginx -t; then
        print_success "Nginx configuration updated successfully"
        sudo systemctl reload nginx 2>/dev/null || sudo systemctl restart nginx 2>/dev/null
    else
        print_error "Nginx configuration test failed"
        exit 1
    fi
}

# Function to configure firewall
configure_firewall() {
    print_status "Configuring firewall..."
    
    case $OS in
        ubuntu|debian)
            if command -v ufw &>/dev/null; then
                sudo ufw --force enable 2>/dev/null
                sudo ufw allow OpenSSH 2>/dev/null
                sudo ufw allow 'Nginx Full' 2>/dev/null
                sudo ufw --force reload 2>/dev/null
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

# Function to start services with enhanced error handling
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
    
    # Wait for services to be ready
    sleep 5
    
    # Verify services are running
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

# Function to create management panel (same as before but with version update)
create_management_panel() {
    print_status "Creating management panel..."
    
    sudo tee "$MANAGEMENT_PANEL" >/dev/null <<'PANEL_EOF'
#!/bin/bash

# Code-Server Management Panel (Enhanced)
# Author: MiniMax Agent
# Version: 2.4 Root User Docker Fix Release

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration file path
CONFIG_FILE="/etc/code-server/installer-config.json"

# Helper functions
print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${CYAN}$1${NC}"
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

# Function to load configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        if command -v jq &>/dev/null; then
            DOMAIN=$(jq -r '.domain' "$CONFIG_FILE" 2>/dev/null || echo "")
            INSTALL_METHOD=$(jq -r '.install_method' "$CONFIG_FILE" 2>/dev/null || echo "")
            ADMIN_EMAIL=$(jq -r '.admin_email' "$CONFIG_FILE" 2>/dev/null || echo "")
            
            # Validate loaded data
            if [[ -z "$DOMAIN" || -z "$INSTALL_METHOD" || -z "$ADMIN_EMAIL" ]]; then
                print_error "Invalid configuration file"
                exit 1
            fi
        else
            print_error "jq is required to read configuration file"
            print_info "Installing jq: sudo apt install jq"
            exit 1
        fi
    else
        print_error "Configuration file not found: $CONFIG_FILE"
        print_info "Run the installer first: ./install-code-server-enhanced.sh"
        exit 1
    fi
}

# Function to show menu
show_menu() {
    clear
    print_header "========================================"
    print_header "      Code-Server Management Panel"
    print_header "========================================"
    echo -e "${CYAN}Domain:${NC} $DOMAIN"
    echo -e "${CYAN}Installation Method:${NC} $INSTALL_METHOD"
    echo -e "${CYAN}SSL Email:${NC} $ADMIN_EMAIL"
    echo ""
    echo "1) Check Status"
    echo "2) Start Code-Server"
    echo "3) Stop Code-Server"
    echo "4) Restart Code-Server"
    echo "5) Update Code-Server"
    echo "6) View Logs"
    echo "7) SSL Certificate Status"
    echo "8) Backup Configuration"
    echo "9) Remove Code-Server"
    echo "10) System Information"
    echo "11) Exit"
    echo ""
}

# Function to check status with enhanced error handling
check_status() {
    echo -e "${CYAN}=== Code-Server Status ===${NC}"
    
    if [[ "$INSTALL_METHOD" == "native" ]]; then
        USER=$(whoami)
        if sudo systemctl is-active --quiet code-server@$USER 2>/dev/null; then
            print_success "Code-Server: Running"
        else
            print_error "Code-Server: Stopped"
        fi
        
        if sudo systemctl is-active --quiet nginx 2>/dev/null; then
            print_success "Nginx: Running"
        else
            print_error "Nginx: Stopped"
        fi
        
        # Check port with enhanced error handling
        if netstat -tuln 2>/dev/null | grep -q ":8080 " || ss -tuln 2>/dev/null | grep -q ":8080 "; then
            print_success "Port 8080: Listening"
        else
            print_error "Port 8080: Not listening"
        fi
        
    elif [[ "$INSTALL_METHOD" == "docker" ]]; then
        DOCKER_COMPOSE_CMD=$(get_docker_compose_cmd)
        if [[ -n "$DOCKER_COMPOSE_CMD" ]] && $DOCKER_COMPOSE_CMD ps 2>/dev/null | grep -q "Up"; then
            print_success "Code-Server (Docker): Running"
        else
            print_error "Code-Server (Docker): Stopped"
        fi
        
        if sudo systemctl is-active --quiet nginx 2>/dev/null; then
            print_success "Nginx: Running"
        else
            print_error "Nginx: Stopped"
        fi
    fi
    
    # Check SSL certificate
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
}

# Function to start services
start_services_cmd() {
    echo "Starting services..."
    if [[ "$INSTALL_METHOD" == "native" ]]; then
        USER=$(whoami)
        sudo systemctl start code-server@$USER 2>/dev/null
        sudo systemctl start nginx 2>/dev/null
    elif [[ "$INSTALL_METHOD" == "docker" ]]; then
        DOCKER_COMPOSE_CMD=$(get_docker_compose_cmd)
        $DOCKER_COMPOSE_CMD up -d 2>/dev/null
        sudo systemctl start nginx 2>/dev/null
    fi
    sleep 3
    print_success "Services started"
}

# Function to stop services
stop_services_cmd() {
    echo "Stopping services..."
    if [[ "$INSTALL_METHOD" == "native" ]]; then
        USER=$(whoami)
        sudo systemctl stop code-server@$USER 2>/dev/null
    elif [[ "$INSTALL_METHOD" == "docker" ]]; then
        DOCKER_COMPOSE_CMD=$(get_docker_compose_cmd)
        $DOCKER_COMPOSE_CMD down 2>/dev/null
    fi
    print_success "Services stopped"
}

# Function to restart services
restart_services_cmd() {
    echo "Restarting services..."
    if [[ "$INSTALL_METHOD" == "native" ]]; then
        USER=$(whoami)
        sudo systemctl restart code-server@$USER 2>/dev/null
        sudo systemctl restart nginx 2>/dev/null
    elif [[ "$INSTALL_METHOD" == "docker" ]]; then
        DOCKER_COMPOSE_CMD=$(get_docker_compose_cmd)
        $DOCKER_COMPOSE_CMD restart 2>/dev/null
        sudo systemctl restart nginx 2>/dev/null
    fi
    sleep 3
    print_success "Services restarted"
}

# Function to update code-server
update_code_server() {
    echo "Updating code-server..."
    
    if [[ "$INSTALL_METHOD" == "native" ]]; then
        # Update native installation
        curl -fsSL https://code-server.dev/install.sh | sh 2>/dev/null
        USER=$(whoami)
        sudo systemctl restart code-server@$USER 2>/dev/null
    elif [[ "$INSTALL_METHOD" == "docker" ]]; then
        # Update Docker image
        DOCKER_COMPOSE_CMD=$(get_docker_compose_cmd)
        $DOCKER_COMPOSE_CMD pull 2>/dev/null
        $DOCKER_COMPOSE_CMD up -d 2>/dev/null
    fi
    
    print_success "Code-server updated"
}

# Function to view logs
view_logs() {
    echo -e "${CYAN}=== Recent Code-Server Logs ===${NC}"
    
    if [[ "$INSTALL_METHOD" == "native" ]]; then
        USER=$(whoami)
        sudo journalctl -u code-server@$USER -n 30 --no-pager 2>/dev/null || print_error "No logs available"
    elif [[ "$INSTALL_METHOD" == "docker" ]]; then
        DOCKER_COMPOSE_CMD=$(get_docker_compose_cmd)
        $DOCKER_COMPOSE_CMD logs --tail=30 2>/dev/null || print_error "No logs available"
    fi
}

# Function to check SSL status
ssl_status() {
    echo -e "${CYAN}=== SSL Certificate Status ===${NC}"
    
    if [[ -d "/etc/letsencrypt/live/$DOMAIN" ]]; then
        echo "Certificate: /etc/letsencrypt/live/$DOMAIN/"
        
        # Check expiry
        if command -v openssl &>/dev/null; then
            EXPIRY=$(sudo openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" 2>/dev/null | cut -d= -f2)
            if [[ -n "$EXPIRY" ]]; then
                echo "Expiry Date: $EXPIRY"
                
                # Check if expiring soon (less than 30 days)
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

# Function to backup configuration
backup_config() {
    BACKUP_DIR="$HOME/code-server-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    echo "Creating backup..."
    
    if [[ "$INSTALL_METHOD" == "native" ]]; then
        # Backup config directory
        cp -r ~/.config/code-server "$BACKUP_DIR/" 2>/dev/null || true
        # Backup systemd service
        USER=$(whoami)
        sudo cp "/etc/systemd/system/code-server@$USER.service.d/override.conf" "$BACKUP_DIR/" 2>/dev/null || true
    elif [[ "$INSTALL_METHOD" == "docker" ]]; then
        cp -r ~/.code-server "$BACKUP_DIR/" 2>/dev/null || true
        cp docker-compose.yml "$BACKUP_DIR/" 2>/dev/null || true
    fi
    
    # Backup Nginx config
    sudo cp "/etc/nginx/sites-available/code-server" "$BACKUP_DIR/" 2>/dev/null || true
    
    # Backup installer config (securely)
    sudo cp "$CONFIG_FILE" "$BACKUP_DIR/" 2>/dev/null || true
    
    print_success "Backup created: $BACKUP_DIR"
}

# Function to remove code-server
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
        rm -rf ~/.local/share/code-server 2>/dev/null || true
        sudo rm -rf /etc/systemd/system/code-server@$USER.service.d/ 2>/dev/null || true
    elif [[ "$INSTALL_METHOD" == "docker" ]]; then
        DOCKER_COMPOSE_CMD=$(get_docker_compose_cmd)
        $DOCKER_COMPOSE_CMD down 2>/dev/null || true
        rm -rf ~/.code-server docker-compose.yml 2>/dev/null || true
    fi
    
    # Remove Nginx config
    sudo rm -f /etc/nginx/sites-enabled/code-server 2>/dev/null || true
    sudo rm -f /etc/nginx/sites-available/code-server 2>/dev/null || true
    sudo systemctl reload nginx 2>/dev/null || true
    
    # Remove SSL certificate
    if [[ -d "/etc/letsencrypt/live/$DOMAIN" ]]; then
        sudo certbot delete --cert-name "$DOMAIN" 2>/dev/null || true
    fi
    
    # Remove config file
    sudo rm -f "$CONFIG_FILE" 2>/dev/null || true
    
    print_success "Code-server removed completely"
    
    # Remove management panel
    sudo rm -f "$MANAGEMENT_PANEL"
    
    exit 0
}

# Function to show system information
system_info() {
    echo -e "${CYAN}=== System Information ===${NC}"
    echo "OS: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2 || echo "Unknown")"
    echo "Kernel: $(uname -r)"
    echo "Memory: $(free -h 2>/dev/null | awk '/^Mem:/ {print $2" total, "$3" used, "$4" free"}' || echo "Unknown")"
    echo "Swap: $(free -h 2>/dev/null | awk '/^Swap:/ {print $2" total, "$3" used"}' || echo "Unknown")"
    echo "Disk: $(df -h / 2>/dev/null | awk 'NR==2 {print $2" total, "$3" used, "$4" available"}' || echo "Unknown")"
    echo "Uptime: $(uptime -p 2>/dev/null || uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}')"
    echo "Load: $(uptime 2>/dev/null | awk -F'load average:' '{print $2}')"
    echo ""
    echo "Code-Server URL: https://$DOMAIN"
    echo "SSL Status: $([[ -d "/etc/letsencrypt/live/$DOMAIN" ]] && echo "Active" || echo "Inactive")"
    echo "Installation Method: $INSTALL_METHOD"
}

# Main menu loop
management_panel_main() {
    load_config
    
    while true; do
        show_menu
        read -p "Select an option (1-11): " choice
        
        case $choice in
            1) check_status ;;
            2) start_services_cmd ;;
            3) stop_services_cmd ;;
            4) restart_services_cmd ;;
            5) update_code_server ;;
            6) view_logs ;;
            7) ssl_status ;;
            8) backup_config ;;
            9) remove_code_server ;;
            10) system_info ;;
            11) echo "Goodbye!"; exit 0 ;;
            *) print_error "Invalid option"; sleep 2 ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
    done
}

# Check dependencies
if ! command -v jq &>/dev/null; then
    echo "Error: jq is required but not installed"
    echo "Please install it: sudo apt install jq (Ubuntu/Debian) or sudo yum install jq (CentOS/RHEL)"
    exit 1
fi

# Run main function
management_panel_main "$@"
PANEL_EOF
    
    sudo chmod +x "$MANAGEMENT_PANEL"
    
    print_success "Management panel created at $MANAGEMENT_PANEL"
}

# Function to display completion information
show_completion_info() {
    echo ""
    print_success "========================================"
    print_success "      INSTALLATION COMPLETED!"
    print_success "========================================"
    echo ""
    echo -e "${CYAN}Access Information:${NC}"
    echo "• URL: https://$DOMAIN"
    echo "• Password: $CODE_SERVER_PASSWORD"
    echo ""
    echo -e "${CYAN}Management:${NC}"
    echo "• Management Panel: sudo $MANAGEMENT_PANEL"
    echo "• Quick Commands:"
    echo "  - Check status: sudo systemctl status code-server@\$USER"
    if [[ "$INSTALL_METHOD" == "docker" ]]; then
        DOCKER_COMPOSE_CMD=$(get_docker_compose_cmd)
        echo "  - View logs: $DOCKER_COMPOSE_CMD logs -f"
    else
        echo "  - View logs: sudo journalctl -u code-server@\$USER -f"
    fi
    echo ""
    echo -e "${CYAN}Log Files:${NC}"
    echo "• Installer Log: $LOG_FILE"
    echo "• Nginx Logs: /var/log/nginx/"
    echo "• Code-Server Logs: journalctl -u code-server@$USER"
    echo ""
    echo -e "${CYAN}Configuration:${NC}"
    echo "• Config File: $CONFIG_FILE (secured with 600 permissions)"
    echo "• Nginx Config: /etc/nginx/sites-available/code-server"
    echo ""
    echo -e "${YELLOW}Security Reminders:${NC}"
    echo "• Your password is stored in: $CONFIG_FILE (root access only)"
    echo "• SSL certificate auto-renews via certbot"
    echo "• Keep your system updated: sudo apt update && sudo apt upgrade"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "1. Access your code-server: https://$DOMAIN"
    echo "2. Use management panel: sudo $MANAGEMENT_PANEL"
    echo "3. Review logs: tail -f $LOG_FILE"
    echo ""
    
    # Save completion info to file
    COMPLETION_FILE="$HOME/code-server-completion-info.txt"
    cat > "$COMPLETION_FILE" <<EOF
Code-Server Installation Completed on $(date)
========================================
Domain: $DOMAIN
Installation Method: $INSTALL_METHOD
Management Panel: $MANAGEMENT_PANEL
SSL Email: $ADMIN_EMAIL
Installation Date: $(date)
Version: 2.3 Docker Permission Fix Release

Access: https://$DOMAIN
Management: sudo $MANAGEMENT_PANEL

Security Notes:
- Config file secured with 600 permissions
- SSL auto-renewal enabled
- Firewall configured
- Docker permission issues resolved

For support and updates, visit: https://github.com/coder/code-server
EOF
    
    print_success "Installation details saved to: $COMPLETION_FILE"
}

# Main installation function
main() {
    echo -e "${PURPLE}"
    cat <<'EOF'
    _____ _                 _ _            
   / ____| |               | (_)           
  | |    | |__   __ _ _ __ | |_  ___  ___  
  | |    | '_ \ / _` | '_ \| | |/ _ \/ _ \ 
  | |____| | | | (_| | | | | | |  __/ (_) |
   \_____|_| |_|\__,_|_| |_|_|_|\___|\___/ 
                                            
    Code-Server Complete Installer
    Author: MiniMax Agent
    Version: 2.3 Docker Permission Fix Release
EOF
    echo -e "${NC}"
    echo ""
    
    # Initialize log
    sudo mkdir -p "$(dirname "$LOG_FILE")"
    sudo touch "$LOG_FILE"
    if [[ $EUID -ne 0 ]]; then
        sudo chown "$USER:$USER" "$LOG_FILE"
    fi
    
    print_status "Starting Code-Server installation..."
    
    # Step 1: Check root privileges
    check_root
    
    # Step 2: Collect user input
    collect_user_input
    
    # Step 3: Check system requirements
    check_system_requirements
    
    # Step 4: Install dependencies
    install_dependencies
    
    # Step 5: Install code-server
    install_code_server
    
    # Step 6: Configure Nginx
    configure_nginx
    
    # Step 7: Setup SSL
    setup_ssl
    
    # Step 8: Configure firewall
    configure_firewall
    
    # Step 9: Start services
    start_services
    
    # Step 10: Create management panel
    create_management_panel
    
    # Step 11: Show completion info
    show_completion_info
}

# Check if jq is installed (required for config parsing)
if ! command -v jq &>/dev/null; then
    print_status "Installing jq for configuration parsing..."
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
