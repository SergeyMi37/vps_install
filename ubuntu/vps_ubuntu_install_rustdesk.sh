#!/bin/bash
# wget https://raw.githubusercontent.com/SergeyMi37/vps_install/master/ubuntu/vps_ubuntu_install_rustdesk.sh && chmod +x vps_ubuntu_install_rustdesk.sh && ./vps_ubuntu_install_rustdesk.sh

# RustDesk Server Auto-Installation Script with Let's Encrypt HTTPS
# Tested on Ubuntu 22.04 / 24.04
#
# Usage:
#   sudo ./install_rustdesk.sh -d rustdesk.example.com -e admin@example.com
#
# Options:
#   -d, --domain DOMAIN    Domain name (required)
#   -e, --email EMAIL      Email for Let's Encrypt (required)
#   -s, --ssh-port PORT    SSH port (default: auto-detect)
#   --skip-firewall        Skip firewall configuration
#   -h, --help             Show help

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_step() { echo -e "\n${BLUE}==>${NC} ${GREEN}$1${NC}"; }

show_help() {
    cat << EOF
RustDesk Server Installation Script

Usage: sudo $0 [OPTIONS]

Options:
  -d, --domain DOMAIN    Domain name (required, e.g., rustdesk.example.com)
  -e, --email EMAIL      Email for Let's Encrypt (required)
  -s, --ssh-port PORT    SSH port (default: auto-detect from system)
  --skip-firewall        Skip firewall configuration
  -h, --help             Show this help

Example:
  sudo $0 -d rustdesk.example.com -e admin@example.com
EOF
    exit 0
}

# Parse arguments
DOMAIN=""
EMAIL=""
SSH_PORT=""
SKIP_FIREWALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--domain)
            DOMAIN="$2"
            shift 2
            ;;
        -e|--email)
            EMAIL="$2"
            shift 2
            ;;
        -s|--ssh-port)
            SSH_PORT="$2"
            shift 2
            ;;
        --skip-firewall)
            SKIP_FIREWALL=true
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            ;;
    esac
done

# Validate required parameters
if [[ -z "$DOMAIN" ]]; then
    print_error "Domain is required. Use -d or --domain"
    show_help
fi

if [[ -z "$EMAIL" ]]; then
    print_error "Email is required. Use -e or --email"
    show_help
fi

# Auto-detect SSH port
if [[ -z "$SSH_PORT" ]]; then
    if [ -f /etc/ssh/sshd_config ]; then
        SSH_PORT=$(grep -E "^Port " /etc/ssh/sshd_config | awk '{print $2}')
        [ -z "$SSH_PORT" ] && SSH_PORT=22
    else
        SSH_PORT=22
    fi
fi

# Check root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

clear
echo "========================================="
echo "  RustDesk Server Installation"
echo "========================================="
echo ""
echo "Domain: $DOMAIN"
echo "Email: $EMAIL"
echo "SSH Port: $SSH_PORT"
echo ""
read -p "Press Enter to continue or Ctrl+C to cancel..."

# ============================================
# 1. Update system
# ============================================
print_step "1/6: Updating system"
apt update && apt upgrade -y
apt install -y apt-transport-https ca-certificates curl wget software-properties-common nginx ufw gnupg lsb-release certbot python3-certbot-nginx

# ============================================
# 2. Install Docker
# ============================================
print_step "2/6: Installing Docker"
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    print_info "Docker installed"
else
    print_info "Docker already installed"
fi

if ! docker compose version &> /dev/null; then
    apt install -y docker-compose-plugin
    print_info "Docker Compose plugin installed"
fi

print_info "Docker version: $(docker --version)"
print_info "Docker Compose version: $(docker compose version)"

# ============================================
# 3. Configure firewall
# ============================================
if [[ "$SKIP_FIREWALL" = false ]]; then
    print_step "3/6: Configuring firewall"
    
    if ufw status | grep -q "inactive"; then
        echo "y" | ufw enable
    fi
    
    ufw allow "${SSH_PORT}/tcp" comment "SSH custom port"
    ufw allow 80/tcp comment "HTTP (Let's Encrypt)"
    ufw allow 443/tcp comment "HTTPS"
    ufw allow 21115/tcp comment "RustDesk NAT test"
    ufw allow 21116/tcp comment "RustDesk TCP"
    ufw allow 21116/udp comment "RustDesk UDP"
    ufw allow 21117/tcp comment "RustDesk Relay"
    ufw allow 21118/tcp comment "RustDesk Web hbbs"
    ufw allow 21119/tcp comment "RustDesk Web hbbr"
    
    ufw --force enable
    print_info "Firewall configured"
else
    print_warn "Skipping firewall configuration"
fi

# ============================================
# 4. Create RustDesk directories and docker-compose
# ============================================
print_step "4/6: Setting up RustDesk Server"

mkdir -p /opt/rustdesk/data
cd /opt/rustdesk

# Create docker-compose.yml for RustDesk [citation:2]
cat > /opt/rustdesk/docker-compose.yml <<EOF
services:
  hbbs:
    image: rustdesk/rustdesk-server:latest
    container_name: rustdesk_hbbs
    command: hbbs
    restart: unless-stopped
    volumes:
      - /opt/rustdesk/data:/root
    network_mode: host

  hbbr:
    image: rustdesk/rustdesk-server:latest
    container_name: rustdesk_hbbr
    command: hbbr
    restart: unless-stopped
    volumes:
      - /opt/rustdesk/data:/root
    network_mode: host
EOF

# Start containers
docker compose up -d
sleep 5

if docker ps | grep -q "rustdesk"; then
    print_info "RustDesk containers started"
else
    print_error "Failed to start RustDesk containers"
    docker compose logs
    exit 1
fi

# Get server key
sleep 5
if [ -f /opt/rustdesk/data/id_ed25519.pub ]; then
    RUSTDESK_KEY=$(cat /opt/rustdesk/data/id_ed25519.pub)
    print_info "Server key obtained"
else
    RUSTDESK_KEY="NOT AVAILABLE - check later"
    print_warn "Key not yet generated"
fi

# ============================================
# 5. Configure Nginx with SSL
# ============================================
print_step "5/6: Configuring Nginx and SSL"

# Create info page
mkdir -p /var/www/rustdesk

cat > /var/www/rustdesk/index.html <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>RustDesk Server Active</title>
    <style>
        body { font-family: monospace; margin: 40px; line-height: 1.6; }
        h1 { color: #27ae60; }
        .key { background: #2c3e50; color: #ecf0f1; padding: 10px; border-radius: 5px; overflow-x: auto; }
        .info { background: #f0f0f0; padding: 20px; border-radius: 8px; margin: 20px 0; }
        code { background: #333; color: #fff; padding: 2px 6px; border-radius: 4px; }
    </style>
</head>
<body>
    <h1>✅ RustDesk Server Active</h1>
    <div class="info">
        <h2>Connection Details</h2>
        <p><strong>ID Server:</strong> <code>$DOMAIN</code></p>
        <p><strong>Key:</strong></p>
        <div class="key">$RUSTDESK_KEY</div>
    </div>
    <div class="info">
        <h2>Client Configuration</h2>
        <p>1. Download RustDesk from <a href="https://rustdesk.com/download">rustdesk.com/download</a></p>
        <p>2. Open Settings → Network</p>
        <p>3. Set <strong>ID Server</strong> to: <code>$DOMAIN</code></p>
        <p>4. Set <strong>Key</strong> to the key above</p>
        <p>5. Click Apply and restart the client</p>
    </div>
    <hr>
    <p>Server installed on $(date '+%Y-%m-%d %H:%M:%S')</p>
</body>
</html>
EOF

# Stop Nginx for certificate issuance
systemctl stop nginx

# Obtain SSL certificate
if certbot certonly --standalone --non-interactive --agree-tos --email "$EMAIL" -d "$DOMAIN"; then
    print_info "SSL certificate obtained successfully"
    
    # Create Nginx configuration with HTTPS support [citation:2][citation:8]
    cat > /etc/nginx/sites-available/rustdesk <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    root /var/www/rustdesk;
    index index.html;
}
EOF
    
else
    print_warn "Could not obtain SSL certificate, configuring HTTP only"
    
    cat > /etc/nginx/sites-available/rustdesk <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    root /var/www/rustdesk;
    index index.html;
}
EOF
fi

# Enable site
ln -sf /etc/nginx/sites-available/rustdesk /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default 2>/dev/null

# Test and restart Nginx
nginx -t
systemctl start nginx
systemctl reload nginx

# Setup auto-renewal for certificates
if [[ -d "/etc/letsencrypt/live/$DOMAIN" ]]; then
    (crontab -l 2>/dev/null; echo "0 3 * * * /usr/bin/certbot renew --quiet --post-hook 'systemctl reload nginx'") | crontab -
    print_info "Auto-renewal configured for SSL certificates"
fi

# ============================================
# 6. Create helper scripts
# ============================================
print_step "6/6: Creating helper scripts"

# Status script
cat > /usr/local/bin/rustdesk-status <<'EOF'
#!/bin/bash
echo "========================================="
echo "  RustDesk Server Status"
echo "========================================="
echo ""
docker ps --filter "name=rustdesk" --format "table {{.Names}}\t{{.Status}}"
echo ""
if [ -f /opt/rustdesk/data/id_ed25519.pub ]; then
    echo "Server Key:"
    cat /opt/rustdesk/data/id_ed25519.pub
fi
echo ""
echo "Commands:"
echo "  docker logs -f rustdesk_hbbs  # View hbbs logs"
echo "  docker logs -f rustdesk_hbbr  # View hbbr logs"
echo "  cd /opt/rustdesk && docker compose restart  # Restart server"
EOF

chmod +x /usr/local/bin/rustdesk-status

# Key display script
cat > /usr/local/bin/rustdesk-key <<'EOF'
#!/bin/bash
if [ -f /opt/rustdesk/data/id_ed25519.pub ]; then
    echo "RustDesk Server Key:"
    echo ""
    cat /opt/rustdesk/data/id_ed25519.pub
else
    echo "Key not found. Make sure RustDesk server is running."
fi
EOF

chmod +x /usr/local/bin/rustdesk-key

# ============================================
# Final output
# ============================================
clear
echo "========================================="
echo "  ✅ RustDesk Server Successfully Installed"
echo "========================================="
echo ""
echo "CONNECTION DETAILS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "ID Server (Host):  $DOMAIN"
echo "Key:               $RUSTDESK_KEY"
echo "SSH Port:          $SSH_PORT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🔧 CLIENT CONFIGURATION:"
echo "   1. Download RustDesk: https://rustdesk.com/download"
echo "   2. Open Settings → Network"
echo "   3. Set ID Server to: $DOMAIN"
echo "   4. Paste the Key above"
echo "   5. Click Apply and restart the client"
echo ""
echo "📍 Info page: https://$DOMAIN"
echo ""
echo "🛠️  USEFUL COMMANDS:"
echo "   rustdesk-status  - Check server status"
echo "   rustdesk-key     - Display server key"
echo "   docker logs -f rustdesk_hbbs  - View logs"
echo "   cd /opt/rustdesk && docker compose restart  - Restart server"
echo ""
print_info "Installation complete!"