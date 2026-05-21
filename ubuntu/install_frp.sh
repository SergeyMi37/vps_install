#!/bin/bash
# sudo wget https://raw.githubusercontent.com/SergeyMi37/vps_install/master/ubuntu/install_frp.sh && sudo chmod +x install_frp.sh && sudo ./install_frp.sh -d frp.mydomain.com

# 1. Базовая установка с доменом:
# bash
# ./install_frp.sh --domain frp.example.com

# 2. Установка с Caddy прокси:
# ./install_frp.sh \
#   --domain example.com \
#   --setup-caddy \
#   --caddy-email admin@example.com \
#   --proxy-pass "frp.example.com:7500" \
#   --proxy-pass "gitea.example.com:3000" \
#   --proxy-pass "jenkins.example.com:8080"

# 3. Дополнение существующей конфигурации:
# ./iinstall_frp.sh \
#   --domain example.com \
#   --setup-caddy \
#   --proxy-pass "nas.example.site:192.168.1.100:5000" \
#   --proxy-pass "plex.example.site:192.168.1.100:32400" \
#   --proxy-pass "camera.example.site:192.168.1.50:8080"

# ==============================================
# FRP Server + Caddy Proxy Auto-Install Script
# Version: 5.0 - With Configuration Merge Support
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

# --- Caddy Configuration ---
SETUP_CADDY=false
CADDY_VERSION="2.8.4"
CADDY_EMAIL=""
declare -A PROXY_PASSES
PROXY_PASSES_STR=""

# --- Usage Function ---
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

FRP Server + Caddy Proxy Auto-Install Script with Configuration Merge

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
    
    CADDY OPTIONS:
    --setup-caddy                  Install and configure Caddy reverse proxy (merges with existing config)
    --caddy-email EMAIL            Email for Let's Encrypt notifications
    --proxy-pass DOMAIN:TARGET     Add proxy rule (can be used multiple times, merges with existing)
                                   Examples:
                                   --proxy-pass "frp.example.com:7500"
                                   --proxy-pass "gitea.example.com:3000"
                                   --proxy-pass "nas.example.com:192.168.1.100:5000"
    
    -h, --help                     Show this help message

EXAMPLES:
    # First installation
    $0 --domain example.com \\
       --setup-caddy \\
       --caddy-email admin@example.com \\
       --proxy-pass "frp.example.com:7500" \\
       --proxy-pass "gitea.example.com:3000"

    # Second installation (adds new proxies, keeps existing)
    $0 --domain example.com \\
       --setup-caddy \\
       --proxy-pass "jenkins.example.com:8080" \\
       --proxy-pass "nextcloud.example.com:8081"

    # Update existing proxy
    $0 --domain example.com \\
       --setup-caddy \\
       --proxy-pass "gitea.example.com:8082"  # Updates port from 3000 to 8082

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
        --setup-caddy)
            SETUP_CADDY=true
            shift
            ;;
        --caddy-email)
            CADDY_EMAIL="$2"
            shift 2
            ;;
        --proxy-pass)
            PROXY_PASSES_STR="$PROXY_PASSES_STR|$2"
            shift 2
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

# --- Parse Proxy Passes ---
if [[ -n "$PROXY_PASSES_STR" ]]; then
    IFS='|' read -ra PROXY_ARRAY <<< "$PROXY_PASSES_STR"
    for item in "${PROXY_ARRAY[@]}"; do
        if [[ -n "$item" ]]; then
            domain=$(echo "$item" | cut -d':' -f1)
            target=$(echo "$item" | cut -d':' -f2-)
            if [[ -n "$domain" && -n "$target" ]]; then
                PROXY_PASSES["$domain"]="$target"
            fi
        fi
    done
fi

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
    echo "  Setup Caddy:       $SETUP_CADDY"
    echo "  Caddy Email:       ${CADDY_EMAIL:-'Not set'}"
    if [[ ${#PROXY_PASSES[@]} -gt 0 ]]; then
        echo "  New/Updated Proxy Rules:"
        for domain in "${!PROXY_PASSES[@]}"; do
            echo "    $domain -> ${PROXY_PASSES[$domain]}"
        done
    fi
    echo ""
    exit 0
fi

# --- Create Log Directory ---
mkdir -p "$(dirname "$LOG_FILE")"

# --- Initialize Logging ---
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=============================================="
echo "FRP Server + Caddy Installation Protocol"
echo "Started at: $(date)"
echo "Domain: $FRP_DOMAIN"
echo "=============================================="
echo ""
echo "Configuration:"
echo "  FRP Version:       $FRP_VERSION"
echo "  Domain:            $FRP_DOMAIN"
echo "  Server Port:       $FRP_SERVER_PORT"
echo "  Dashboard Port:    $FRP_DASHBOARD_PORT"
echo "  Client Port Range: ${CLIENT_PORT_RANGE_START}-${CLIENT_PORT_RANGE_END}"
echo "  Setup Caddy:       $SETUP_CADDY"
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
echo "[1/9] Installing dependencies..."
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
echo "[2/9] Creating frp system user..."
if ! id -u frp &>/dev/null; then
    useradd -r -s /bin/false frp 2>/dev/null || \
    useradd --system --no-create-home --shell /bin/false frp 2>/dev/null || \
    adduser --system --no-create-home --shell /bin/false frp 2>/dev/null || true
fi
echo "User frp ready"

# --- Download and Extract FRP ---
echo ""
echo "[3/9] Downloading FRP version ${FRP_VERSION} for ${ARCH}..."
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
echo "[4/9] Creating server configuration..."
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
    echo "[5/9] SKIPPING systemd service creation (--skip-service flag set)"
    echo "Manual start command: ${INSTALL_DIR}/frps -c /etc/frps.toml"
else
    echo ""
    echo "[5/9] Creating systemd service..."
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
    echo "[6/9] SKIPPING firewall configuration (--skip-firewall flag set)"
else
    echo ""
    echo "[6/9] Configuring firewall..."
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
    fi
fi

# --- Function to Merge Caddy Configuration ---
merge_caddy_config() {
    local caddyfile="/etc/caddy/Caddyfile"
    local temp_file="/tmp/caddyfile_temp_$$"
    local backup_file="/etc/caddy/Caddyfile.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Create backup of existing config
    if [[ -f "$caddyfile" ]]; then
        cp "$caddyfile" "$backup_file"
        echo "✅ Backup created: $backup_file"
    fi
    
    # Extract existing domains
    declare -A existing_domains
    if [[ -f "$caddyfile" ]]; then
        while IFS= read -r line; do
            if [[ "$line" =~ ^([a-zA-Z0-9.-]+)\s*\{\s*$ ]]; then
                existing_domain="${BASH_REMATCH[1]}"
                existing_domains["$existing_domain"]=1
            fi
        done < "$caddyfile"
    fi
    
    # Start building new config
    {
        echo "# Caddy reverse proxy configuration"
        echo "# Last merged on: $(date)"
        echo ""
        echo "# Global options"
        echo "{"
        echo "    email ${CADDY_EMAIL:-admin@${FRP_DOMAIN#*.}}"
        echo "}"
        echo ""
        
        # Copy non-proxy blocks from existing config if they exist
        if [[ -f "$caddyfile" ]]; then
            in_proxy_block=0
            while IFS= read -r line; do
                # Skip proxy blocks
                if [[ "$line" =~ ^([a-zA-Z0-9.-]+)\s*\{\s*$ ]]; then
                    in_proxy_block=1
                    continue
                fi
                if [[ "$in_proxy_block" -eq 1 ]] && [[ "$line" =~ ^\}\s*$ ]]; then
                    in_proxy_block=0
                    continue
                fi
                # Add non-proxy lines (like header, file_server blocks for main domain)
                if [[ $in_proxy_block -eq 0 ]] && [[ -n "$line" ]] && [[ ! "$line" =~ ^#.*$ ]]; then
                    if [[ ! "$line" =~ ^[a-zA-Z0-9.-]+\ {$ ]] && [[ "$line" != "}" ]] && [[ "$line" != "{" ]]; then
                        echo "$line"
                    fi
                fi
            done < "$caddyfile"
        fi
        
        echo ""
        
        # Add all proxy rules (existing + new, with new taking precedence)
        if [[ -f "$caddyfile" ]]; then
            while IFS= read -r line; do
                if [[ "$line" =~ ^([a-zA-Z0-9.-]+)\s*\{\s*$ ]]; then
                    domain="${BASH_REMATCH[1]}"
                    # Check if this domain should be updated with new rule
                    if [[ -n "${PROXY_PASSES[$domain]:-}" ]]; then
                        # Skip, will be added later with new config
                        # Read until closing brace to skip the block
                        while IFS= read -r inner_line; do
                            if [[ "$inner_line" =~ ^\}\s*$ ]]; then
                                break
                            fi
                        done
                    else
                        # Keep existing rule
                        echo "$line"
                        while IFS= read -r inner_line; do
                            echo "$inner_line"
                            if [[ "$inner_line" =~ ^\}\s*$ ]]; then
                                break
                            fi
                        done
                        echo ""
                    fi
                fi
            done < "$caddyfile"
        fi
        
        # Add new/updated proxy rules
        for domain in "${!PROXY_PASSES[@]}"; do
            target="${PROXY_PASSES[$domain]}"
            # Convert port-only to localhost:port
            if [[ "$target" =~ ^[0-9]+$ ]]; then
                target="127.0.0.1:$target"
            fi
            
            cat << CADDYBLOCK

# Proxy rule for $domain (added/updated on $(date))
$domain {
    # Reverse proxy to backend
    reverse_proxy $target {
        # Pass real IP to backend
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
    
    # Security headers
    header {
        X-Content-Type-Options nosniff
        X-Frame-Options DENY
        X-XSS-Protection "1; mode=block"
    }
    
    # Logging
    log {
        output file /var/log/caddy/${domain}.log
    }
}

CADDYBLOCK
        done
        
        # Add default catch-all for main domain if no existing rule
        main_domain="${FRP_DOMAIN#*.}"
        if [[ -z "${existing_domains[$main_domain]:-}" ]] && [[ -z "${PROXY_PASSES[$main_domain]:-}" ]]; then
            cat << CADDYBLOCK

# Default catch-all rule for main domain
$main_domain {
    root * /var/www/html
    file_server browse
    try_files {path} index.html
    
    # Custom 404 page
    handle_errors {
        rewrite * /404.html
        file_server
    }
}

CADDYBLOCK
        fi
        
    } > "$temp_file"
    
    # Validate and apply new configuration
    if caddy validate --config "$temp_file" 2>/dev/null; then
        mv "$temp_file" "$caddyfile"
        echo "✅ Caddy configuration merged successfully"
        return 0
    else
        echo "❌ Invalid Caddy configuration, keeping existing"
        rm -f "$temp_file"
        return 1
    fi
}

# --- Function to Update Info Page ---
update_info_page() {
    local info_page="/var/www/html/index.html"
    
    mkdir -p /var/www/html
    
    cat > "$info_page" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>FRP Proxy Server - Active Proxies</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        
        .container {
            max-width: 900px;
            margin: 0 auto;
            background: rgba(255,255,255,0.95);
            border-radius: 20px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            overflow: hidden;
        }
        
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 40px;
            text-align: center;
        }
        
        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
        }
        
        .header p {
            font-size: 1.1em;
            opacity: 0.9;
        }
        
        .content {
            padding: 40px;
        }
        
        .section {
            margin-bottom: 30px;
        }
        
        .section h2 {
            color: #667eea;
            margin-bottom: 20px;
            font-size: 1.5em;
            border-bottom: 2px solid #e0e0e0;
            padding-bottom: 10px;
        }
        
        .proxy-list {
            background: #f8f9fa;
            border-radius: 10px;
            overflow: hidden;
        }
        
        .proxy-item {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 15px 20px;
            border-bottom: 1px solid #e0e0e0;
            transition: background 0.3s;
        }
        
        .proxy-item:hover {
            background: #e9ecef;
        }
        
        .proxy-item:last-child {
            border-bottom: none;
        }
        
        .proxy-domain {
            font-weight: 600;
            color: #495057;
            font-size: 1.1em;
        }
        
        .proxy-domain a {
            color: #667eea;
            text-decoration: none;
        }
        
        .proxy-domain a:hover {
            text-decoration: underline;
        }
        
        .proxy-target {
            font-family: 'Monaco', 'Courier New', monospace;
            color: #28a745;
            background: white;
            padding: 5px 10px;
            border-radius: 5px;
            font-size: 0.9em;
        }
        
        .badge {
            display: inline-block;
            padding: 3px 8px;
            border-radius: 4px;
            font-size: 0.8em;
            font-weight: 600;
        }
        
        .badge-https {
            background: #28a745;
            color: white;
        }
        
        .footer {
            background: #f8f9fa;
            padding: 20px;
            text-align: center;
            color: #6c757d;
            font-size: 0.9em;
        }
        
        .last-updated {
            margin-top: 20px;
            text-align: center;
            color: #6c757d;
            font-size: 0.85em;
        }
        
        @media (max-width: 768px) {
            .proxy-item {
                flex-direction: column;
                align-items: flex-start;
                gap: 10px;
            }
            
            .header h1 {
                font-size: 1.8em;
            }
            
            .content {
                padding: 20px;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 FRP Proxy Server</h1>
            <p>Reverse Proxy with Automatic HTTPS</p>
        </div>
        
        <div class="content">
            <div class="section">
                <h2>📡 Active Proxy Rules</h2>
                <div class="proxy-list">
HTMLEOF

    # Add proxy rules from Caddyfile
    if [[ -f /etc/caddy/Caddyfile ]]; then
        while IFS= read -r line; do
            if [[ "$line" =~ ^([a-zA-Z0-9.-]+)\s*\{\s*$ ]]; then
                domain="${BASH_REMATCH[1]}"
                # Extract target
                target=$(sed -n "/^$domain {$/,/^}/p" /etc/caddy/Caddyfile | grep "reverse_proxy" | head -1 | awk '{print $2}')
                if [[ -z "$target" ]]; then
                    target="unknown"
                fi
                cat >> "$info_page" << HTMLEOF
                    <div class="proxy-item">
                        <div class="proxy-domain">
                            <span class="badge badge-https">HTTPS</span>
                            <a href="https://$domain" target="_blank">$domain</a>
                        </div>
                        <div class="proxy-target">→ $target</div>
                    </div>
HTMLEOF
            fi
        done < /etc/caddy/Caddyfile
    fi

    cat >> "$info_page" << HTMLEOF
                </div>
            </div>
        </div>
        
        <div class="footer">
            <p>Powered by <strong>Caddy</strong> + <strong>FRP</strong></p>
            <p>All HTTPS certificates are automatically managed by Let's Encrypt</p>
        </div>
        
        <div class="last-updated">
            Last updated: $(date)
        </div>
    </div>
</body>
</html>
HTMLEOF
    
    echo "✅ Info page updated: /var/www/html/index.html"
}

# --- Install and Configure Caddy ---
if [[ "$SETUP_CADDY" == "true" ]]; then
    echo ""
    echo "[7/9] Installing and configuring Caddy reverse proxy..."
    
    # Check if Caddy is already installed
    if ! command -v caddy &> /dev/null; then
        echo "Installing Caddy..."
        apt-get install -y -qq debian-keyring debian-archive-keyring apt-transport-https
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
        apt-get update -qq
        apt-get install -y -qq caddy
        echo "✅ Caddy installed successfully"
    else
        echo "✅ Caddy already installed"
    fi
    
    # Create necessary directories
    mkdir -p /etc/caddy
    mkdir -p /var/log/caddy
    mkdir -p /var/www/html
    chown -R caddy:caddy /var/log/caddy 2>/dev/null || true
    
    # Merge or create configuration
    if [[ -f /etc/caddy/Caddyfile ]]; then
        echo "Existing Caddy configuration found. Merging rules..."
        if merge_caddy_config; then
            echo "✅ Configuration merged successfully"
        else
            echo "⚠️  Merge failed, keeping existing configuration"
        fi
    else
        echo "Creating new Caddy configuration..."
        # Create initial config with new rules
        cat > /etc/caddy/Caddyfile << CADDYEOF
# Caddy reverse proxy configuration
# Created on $(date)

# Global options
{
    email ${CADDY_EMAIL:-admin@${FRP_DOMAIN#*.}}
}

CADDYEOF
        
        # Add proxy rules
        for domain in "${!PROXY_PASSES[@]}"; do
            target="${PROXY_PASSES[$domain]}"
            if [[ "$target" =~ ^[0-9]+$ ]]; then
                target="127.0.0.1:$target"
            fi
            cat >> /etc/caddy/Caddyfile << CADDYEOF

# Proxy rule for $domain
$domain {
    reverse_proxy $target {
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
    
    header {
        X-Content-Type-Options nosniff
        X-Frame-Options DENY
        X-XSS-Protection "1; mode=block"
    }
    
    log {
        output file /var/log/caddy/${domain}.log
    }
}

CADDYEOF
        done
        
        # Add default catch-all
        main_domain="${FRP_DOMAIN#*.}"
        cat >> /etc/caddy/Caddyfile << CADDYEOF

# Default catch-all rule for main domain
$main_domain {
    root * /var/www/html
    file_server browse
    try_files {path} index.html
}

CADDYEOF
        echo "✅ New configuration created"
    fi
    
    # Update info page
    update_info_page
    
    # Start/enable Caddy service
    systemctl daemon-reload
    systemctl enable caddy
    
    # Validate config before restart
    if caddy validate --config /etc/caddy/Caddyfile 2>/dev/null; then
        systemctl restart caddy
        echo "✅ Caddy restarted successfully"
    else
        echo "⚠️  Configuration validation failed, check /etc/caddy/Caddyfile"
        echo "Rolling back to previous configuration if backup exists"
        if [[ -f /etc/caddy/Caddyfile.backup.* ]]; then
            latest_backup=$(ls -t /etc/caddy/Caddyfile.backup.* | head -1)
            cp "$latest_backup" /etc/caddy/Caddyfile
            systemctl restart caddy
            echo "✅ Rolled back to $latest_backup"
        fi
    fi
    
    # Display active proxy rules
    echo ""
    echo "Active proxy rules after merge:"
    grep -E "^[a-zA-Z0-9.-]+\s+\{$" /etc/caddy/Caddyfile | sed 's/ {$//' | while read -r domain; do
        target=$(sed -n "/^$domain {$/,/^}/p" /etc/caddy/Caddyfile | grep "reverse_proxy" | head -1 | awk '{print $2}')
        echo "  🌐 https://$domain -> $target"
    done
else
    echo ""
    echo "[7/9] SKIPPING Caddy installation (--setup-caddy flag not set)"
fi

# --- Start FRP Service ---
if [[ "$SKIP_SERVICE" == "true" ]]; then
    echo ""
    echo "[8/9] SKIPPING service start (--skip-service flag set)"
else
    echo ""
    echo "[8/9] Starting FRP service..."
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
echo "[9/9] Installation complete"
echo "Service status: $STATUS"

# --- Get Public IP ---
PUBLIC_IP=$(curl -s4 --max-time 5 ifconfig.me 2>/dev/null || \
           curl -s4 --max-time 5 ipinfo.io/ip 2>/dev/null || \
           curl -s4 --max-time 5 icanhazip.com 2>/dev/null || \
           echo "YOUR_VPS_IP")

# --- Generate