#!/bin/bash
# wget https://raw.githubusercontent.com/SergeyMi37/vps_install/master/ubuntu/vps_ubuntu_install_rustdesk.sh && chmod +x vps_ubuntu_install_rustdesk.sh && ./vps_ubuntu_install_rustdesk.sh

# RustDesk Server Auto-Installation Script with Let's Encrypt HTTPS
# Tested on Ubuntu 22.04 / 24.04

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
            echo "Usage: sudo $0 -d DOMAIN -e EMAIL [-s SSH_PORT] [--skip-firewall]"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$DOMAIN" ]]; then
    print_error "Domain is required. Use -d or --domain"
    exit 1
fi

if [[ -z "$EMAIL" ]]; then
    print_error "Email is required. Use -e or --email"
    exit 1
fi

# Auto-detect SSH port
if [[ -z "$SSH_PORT" ]]; then
    if [ -f /etc/ssh/sshd_config ]; then
        SSH_PORT=$(grep -E "^Port " /etc/ssh/sshd_config | awk '{print $2}')
        if [ -z "$SSH_PORT" ]; then
            SSH_PORT=22
        fi
    else
        SSH_PORT=22
    fi
fi

# Validate SSH port is a number
if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]]; then
    print_warn "Invalid SSH port detected, using default 22"
    SSH_PORT=22
fi

# Check root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi


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

# ============================================
# 3. Configure firewall (FIXED)
# ============================================
if [[ "$SKIP_FIREWALL" = false ]]; then
    print_step "3/6: Configuring firewall"
    
    # Check if ufw is installed
    if ! command -v ufw &> /dev/null; then
        apt install -y ufw
    fi
    
    # Enable ufw non-interactively
    if ufw status | grep -q "inactive"; then
        echo "y" | ufw enable || true
    fi
    
    # Open ports with proper syntax - using separate commands without problematic comments
    print_info "Opening ports..."
    ufw allow "$SSH_PORT"/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw allow 21115/tcp
    ufw allow 21116/tcp
    ufw allow 21116/udp
    ufw allow 21117/tcp
    ufw allow 21118/tcp
    ufw allow 21119/tcp
    
    # Reload and enable
    ufw --force enable
    print_info "Firewall configured"
else
    print_warn "Skipping firewall configuration"
fi

# ============================================
# 4. Setup RustDesk Server
# ============================================
print_step "4/6: Setting up RustDesk Server"

mkdir -p /opt/rustdesk/data
cd /opt/rustdesk

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

docker compose up -d
sleep 5

if docker ps | grep -q "rustdesk"; then
    print_info "RustDesk containers started"
else
    print_error "Failed to start RustDesk containers"
    docker compose logs
    exit 1
fi

sleep 5
if [ -f /opt/rustdesk/data/id_ed25519.pub ]; then
    RUSTDESK_KEY=$(cat /opt/rustdesk/data/id_ed25519.pub)
    print_info "Server key obtained"
else
    RUSTDESK_KEY="NOT AVAILABLE"
    print_warn "Key not yet generated"
fi

# ============================================
# 5. Configure Nginx with SSL
# ============================================
print_step "5/6: Configuring Nginx and SSL"

mkdir -p /var/www/rustdesk

cat > /var/www/rustdesk/index.html <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>RustDesk Server</title>
    <style>
        body { font-family: monospace; margin: 40px; }
        .key { background: #2c3e50; color: #ecf0f1; padding: 10px; border-radius: 5px; overflow-x: auto; }
        .info { background: #f0f0f0; padding: 20px; border-radius: 8px; margin: 20px 0; }
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
        <h2>Client Setup</h2>
        <p>1. Download RustDesk: <a href="https://rustdesk.com/download">rustdesk.com/download</a></p>
        <p>2. Settings → Network → ID Server: <code>$DOMAIN</code></p>
        <p>3. Paste the Key above → Apply → Restart client</p>
    </div>
</body>
</html>
EOF

systemctl stop nginx

if certbot certonly --standalone --non-interactive --agree-tos --email "$EMAIL" -d "$DOMAIN"; then
    print_info "SSL certificate obtained"
    
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

    root /var/www/rustdesk;
    index index.html;
}
EOF
else
    print_warn "SSL certificate failed, using HTTP only"
    
    cat > /etc/nginx/sites-available/rustdesk <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    root /var/www/rustdesk;
    index index.html;
}
EOF
fi

ln -sf /etc/nginx/sites-available/rustdesk /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

nginx -t
systemctl start nginx
systemctl reload nginx

if [[ -d "/etc/letsencrypt/live/$DOMAIN" ]]; then
    (crontab -l 2>/dev/null; echo "0 3 * * * /usr/bin/certbot renew --quiet --post-hook 'systemctl reload nginx'") | crontab -
    print_info "Auto-renewal configured"
fi

# ============================================
# 6. Helper scripts
# ============================================
print_step "6/6: Creating helper scripts"

cat > /usr/local/bin/rustdesk-status <<'EOF'
#!/bin/bash
echo "=== RustDesk Server Status ==="
echo ""
docker ps --filter "name=rustdesk" --format "table {{.Names}}\t{{.Status}}"
echo ""
if [ -f /opt/rustdesk/data/id_ed25519.pub ]; then
    echo "Server Key:"
    cat /opt/rustdesk/data/id_ed25519.pub
fi
EOF

chmod +x /usr/local/bin/rustdesk-status

cat > /usr/local/bin/rustdesk-key <<'EOF'
#!/bin/bash
cat /opt/rustdesk/data/id_ed25519.pub 2>/dev/null || echo "Key not found"
EOF

chmod +x /usr/local/bin/rustdesk-key

# ============================================
# Final output
# ============================================

echo "========================================="
echo "  ✅ RustDesk Server Installed"
echo "========================================="
echo ""
echo "ID Server:  $DOMAIN"
echo "Key:        $RUSTDESK_KEY"
echo "SSH Port:   $SSH_PORT"
echo ""
echo "Info page:  https://$DOMAIN"
echo ""
echo "Commands:   rustdesk-status"
echo "            rustdesk-key"

echo "# Посмотреть логи hbbs (сервер регистрации)"
echo "            docker logs -f rustdesk_hbbs"

echo "# Посмотреть логи hbbr (релейный сервер)"
echo "            docker logs -f rustdesk_hbbr"
echo "# Перезапустить RustDesk сервер "
echo "cd /opt/rustdesk && docker compose restart"
echo ""
echo "Клиентов можно скачать здесь"
echo "https://github.com/rustdesk/rustdesk/releases"
echo "https://rustdesk.com/web/"
echo ""
print_info "Installation complete!"