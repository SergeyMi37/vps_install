#!/bin/bash

# ==============================================
# FRP Server Auto-Install Script
# Non-interactive installation for VPS
# Domain: frp.my.site
# ==============================================

set -euo pipefail

# --- Configuration Variables ---
FRP_VERSION="0.61.0"
FRP_DOWNLOAD_URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_amd64.tar.gz"
INSTALL_DIR="/opt/frp"
LOG_FILE="/root/frp_install_protocol.log"
FRP_DOMAIN="frp.my.site"
FRP_SERVER_PORT=7000
FRP_DASHBOARD_PORT=7500
FRP_TOKEN=$(openssl rand -hex 16)
FRP_DASHBOARD_USER="admin"
FRP_DASHBOARD_PASS=$(openssl rand -base64 12)

# --- Initialize Log ---
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=============================================="
echo "FRP Server Installation Protocol"
echo "Started at: $(date)"
echo "Domain: $FRP_DOMAIN"
echo "=============================================="
echo ""

# --- System Detection ---
ARCH=$(uname -m)
case $ARCH in
    x86_64)  ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

FRP_DOWNLOAD_URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${ARCH}.tar.gz"

# --- Install Dependencies ---
echo "[1/7] Installing dependencies..."
if command -v apt-get &> /dev/null; then
    apt-get update -qq
    apt-get install -y -qq wget tar openssl curl ufw
elif command -v yum &> /dev/null; then
    yum install -y -q wget tar openssl curl firewalld
elif command -v dnf &> /dev/null; then
    dnf install -y -q wget tar openssl curl firewalld
fi

# --- Create User ---
echo "[2/7] Creating frp system user..."
if ! id -u frp &>/dev/null; then
    useradd -r -s /bin/false frp
fi

# --- Download and Install FRP ---
echo "[3/7] Downloading FRP version ${FRP_VERSION} for ${ARCH}..."
mkdir -p "$INSTALL_DIR"
cd /tmp
wget -q --show-progress "$FRP_DOWNLOAD_URL" -O frp.tar.gz
tar -xzf frp.tar.gz
cp "frp_${FRP_VERSION}_linux_${ARCH}/frps" "$INSTALL_DIR/frps"
chmod +x "$INSTALL_DIR/frps"
chown -R frp:frp "$INSTALL_DIR"

# --- Create Configuration ---
echo "[4/7] Creating server configuration..."
cat > /etc/frps.toml << EOF
# FRP Server Configuration
bindPort = ${FRP_SERVER_PORT}
auth.token = "${FRP_TOKEN}"

# Dashboard
webServer.addr = "0.0.0.0"
webServer.port = ${FRP_DASHBOARD_PORT}
webServer.user = "${FRP_DASHBOARD_USER}"
webServer.password = "${FRP_DASHBOARD_PASS}"

# Transport
transport.tcpMux = true

# Logging
log.to = "/var/log/frps.log"
log.level = "info"
log.maxDays = 3
EOF

# --- Create Systemd Service ---
echo "[5/7] Creating systemd service..."
cat > /etc/systemd/system/frps.service << EOF
[Unit]
Description=FRP Server Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=frp
Group=frp
ExecStart=${INSTALL_DIR}/frps -c /etc/frps.toml
Restart=on-failure
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

# --- Configure Firewall ---
echo "[6/7] Configuring firewall..."
if command -v ufw &> /dev/null; then
    ufw allow ${FRP_SERVER_PORT}/tcp comment "FRP Server"
    ufw allow ${FRP_DASHBOARD_PORT}/tcp comment "FRP Dashboard"
    ufw allow 80/tcp comment "HTTP"
    ufw allow 443/tcp comment "HTTPS"
    ufw allow 6000:6100/tcp comment "FRP Client Range"
    ufw --force enable
elif command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --add-port=${FRP_SERVER_PORT}/tcp
    firewall-cmd --permanent --add-port=${FRP_DASHBOARD_PORT}/tcp
    firewall-cmd --permanent --add-port=80/tcp
    firewall-cmd --permanent --add-port=443/tcp
    firewall-cmd --permanent --add-port=6000-6100/tcp
    firewall-cmd --reload
fi

# --- Enable and Start Service ---
echo "[7/7] Starting FRP service..."
systemctl daemon-reload
systemctl enable frps
systemctl start frps

sleep 2

# --- Verify Installation ---
if systemctl is-active --quiet frps; then
    STATUS="ACTIVE"
else
    STATUS="FAILED"
fi

# --- Get Public IP ---
PUBLIC_IP=$(curl -s4 ifconfig.me || curl -s4 ipinfo.io/ip || echo "YOUR_VPS_IP")

# --- Generate Protocol File ---
cat > "$LOG_FILE" << 'PROTOCOL_EOF'

==============================================
FRP SERVER INSTALLATION PROTOCOL
==============================================
Installation Date: $(date)
Status: $STATUS

==============================================
SERVER DETAILS
==============================================
FRP Version: ${FRP_VERSION}
Domain: ${FRP_DOMAIN}
Public IP: ${PUBLIC_IP}

Server Configuration:
  Bind Port: ${FRP_SERVER_PORT}
  Token: ${FRP_TOKEN}
  Dashboard: http://${PUBLIC_IP}:${FRP_DASHBOARD_PORT}
  Dashboard User: ${FRP_DASHBOARD_USER}
  Dashboard Password: ${FRP_DASHBOARD_PASS}

==============================================
CLIENT INSTALLATION INSTRUCTIONS
==============================================

=== WINDOWS INSTALLATION ===

1. Download FRP Client:
   https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_windows_amd64.zip

2. Extract the archive to C:\frp\

3. Create configuration file C:\frp\frpc.toml:
```toml
# FRP Client Configuration
serverAddr = "${PUBLIC_IP}"
serverPort = ${FRP_SERVER_PORT}
auth.token = "${FRP_TOKEN}"

# Example: Expose local web service on port 8080
[[proxies]]
name = "web-service"
type = "tcp"
localIP = "127.0.0.1"
localPort = 8080
remotePort = 6000

# Example: Expose RDP (Remote Desktop)
[[proxies]]
name = "rdp-access"
type = "tcp"
localIP = "127.0.0.1"
localPort = 3389
remotePort = 6001