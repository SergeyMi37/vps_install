#!/bin/bash
# sudo wget https://raw.githubusercontent.com/SergeyMi37/vps_install/master/ubuntu/tun_frp.sh && sudo chmod +x tun_frp.sh && sudo ./tun_frp.sh -d frp.mydomain.com -e admin@mydomain.com
# 1. Базовая установка с доменом:
# bash
# ./install-frp-server.sh --domain frp.example.com
# 2. Полная кастомизация:
# ./install-frp-server.sh \
#   --version 0.60.0 \
#   --domain frp.my.site \
#   --port 7000 \
#   --dashboard-port 7500 \
#   --dashboard-user admin \
#   --dashboard-pass MySecurePass123 \
#   --token MySecretToken456 \
#   --client-port-start 6000 \
#   --client-port-end 6100
# 3. Установка без файрвола:
# bash
# ./install-frp-server.sh --skip-firewall --domain frp.example.com
# 4. Dry run для проверки:
# bash
# ./install-frp-server.sh --dry-run --domain frp.example.com
# 5. Установка с пользовательскими портами:
# bash
# ./install-frp-server.sh \
#   -p 4443 \
#   --dashboard-port 8080 \
#   --client-port-start 10000 \
#   --client-port-end 10050
  
# ==============================================
# FRP Server Auto-Install Script
# Fully Non-Interactive Installation for VPS
# Version: 3.0 - Parameterized Configuration
# ==============================================

set -euo pipefail

# --- Default Configuration ---
FRP_VERSION="0.61.0"
INSTALL_DIR="/opt/frp"
LOG_FILE="/root/frp_install_protocol.log"
FRP_DOMAIN="frp.my.site"
FRP_SERVER_PORT=7000
FRP_DASHBOARD_PORT=7500
FRP_DASHBOARD_USER="admin"
FRP_TOKEN=""
FRP_DASHBOARD_PASS=""
DRY_RUN=false
SKIP_FIREWALL=false
SKIP_SERVICE=false
CLIENT_PORT_RANGE_START=6000
CLIENT_PORT_RANGE_END=6100

# --- Usage Function ---
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

FRP Server Auto-Install Script - Non-interactive installation for VPS

OPTIONS:
    -v, --version VERSION          FRP version to install (default: ${FRP_VERSION})
    -d, --domain DOMAIN            Domain name for FRP server (default: ${FRP_DOMAIN})
    -p, --port PORT                FRP server bind port (default: ${FRP_SERVER_PORT})
    --dashboard-port PORT          Dashboard web interface port (default: ${FRP_DASHBOARD_PORT})
    --dashboard-user USER          Dashboard admin username (default: ${FRP_DASHBOARD_USER})
    --dashboard-pass PASS          Dashboard admin password (auto-generated if not set)
    --token TOKEN                  Authentication token (auto-generated if not set)
    --install-dir DIR              Installation directory (default: ${INSTALL_DIR})
    --log-file FILE                Protocol log file path (default: ${LOG_FILE})
    --client-port-start PORT       Start of client port range (default: ${CLIENT_PORT_RANGE_START})
    --client-port-end PORT         End of client port range (default: ${CLIENT_PORT_RANGE_END})
    --skip-firewall                Skip firewall configuration
    --skip-service                 Skip systemd service creation (manual start)
    --dry-run                      Perform dry run without actual installation
    -h, --help                     Show this help message

EXAMPLES:
    # Basic installation with domain
    $0 --domain frp.example.com

    # Custom ports and auto-generated credentials
    $0 -p 7000 --dashboard-port 7500

    # Full custom installation
    $0 -v 0.60.0 -d frp.my.site -p 7000 --dashboard-port 7500 \\
       --dashboard-user myadmin --dashboard-pass MyPass123 --token MyToken123

    # Dry run to see what would happen
    $0 --dry-run -d frp.example.com

    # Installation without firewall configuration
    $0 --skip-firewall -d frp.example.com

EOF
    exit 0
}

# --- Parse Command Line Arguments ---
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--version)
            FRP_VERSION="$2"
            shift 2
            ;;
        -d|--domain)
            FRP_DOMAIN="$2"
            shift 2
            ;;
        -p|--port)
            FRP_SERVER_PORT="$2"
            shift 2
            ;;
        --dashboard-port)
            FRP_DASHBOARD_PORT="$2"
            shift 2
            ;;
        --dashboard-user)
            FRP_DASHBOARD_USER="$2"
            shift 2
            ;;
        --dashboard-pass)
            FRP_DASHBOARD_PASS="$2"
            shift 2
            ;;
        --token)
            FRP_TOKEN="$2"
            shift 2
            ;;
        --install-dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        --log-file)
            LOG_FILE="$2"
            shift 2
            ;;
        --client-port-start)
            CLIENT_PORT_RANGE_START="$2"
            shift 2
            ;;
        --client-port-end)
            CLIENT_PORT_RANGE_END="$2"
            shift 2
            ;;
        --skip-firewall)
            SKIP_FIREWALL=true
            shift
            ;;
        --skip-service)
            SKIP_SERVICE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "ERROR: Unknown option: $1"
            usage
            ;;
    esac
done

# --- Generate Random Credentials if Not Provided ---
if [[ -z "$FRP_TOKEN" ]]; then
    FRP_TOKEN=$(openssl rand -hex 16)
fi

if [[ -z "$FRP_DASHBOARD_PASS" ]]; then
    FRP_DASHBOARD_PASS=$(openssl rand -base64 12)
fi

# --- Export Variables for Sub-processes ---
export FRP_VERSION
export INSTALL_DIR
export LOG_FILE
export FRP_DOMAIN
export FRP_SERVER_PORT
export FRP_DASHBOARD_PORT
export FRP_TOKEN
export FRP_DASHBOARD_USER
export FRP_DASHBOARD_PASS
export CLIENT_PORT_RANGE_START
export CLIENT_PORT_RANGE_END

# --- Suppress Interactive Prompts ---
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# --- Dry Run Check ---
if [[ "$DRY_RUN" == "true" ]]; then
    echo "=============================================="
    echo "DRY RUN MODE - No changes will be made"
    echo "=============================================="
    echo ""
    echo "Configuration that would be used:"
    echo "  FRP Version:       $FRP_VERSION"
    echo "  Domain:            $FRP_DOMAIN"
    echo "  Server Port:       $FRP_SERVER_PORT"
    echo "  Dashboard Port:    $FRP_DASHBOARD_PORT"
    echo "  Dashboard User:    $FRP_DASHBOARD_USER"
    echo "  Dashboard Pass:    $FRP_DASHBOARD_PASS"
    echo "  Token:             $FRP_TOKEN"
    echo "  Install Dir:       $INSTALL_DIR"
    echo "  Log File:          $LOG_FILE"
    echo "  Client Port Range: ${CLIENT_PORT_RANGE_START}-${CLIENT_PORT_RANGE_END}"
    echo "  Skip Firewall:     $SKIP_FIREWALL"
    echo "  Skip Service:      $SKIP_SERVICE"
    echo ""
    exit 0
fi

# --- Create Log Directory ---
mkdir -p "$(dirname "$LOG_FILE")"

# --- Initialize Logging ---
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=============================================="
echo "FRP Server Installation Protocol"
echo "Started at: $(date)"
echo "Domain: $FRP_DOMAIN"
echo "=============================================="
echo ""
echo "Configuration:"
echo "  FRP Version:       $FRP_VERSION"
echo "  Domain:            $FRP_DOMAIN"
echo "  Server Port:       $FRP_SERVER_PORT"
echo "  Dashboard Port:    $FRP_DASHBOARD_PORT"
echo "  Dashboard User:    $FRP_DASHBOARD_USER"
echo "  Client Port Range: ${CLIENT_PORT_RANGE_START}-${CLIENT_PORT_RANGE_END}"
echo ""

# --- System Detection ---
ARCH=$(uname -m)
case $ARCH in
    x86_64)  ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    *) echo "ERROR: Unsupported architecture: $ARCH"; exit 1 ;;
esac

export FRP_DOWNLOAD_URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${ARCH}.tar.gz"

echo "Detected architecture: $ARCH"
echo "Download URL: $FRP_DOWNLOAD_URL"

# --- Install Dependencies ---
echo ""
echo "[1/7] Installing dependencies..."
if command -v apt-get &> /dev/null; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq -y
    apt-get install -y -qq --no-install-recommends wget tar openssl curl ufw
    systemctl stop ufw 2>/dev/null || true
elif command -v dnf &> /dev/null; then
    dnf install -y -q wget tar openssl curl firewalld
    systemctl stop firewalld 2>/dev/null || true
elif command -v yum &> /dev/null; then
    yum install -y -q wget tar openssl curl firewalld
    systemctl stop firewalld 2>/dev/null || true
fi
echo "Dependencies installed successfully"

# --- Create System User ---
echo ""
echo "[2/7] Creating frp system user..."
if ! id -u frp &>/dev/null; then
    useradd -r -s /bin/false frp 2>/dev/null || \
    useradd --system --no-create-home --shell /bin/false frp 2>/dev/null || \
    adduser --system --no-create-home --shell /bin/false frp 2>/dev/null || true
fi
echo "User frp ready"

# --- Download and Extract FRP ---
echo ""
echo "[3/7] Downloading FRP version ${FRP_VERSION} for ${ARCH}..."
mkdir -p "$INSTALL_DIR"
cd /tmp
rm -f frp.tar.gz
rm -rf "frp_${FRP_VERSION}_linux_${ARCH}"

wget -q --show-progress --no-check-certificate "$FRP_DOWNLOAD_URL" -O frp.tar.gz || {
    echo "ERROR: Failed to download FRP from $FRP_DOWNLOAD_URL"
    echo "Check if version ${FRP_VERSION} exists at https://github.com/fatedier/frp/releases"
    exit 1
}

tar -xzf frp.tar.gz
cp -f "frp_${FRP_VERSION}_linux_${ARCH}/frps" "$INSTALL_DIR/frps"
chmod +x "$INSTALL_DIR/frps"
chown -R frp:frp "$INSTALL_DIR"
rm -rf "frp_${FRP_VERSION}_linux_${ARCH}" frp.tar.gz
echo "FRP binary installed to $INSTALL_DIR/frps"

# --- Create Server Configuration ---
echo ""
echo "[4/7] Creating server configuration..."
cat > /etc/frps.toml << EOF
# FRP Server Configuration
# Generated: $(date)
# Domain: ${FRP_DOMAIN}
bindPort = ${FRP_SERVER_PORT}
auth.token = "${FRP_TOKEN}"

# Dashboard
webServer.addr = "0.0.0.0"
webServer.port = ${FRP_DASHBOARD_PORT}
webServer.user = "${FRP_DASHBOARD_USER}"
webServer.password = "${FRP_DASHBOARD_PASS}"

# Transport
transport.tcpMux = true

# Port range for clients
allowPorts = [
  { start = ${CLIENT_PORT_RANGE_START}, end = ${CLIENT_PORT_RANGE_END} }
]

# Logging
log.to = "/var/log/frps.log"
log.level = "info"
log.maxDays = 3

# Performance
transport.maxPoolCount = 5
EOF
echo "Configuration written to /etc/frps.toml"

# --- Create Systemd Service ---
if [[ "$SKIP_SERVICE" == "true" ]]; then
    echo ""
    echo "[5/7] SKIPPING systemd service creation (--skip-service flag set)"
    echo "Manual start command: ${INSTALL_DIR}/frps -c /etc/frps.toml"
else
    echo ""
    echo "[5/7] Creating systemd service..."
    cat > /etc/systemd/system/frps.service << EOF
[Unit]
Description=FRP Server Service
Documentation=https://github.com/fatedier/frp
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=frp
Group=frp
ExecStart=${INSTALL_DIR}/frps -c /etc/frps.toml
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576
StandardOutput=journal
StandardError=journal
SyslogIdentifier=frps

# Security hardening
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=full
ProtectHome=yes

[Install]
WantedBy=multi-user.target
EOF
    echo "Systemd service created"
fi

# --- Configure Firewall ---
if [[ "$SKIP_FIREWALL" == "true" ]]; then
    echo ""
    echo "[6/7] SKIPPING firewall configuration (--skip-firewall flag set)"
    echo "Manual port openings needed:"
    echo "  - ${FRP_SERVER_PORT}/tcp (FRP Server)"
    echo "  - ${FRP_DASHBOARD_PORT}/tcp (Dashboard)"
    echo "  - 80/tcp (HTTP)"
    echo "  - 443/tcp (HTTPS)"
    echo "  - ${CLIENT_PORT_RANGE_START}-${CLIENT_PORT_RANGE_END}/tcp (Client ports)"
else
    echo ""
    echo "[6/7] Configuring firewall..."
    if command -v ufw &> /dev/null; then
        echo "y" | ufw --force reset 2>/dev/null || true
        ufw default deny incoming
        ufw default allow outgoing
        ufw allow ssh
        ufw allow ${FRP_SERVER_PORT}/tcp comment "FRP Server Bind Port"
        ufw allow ${FRP_DASHBOARD_PORT}/tcp comment "FRP Dashboard"
        ufw allow 80/tcp comment "HTTP"
        ufw allow 443/tcp comment "HTTPS"
        ufw allow ${CLIENT_PORT_RANGE_START}:${CLIENT_PORT_RANGE_END}/tcp comment "FRP Client Port Range"
        echo "y" | ufw --force enable
        echo "UFW configured"
    elif command -v firewall-cmd &> /dev/null; then
        systemctl start firewalld 2>/dev/null || true
        systemctl enable firewalld 2>/dev/null || true
        firewall-cmd --permanent --add-port=${FRP_SERVER_PORT}/tcp
        firewall-cmd --permanent --add-port=${FRP_DASHBOARD_PORT}/tcp
        firewall-cmd --permanent --add-port=80/tcp
        firewall-cmd --permanent --add-port=443/tcp
        firewall-cmd --permanent --add-port=${CLIENT_PORT_RANGE_START}-${CLIENT_PORT_RANGE_END}/tcp
        firewall-cmd --reload
        echo "Firewalld configured"
    else
        echo "WARNING: No supported firewall detected"
        echo "Manual port openings needed:"
        echo "  - ${FRP_SERVER_PORT}/tcp (FRP Server)"
        echo "  - ${FRP_DASHBOARD_PORT}/tcp (Dashboard)"
        echo "  - 80/tcp (HTTP)"
        echo "  - 443/tcp (HTTPS)"
        echo "  - ${CLIENT_PORT_RANGE_START}-${CLIENT_PORT_RANGE_END}/tcp (Client ports)"
    fi
fi

# --- Start Service ---
if [[ "$SKIP_SERVICE" == "true" ]]; then
    echo ""
    echo "[7/7] SKIPPING service start (--skip-service flag set)"
else
    echo ""
    echo "[7/7] Starting FRP service..."
    systemctl daemon-reload
    systemctl enable frps 2>/dev/null || true
    systemctl start frps 2>/dev/null || true
    sleep 3
fi

# --- Verify Installation ---
if [[ "$SKIP_SERVICE" == "true" ]]; then
    STATUS="⚠️  MANUAL START REQUIRED"
else
    if systemctl is-active --quiet frps; then
        STATUS="✅ ACTIVE AND RUNNING"
    else
        STATUS="❌ FAILED TO START (check: systemctl status frps)"
    fi
fi

echo ""
echo "Service status: $STATUS"

# --- Get Public IP ---
export PUBLIC_IP=$(curl -s4 --max-time 5 ifconfig.me 2>/dev/null || \
                   curl -s4 --max-time 5 ipinfo.io/ip 2>/dev/null || \
                   curl -s4 --max-time 5 icanhazip.com 2>/dev/null || \
                   echo "YOUR_VPS_IP")

# --- Generate Protocol File ---
echo ""
echo "Generating installation protocol..."

cat > "$LOG_FILE" << PROTOCOL_EOF
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
  Client Port Range: ${CLIENT_PORT_RANGE_START}-${CLIENT_PORT_RANGE_END}

==============================================
IMPORTANT: DNS SETUP
==============================================
Create an A record for your domain:
  ${FRP_DOMAIN} -> ${PUBLIC_IP}

Test DNS resolution:
  nslookup ${FRP_DOMAIN}
  ping ${FRP_DOMAIN}

==============================================
CLIENT INSTALLATION INSTRUCTIONS
==============================================

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
WINDOWS INSTALLATION GUIDE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Step 1: Download FRP Client
   URL: https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_windows_amd64.zip
   Save to: Downloads folder

Step 2: Extract Archive
   Right-click frp_${FRP_VERSION}_windows_amd64.zip -> Extract All
   Extract to: C:\frp\

Step 3: Create Configuration File
   Create new file: C:\frp\frpc.toml
   Contents:
\`\`\`toml
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
remotePort = ${CLIENT_PORT_RANGE_START}

# Example: Expose RDP (Remote Desktop)
[[proxies]]
name = "rdp-access"
type = "tcp"
localIP = "127.0.0.1"
localPort = 3389
remotePort = $((CLIENT_PORT_RANGE_START + 1))
\`\`\`

Step 4: Create Start Script
   Create file: C:\frp\start-frpc.bat
   Contents:
\`\`\`batch
@echo off
cd /d C:\frp
frpc.exe -c frpc.toml
pause
\`\`\`

Step 5: Run Client
   Double-click start-frpc.bat
   Or run from Command Prompt:
   C:\frp\frpc.exe -c C:\frp\frpc.toml

Step 6 (Optional): Install as Windows Service using NSSM
   1. Download NSSM: https://nssm.cc/download
   2. Extract nssm.exe to C:\frp\
   3. Open Command Prompt as Administrator:
   cd C:\frp
   nssm install FRPClient
   # Application Path: C:\frp\frpc.exe
   # Arguments: -c C:\frp\frpc.toml
   nssm start FRPClient

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
UBUNTU / DEBIAN INSTALLATION GUIDE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Step 1: Download FRP Client
\`\`\`bash
cd /tmp
wget https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_amd64.tar.gz
tar -xzf frp_${FRP_VERSION}_linux_amd64.tar.gz
sudo mkdir -p /opt/frpc
sudo cp frp_${FRP_VERSION}_linux_amd64/frpc /opt/frpc/
sudo chmod +x /opt/frpc/frpc
rm -rf frp_${FRP_VERSION}_linux_amd64 frp_${FRP_VERSION}_linux_amd64.tar.gz
\`\`\`

Step 2: Create Configuration
\`\`\`bash
sudo tee /etc/frpc.toml > /dev/null << 'CONFEOF'
# FRP Client Configuration
serverAddr = "${PUBLIC_IP}"
serverPort = ${FRP_SERVER_PORT}
auth.token = "${FRP_TOKEN}"

# Example: Expose local SSH
[[proxies]]
name = "ssh-access"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = $((CLIENT_PORT_RANGE_START + 2))

# Example: Expose local web server
[[proxies]]
name = "web-local"
type = "tcp"
localIP = "127.0.0.1"
localPort = 80
remotePort = $((CLIENT_PORT_RANGE_START + 3))
CONFEOF
\`\`\`

Step 3: Create Systemd Service
\`\`\`bash
sudo tee /etc/systemd/system/frpc.service > /dev/null << 'SERVICEEOF'
[Unit]
Description=FRP Client Service
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/opt/frpc/frpc -c /etc/frpc.toml
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
SERVICEEOF
\`\`\`

Step 4: Enable and Start
\`\`\`bash
sudo systemctl daemon-reload
sudo systemctl enable frpc
sudo systemctl start frpc
sudo systemctl status frpc
\`\`\`

Step 5: View Logs (if needed)
\`\`\`bash
journalctl -u frpc -f
\`\`\`

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ALMALINUX / RHEL / ROCKY LINUX GUIDE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Step 1: Download FRP Client
\`\`\`bash
cd /tmp
wget https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_amd64.tar.gz
tar -xzf frp_${FRP_VERSION}_linux_amd64.tar.gz
sudo mkdir -p /opt/frpc
sudo cp frp_${FRP_VERSION}_linux_amd64/frpc /opt/frpc/
sudo chmod +x /opt/frpc/frpc
rm -rf frp_${FRP_VERSION}_linux_amd64 frp_${FRP_VERSION}_linux_amd64.tar.gz
\`\`\`

Step 2: Configure SELinux (if enabled)
\`\`\`bash
# Check if SELinux is enforcing
getenforce
# If Enforcing, set context:
sudo semanage fcontext -a -t bin_t /opt/frpc/frpc 2>/dev/null || true
sudo restorecon -v /opt/frpc/frpc
# Or temporarily disable (not recommended for production):
# sudo setenforce 0
\`\`\`

Step 3: Create Configuration
\`\`\`bash
sudo tee /etc/frpc.toml > /dev/null << 'CONFEOF'
# FRP Client Configuration
serverAddr = "${PUBLIC_IP}"
serverPort = ${FRP_SERVER_PORT}
auth.token = "${FRP_TOKEN}"

# Example: Expose local web server
[[proxies]]
name = "web-service"
type = "tcp"
localIP = "127.0.0.1"
localPort = 80
remotePort = $((CLIENT_PORT_RANGE_START + 4))
CONFEOF
\`\`\`

Step 4: Create Systemd Service
\`\`\`bash
sudo tee /etc/systemd/system/frpc.service > /dev/null << 'SERVICEEOF'
[Unit]
Description=FRP Client Service
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/opt/frpc/frpc -c /etc/frpc.toml
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
SERVICEEOF
\`\`\`

Step 5: Configure Firewall
\`\`\`bash
# Allow client ports (do NOT open on client, these are for reference)
sudo firewall-cmd --permanent --add-port=$((CLIENT_PORT_RANGE_START + 4))/tcp
sudo firewall-cmd --reload
# Verify:
sudo firewall-cmd --list-ports
\`\`\`

Step 6: Enable and Start Service
\`\`\`bash
sudo systemctl daemon-reload
sudo systemctl enable frpc
sudo systemctl start frpc
sudo systemctl status frpc
\`\`\`

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
COMMON PROXY CONFIGURATION EXAMPLES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Add these to your frpc.toml on the client:

# HTTPS website
[[proxies]]
name = "web-https"
type = "tcp"
localIP = "127.0.0.1"
localPort = 443
remotePort = $((CLIENT_PORT_RANGE_START + 5))

# MySQL/MariaDB database
[[proxies]]
name = "mysql"
type = "tcp"
localIP = "127.0.0.1"
localPort = 3306
remotePort = $((CLIENT_PORT_RANGE_START + 6))

# PostgreSQL database
[[proxies]]
name = "postgresql"
type = "tcp"
localIP = "127.0.0.1"
localPort = 5432
remotePort = $((CLIENT_PORT_RANGE_START + 7))

# Minecraft server
[[proxies]]
name = "minecraft"
type = "tcp"
localIP = "127.0.0.1"
localPort = 25565
remotePort = $((CLIENT_PORT_RANGE_START + 8))

# VNC remote desktop
[[proxies]]
name = "vnc"
type = "tcp"
localIP = "127.0.0.1"
localPort = 5900
remotePort = $((CLIENT_PORT_RANGE_START + 9))

# FTP server
[[proxies]]
name = "ftp"
type = "tcp"
localIP = "127.0.0.1"
localPort = 21
remotePort = $((CLIENT_PORT_RANGE_START + 10))

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TROUBLESHOOTING
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Check Server Status (on VPS):
  systemctl status frps
  journalctl -u frps -f
  tail -f /var/log/frps.log

Check Client Status (on client):
  systemctl status frpc
  journalctl -u frpc -f

Test server connectivity from client:
  telnet ${PUBLIC_IP} ${FRP_SERVER_PORT}
  nc -zv ${PUBLIC_IP} ${FRP_SERVER_PORT}

Test your exposed service:
  curl http://${PUBLIC_IP}:${CLIENT_PORT_RANGE_START}
  ssh user@${PUBLIC_IP} -p $((CLIENT_PORT_RANGE_START + 2))

Dashboard Access:
  URL: http://${PUBLIC_IP}:${FRP_DASHBOARD_PORT}
  Username: ${FRP_DASHBOARD_USER}
  Password: ${FRP_DASHBOARD_PASS}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
IMPORTANT SECURITY NOTES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. CHANGE DEFAULT PASSWORDS - This is critical!
   Edit /etc/frps.toml and change dashboard password

2. Use strong auth.token on all clients

3. Each remote port MUST be unique across all clients
   Available range: ${CLIENT_PORT_RANGE_START}-${CLIENT_PORT_RANGE_END}

4. For production use:
   - Set up SSL/TLS encryption
   - Restrict dashboard access to specific IPs
   - Use SSH tunneling for sensitive services

5. Regular updates:
   Check for new FRP versions at:
   https://github.com/fatedier/frp/releases

6. Firewall best practices:
   - Only open necessary ports
   - Use UFW/firewalld rate limiting
   - Monitor logs regularly

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
QUICK START CHECKLIST
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Server Setup (already completed):
☑ FRP Server installed at ${INSTALL_DIR}/frps
☑ Configuration at /etc/frps.toml
☑ Systemd service: frps
☑ Firewall configured
☑ Dashboard: http://${PUBLIC_IP}:${FRP_DASHBOARD_PORT}

Client Setup (to be completed on each client):
☐ Download FRP client binary
☐ Create frpc.toml with proper configuration
☐ Test connection to server
☐ Set up as service for auto-start
☐ Verify remote access works

==============================================
END OF INSTALLATION PROTOCOL
Generated: $(date)
Server IP: ${PUBLIC_IP}
==============================================
PROTOCOL_EOF

# --- Cleanup ---
rm -rf /tmp/frp.tar.gz /tmp/frp_* 2>/dev/null || true

# --- Final Summary ---
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║           FRP SERVER INSTALLATION COMPLETE              ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "Status: $STATUS"
echo "Protocol saved to: $LOG_FILE"
echo ""
echo "Connection Details:"
echo "  Server Address:  ${PUBLIC_IP}:${FRP_SERVER_PORT}"
echo "  Auth Token:      ${FRP_TOKEN}"
echo "  Dashboard:       http://${PUBLIC_IP}:${FRP_DASHBOARD_PORT}"
echo "  Dashboard User:  ${FRP_DASHBOARD_USER}"
echo "  Dashboard Pass:  ${FRP_DASHBOARD_PASS}"
echo ""
echo "Copy protocol to local machine:"
echo "  scp root@${PUBLIC_IP}:${LOG_FILE} ./frp-install-guide.txt"
echo ""
echo "View protocol on server:"
echo "  cat $LOG_FILE"
echo ""

exit 0