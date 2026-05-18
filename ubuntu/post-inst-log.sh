#!/bin/bash
set -e

# Конфигурация
NEW_USER="msw"
NEW_USER_PASSWORD="P@S5w0rd"
SSH_KEY="ssh-ed25519 AAAAC3... user@host"
SSH_PORT="2222"
LOG_FILE="/home/${NEW_USER}/post-install.log"

# Функция логирования
log() { echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG_FILE"; }

# Инициализация лога
mkdir -p "/home/${NEW_USER}" 2>/dev/null
echo "=== POST-INSTALL START: $(date) ===" > "$LOG_FILE"

# Callback
SERVER_IP=$(ip -4 route get 1 | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' 2>/dev/null || curl -s ifconfig.me)
send_callback() { curl -s -X GET "http://${SERVER_IP}:8080/hostkey/callback?status=$1${2:+&Code=$2}" --max-time 5 >/dev/null 2>&1 & }

# Обработка ошибок
trap 'send_callback "Err" "LINE_${LINENO}: $BASH_COMMAND"; log "ERROR at line ${LINENO}"; exit 1' ERR

log "=== ЧАСТЬ A: Создание пользователя ==="
id "$NEW_USER" &>/dev/null || { useradd -m -s /bin/bash "$NEW_USER"; echo "$NEW_USER:$NEW_USER_PASSWORD" | chpasswd; usermod -aG sudo "$NEW_USER"; log "User $NEW_USER created"; }
[[ -n "$SSH_KEY" ]] && { mkdir -p "/home/$NEW_USER/.ssh"; echo "$SSH_KEY" >> "/home/$NEW_USER/.ssh/authorized_keys"; chmod 700 "/home/$NEW_USER/.ssh"; log "SSH key added"; }

log "=== ЧАСТЬ B: Установка Docker ==="
export DEBIAN_FRONTEND=noninteractive
apt update -qq && apt upgrade -y -qq
apt install -y -qq ca-certificates curl gnupg lsb-release git net-tools make mc
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor --yes -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update -qq
apt install -y -qq docker-ce docker-ce-cli containerd.io
usermod -aG docker "$NEW_USER"
curl -sL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose && chmod +x /usr/local/bin/docker-compose
log "Docker installed: $(docker --version)"

log "=== ЧАСТЬ C: SSH безопасность ==="
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
sed -i "/^[#[:space:]]*Port/d; /^[#[:space:]]*PermitRootLogin/d; /^[#[:space:]]*PasswordAuthentication/d" /etc/ssh/sshd_config
cat >> /etc/ssh/sshd_config << EOF
Port $SSH_PORT
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AllowUsers $NEW_USER
EOF
sshd -t && systemctl restart ssh
log "SSH configured on port $SSH_PORT"

# Финальный лог и callback
chown "$NEW_USER:" "$LOG_FILE"
echo "=== POST-INSTALL SUCCESS: $(date) ===" >> "$LOG_FILE"
send_callback "OK" ""
log "✅ Setup complete! Log saved to $LOG_FILE"
