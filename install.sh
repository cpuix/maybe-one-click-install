#!/bin/bash

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Output functions
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

echo "=================================================="
echo "Complete Maybe Finance Installation Script"
echo "Docker + Nginx + SSL + Domain Setup"
echo "=================================================="
echo

# ==============================================
# COLLECT USER INPUT AT THE BEGINNING
# ==============================================

# Domain name
echo "📋 Configuration Setup"
echo "======================"
while true; do
    read -p "Enter your domain name (e.g., maybe.example.com): " DOMAIN_NAME
    if [[ -n "$DOMAIN_NAME" && "$DOMAIN_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]*\.[a-zA-Z]{2,}$ ]]; then
        break
    else
        print_error "Please enter a valid domain name!"
    fi
done

# Email for SSL certificate
while true; do
    read -p "Enter your email address for SSL certificate: " EMAIL_ADDRESS
    if [[ "$EMAIL_ADDRESS" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        break
    else
        print_error "Please enter a valid email address!"
    fi
done

# PostgreSQL password
while true; do
    read -s -p "Enter PostgreSQL password (or press Enter for auto-generated): " POSTGRES_PASSWORD
    echo
    if [[ -z "$POSTGRES_PASSWORD" ]]; then
        POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
        print_status "Auto-generated PostgreSQL password"
        break
    elif [[ ${#POSTGRES_PASSWORD} -ge 8 ]]; then
        break
    else
        print_error "Password must be at least 8 characters long!"
    fi
done

# PostgreSQL username
read -p "Enter PostgreSQL username (default: maybe_user): " POSTGRES_USER
POSTGRES_USER=${POSTGRES_USER:-maybe_user}

# PostgreSQL database name
read -p "Enter PostgreSQL database name (default: maybe_production): " POSTGRES_DB
POSTGRES_DB=${POSTGRES_DB:-maybe_production}

# OpenAI API Key (optional)
read -p "Enter OpenAI API key for AI features (optional, press Enter to skip): " OPENAI_API_KEY

# Installation directory
read -p "Enter installation directory (default: ~/docker-apps/maybe): " INSTALL_DIR
INSTALL_DIR=${INSTALL_DIR:-~/docker-apps/maybe}

# Expand tilde to full path
INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}"

# SSL Certificate option
echo
read -p "Install SSL certificate automatically? (y/N): " -n 1 -r INSTALL_SSL
echo

# Firewall configuration
echo
read -p "Configure UFW firewall automatically? (y/N): " -n 1 -r CONFIGURE_FIREWALL
echo

# Confirmation
echo
echo "=================================================="
echo "📋 Installation Summary"
echo "=================================================="
echo "Domain: $DOMAIN_NAME"
echo "Email: $EMAIL_ADDRESS"
echo "PostgreSQL User: $POSTGRES_USER"
echo "PostgreSQL Database: $POSTGRES_DB"
echo "Installation Directory: $INSTALL_DIR"
echo "SSL Certificate: $(if [[ $INSTALL_SSL =~ ^[Yy]$ ]]; then echo 'Yes'; else echo 'No'; fi)"
echo "Configure Firewall: $(if [[ $CONFIGURE_FIREWALL =~ ^[Yy]$ ]]; then echo 'Yes'; else echo 'No'; fi)"
if [[ -n "$OPENAI_API_KEY" ]]; then
    echo "OpenAI API Key: Provided"
else
    echo "OpenAI API Key: Not provided"
fi
echo "=================================================="
echo

read -p "Continue with installation? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_error "Installation cancelled by user"
    exit 1
fi

# ==============================================
# SYSTEM CHECKS
# ==============================================

print_status "Performing system checks..."

# Root user check
if [ "$EUID" -eq 0 ]; then
    print_error "Do not run this script as root user. Use a regular user with sudo privileges."
    exit 1
fi

# Sudo privileges check
if ! sudo -n true 2>/dev/null; then
    print_error "This script requires sudo privileges. Please run with a user that has sudo access."
    exit 1
fi

# Check if domain resolves to this server
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || echo "unknown")
if [[ "$SERVER_IP" != "unknown" ]]; then
    DOMAIN_IP=$(dig +short "$DOMAIN_NAME" 2>/dev/null | tail -n1)
    if [[ "$DOMAIN_IP" != "$SERVER_IP" ]]; then
        print_warning "Domain $DOMAIN_NAME does not resolve to this server IP ($SERVER_IP)"
        print_warning "Current domain IP: ${DOMAIN_IP:-not found}"
        print_warning "SSL certificate installation may fail if DNS is not configured correctly"
    else
        print_success "Domain DNS is correctly configured"
    fi
fi

# ==============================================
# SYSTEM UPDATE AND DOCKER INSTALLATION
# ==============================================

print_status "Updating system packages..."
sudo apt update && sudo apt upgrade -y

print_status "Installing required packages..."
sudo apt install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    wget \
    unzip \
    openssl \
    dnsutils

print_status "Adding Docker GPG key..."
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

print_status "Adding Docker repository..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

print_status "Updating package list..."
sudo apt update

print_status "Installing Docker Engine..."
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

print_status "Starting Docker service..."
sudo systemctl start docker
sudo systemctl enable docker

print_status "Adding user to Docker group..."
sudo usermod -aG docker $USER

print_status "Testing Docker installation..."
if sudo docker run hello-world > /dev/null 2>&1; then
    print_success "Docker successfully installed and running!"
else
    print_error "Docker installation failed!"
    exit 1
fi

# ==============================================
# NGINX INSTALLATION AND CONFIGURATION
# ==============================================

print_status "Installing Nginx..."
sudo apt install -y nginx

print_status "Installing Certbot for SSL certificates..."
sudo apt install -y certbot python3-certbot-nginx

print_status "Creating Nginx configuration..."
sudo tee /etc/nginx/sites-available/$DOMAIN_NAME > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN_NAME;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 86400;
    }

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_proxied any;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/xml+rss
        application/atom+xml
        image/svg+xml;

    # Security headers
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options DENY;
    add_header X-XSS-Protection "1; mode=block";
}
EOF

print_success "Nginx configuration created!"

print_status "Enabling site..."
sudo ln -sf /etc/nginx/sites-available/$DOMAIN_NAME /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

print_status "Testing Nginx configuration..."
if sudo nginx -t; then
    print_success "Nginx configuration is valid!"
else
    print_error "Nginx configuration error!"
    exit 1
fi

print_status "Restarting Nginx..."
sudo systemctl restart nginx
sudo systemctl enable nginx

print_success "Nginx successfully configured!"

# ==============================================
# MAYBE FINANCE INSTALLATION
# ==============================================

print_status "Creating Maybe Finance directory..."
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

print_success "Directory created: $INSTALL_DIR"

print_status "Downloading Docker Compose file..."
curl -o compose.yml https://raw.githubusercontent.com/maybe-finance/maybe/main/compose.example.yml

if [ ! -f "compose.yml" ]; then
    print_error "Failed to download compose file!"
    exit 1
fi

print_success "Docker Compose file downloaded successfully!"

print_status "Creating environment configuration file..."

# Generate secure secret key
SECRET_KEY_BASE=$(openssl rand -hex 64)

# Create .env file
cat > .env << EOF
# Maybe Finance Environment Variables
# Generated by installation script

# Security - Strong secret key for Rails application
SECRET_KEY_BASE=$SECRET_KEY_BASE

# PostgreSQL Database Configuration
POSTGRES_USER=$POSTGRES_USER
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_DB=$POSTGRES_DB

# OpenAI API Key for AI features (optional)
$(if [[ -n "$OPENAI_API_KEY" ]]; then echo "OPENAI_ACCESS_TOKEN=$OPENAI_API_KEY"; else echo "# OPENAI_ACCESS_TOKEN=your_openai_api_key_here"; fi)

# Domain Configuration
DOMAIN_NAME=$DOMAIN_NAME
ACME_EMAIL=$EMAIL_ADDRESS
EOF

print_success "Environment file created with secure passwords!"

print_status "Modifying Docker Compose for localhost binding..."
# Bind to localhost only for security (Nginx will handle external access)
if grep -q "3000:3000" compose.yml; then
    sed -i 's/- 3000:3000/- 127.0.0.1:3000:3000/' compose.yml
    print_status "Docker port mapping bound to localhost for security"
fi

print_status "Downloading Docker images..."
sudo docker compose pull

print_success "Docker images downloaded successfully!"

print_status "Starting Maybe Finance application..."
sudo docker compose up -d

# Wait for containers to start
print_status "Waiting for containers to start..."
sleep 30

# Check container status
if sudo docker compose ps | grep -q "Up"; then
    print_success "Maybe Finance successfully started!"
else
    print_error "Failed to start Maybe Finance containers!"
    print_status "Checking logs:"
    sudo docker compose logs
    exit 1
fi

# ==============================================
# SSL CERTIFICATE INSTALLATION
# ==============================================

if [[ $INSTALL_SSL =~ ^[Yy]$ ]]; then
    print_status "Installing SSL certificate..."
    
    if sudo certbot --nginx -d $DOMAIN_NAME --non-interactive --agree-tos --email $EMAIL_ADDRESS --redirect; then
        print_success "SSL certificate successfully installed!"
        
        print_status "Setting up automatic SSL renewal..."
        if ! sudo crontab -l 2>/dev/null | grep -q "certbot renew"; then
            (sudo crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet") | sudo crontab -
            print_success "Automatic SSL renewal configured!"
        fi
    else
        print_error "SSL certificate installation failed!"
        print_warning "You can install it manually later with:"
        echo "sudo certbot --nginx -d $DOMAIN_NAME"
    fi
fi

# ==============================================
# FIREWALL CONFIGURATION
# ==============================================

if [[ $CONFIGURE_FIREWALL =~ ^[Yy]$ ]]; then
    if command -v ufw >/dev/null 2>&1; then
        print_status "Configuring UFW firewall..."
        sudo ufw --force enable
        sudo ufw allow ssh
        sudo ufw allow 'Nginx Full'
        print_success "Firewall rules configured!"
    else
        print_warning "UFW not installed, skipping firewall configuration"
    fi
fi

# ==============================================
# FINAL STATUS CHECKS
# ==============================================

print_status "Performing final system checks..."

# Check Nginx status
if sudo systemctl is-active --quiet nginx; then
    print_success "✓ Nginx is running"
else
    print_error "✗ Nginx is not running"
fi

# Check Maybe Finance status
cd "$INSTALL_DIR"
if sudo docker compose ps | grep -q "Up"; then
    print_success "✓ Maybe Finance is running"
else
    print_error "✗ Maybe Finance is not running"
fi

# Check SSL certificate status
if [[ $INSTALL_SSL =~ ^[Yy]$ ]]; then
    if sudo certbot certificates 2>/dev/null | grep -q "$DOMAIN_NAME"; then
        print_success "✓ SSL certificate is installed"
    else
        print_warning "✗ SSL certificate not found"
    fi
fi

# ==============================================
# INSTALLATION COMPLETE
# ==============================================

echo
echo "=================================================="
echo "🎉 INSTALLATION COMPLETED SUCCESSFULLY!"
echo "=================================================="
echo
print_success "Maybe Finance is now running on your domain!"
echo
echo "🌐 Access Information:"
if [[ $INSTALL_SSL =~ ^[Yy]$ ]]; then
    echo "   Primary URL: https://$DOMAIN_NAME"
    echo "   HTTP URL: http://$DOMAIN_NAME (redirects to HTTPS)"
else
    echo "   URL: http://$DOMAIN_NAME"
fi
echo
echo "🔐 First Time Setup:"
echo "   1. Visit your domain in a web browser"
echo "   2. Click 'Create your account'"
echo "   3. Register your first user account"
echo
echo "📁 Installation Details:"
echo "   Installation Directory: $INSTALL_DIR"
echo "   Environment File: $INSTALL_DIR/.env" 
echo "   Nginx Configuration: /etc/nginx/sites-available/$DOMAIN_NAME"
echo "   PostgreSQL User: $POSTGRES_USER"
echo "   PostgreSQL Database: $POSTGRES_DB"
echo
echo "🔄 Management Commands:"
echo "   cd $INSTALL_DIR"
echo "   sudo docker compose stop      # Stop application"
echo "   sudo docker compose start     # Start application"
echo "   sudo docker compose restart   # Restart application"
echo "   sudo docker compose logs      # View logs"
echo "   sudo docker compose pull      # Update to latest version"
echo
echo "🌐 Nginx Commands:"
echo "   sudo systemctl status nginx   # Check Nginx status"
echo "   sudo nginx -t                 # Test configuration"
echo "   sudo systemctl reload nginx   # Reload configuration"
echo
if [[ $INSTALL_SSL =~ ^[Yy]$ ]]; then
echo "🔒 SSL Certificate Commands:"
echo "   sudo certbot certificates     # List certificates"
echo "   sudo certbot renew           # Renew certificates"
fi
echo
echo "☁️ Server Security Group Requirements:"
echo "   ✓ Port 80 (HTTP) - Required"
echo "   ✓ Port 443 (HTTPS) - Required for SSL"
echo "   ✓ Port 22 (SSH) - For server management"
echo "   ❌ Port 3000 - No longer needed (secured by Nginx)"
echo
echo "📋 Database Information (securely stored in .env):"
echo "   Username: $POSTGRES_USER"
echo "   Database: $POSTGRES_DB"
echo "   Password: [Hidden for security - check .env file]"
echo
echo "🔧 Troubleshooting:"
echo "   - Check logs: sudo docker compose logs"
echo "   - Check Nginx: sudo nginx -t"
echo "   - Check services: sudo systemctl status nginx docker"
echo "   - View environment: cat $INSTALL_DIR/.env"
echo
echo "=================================================="
print_success "Installation completed! Maybe Finance is ready to use."
print_warning "IMPORTANT: Please reboot the system or run 'newgrp docker' to apply Docker group changes."
echo "=================================================="

# Offer system reboot
echo
read -p "Would you like to reboot the system now to apply all changes? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_status "Rebooting system..."
    sudo reboot
else
    print_status "System reboot skipped. Consider rebooting manually: sudo reboot"
    print_status "Or run: newgrp docker"
fi
