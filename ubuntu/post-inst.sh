#!/bin/bash
set -e  # Прерывать выполнение при ошибке

# ==============================================
# ЕДИНЫЙ POST-INSTALL СКРИПТ ДЛЯ HOSTKEY VPS
# Абсолютно неинтерактивный, с callback уведомлениями
# ==============================================

# --- 1. Параметры конфигурации (измените под себя) ---
NEW_USER="msw"
NEW_USER_PASSWORD="P@S5w0rd"
SSH_KEY="ssh-ed25519 AAAAC3... user@host"
SSH_PORT="2222"

# --- 2. Настройки Callback ---
# Определяем реальный IP сервера (для callback)
SERVER_IP=$(ip -4 route get 1 | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' 2>/dev/null || curl -s ifconfig.me 2>/dev/null || echo "unknown")
CALLBACK_BASE_URL="http://${SERVER_IP}:8080/hostkey/callback"  # ИЗМЕНИТЕ ПОРТ ПРИ НЕОБХОДИМОСТИ

# --- 3. Функции для callback уведомлений ---
send_callback() {
    local status="$1"
    local error_info="$2"
    local url=""
    
    if [[ "$status" == "OK" ]]; then
        url="${CALLBACK_BASE_URL}?status=OK"
    else
        # Экранируем спецсимволы для URL
        local encoded_error=$(echo "$error_info" | sed 's/ /%20/g; s/&/%26/g; s/?/%3F/g')
        url="${CALLBACK_BASE_URL}?status=Err&Code=${encoded_error}"
    fi
    
    # Отправляем callback (не ждём ответа, не прерываем скрипт при ошибке)
    curl -s -X GET "$url" --max-time 5 --connect-timeout 2 >/dev/null 2>&1 &
    echo "[CALLBACK] Отправлен: $url"
}

# Функция вызова при ошибке с указанием строки
error_exit() {
    local line_number=$1
    local error_message=$2
    local error_code="LINE_${line_number}: ${error_message}"
    
    echo "[ERROR] Произошла ошибка: $error_code"
    send_callback "Err" "$error_code"
    exit 1
}

# Перехват ошибок с указанием строки
trap 'error_exit ${LINENO} "Неожиданная ошибка (код $?)"' ERR

# --- 4. Логирование (тихий режим) ---
log_info() { echo "[INFO] $1"; }
log_warn() { echo "[WARN] $1"; }
log_error() { echo "[ERROR] $1"; }

# ==============================================
# ЧАСТЬ A: Создание пользователя (из vps_ubuntu_newuser.sh)
# ==============================================
log_info "=== ЧАСТЬ A: Создание пользователя $NEW_USER ==="

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
    error_exit ${LINENO} "Скрипт должен запускаться с правами root"
fi

# Создание пользователя, если не существует
if id "$NEW_USER" &>/dev/null; then
    log_warn "Пользователь $NEW_USER уже существует, пропускаем создание"
else
    useradd -m -s /bin/bash "$NEW_USER" || error_exit ${LINENO} "Не удалось создать пользователя"
    echo "$NEW_USER:$NEW_USER_PASSWORD" | chpasswd || error_exit ${LINENO} "Не удалось установить пароль"
    usermod -aG sudo "$NEW_USER" || error_exit ${LINENO} "Не удалось добавить в группу sudo"
    log_info "Пользователь $NEW_USER создан"
fi

# Добавление bash-алиасов (без интерактива)
cat >> "/home/$NEW_USER/.bashrc" << 'EOF'
alias myip='wget -qO myip http://www.ipchicken.com/; grep -o "[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}" myip; rm myip'
alias ver='cat /etc/*-release'
alias mc='mc -S gotar'
alias hi='history | grep'
alias lsrt='ls --human-readable --size -1 -S --classify'

if [[ $- == *i* ]]; then
    bind '"\e[5~": history-search-backward'
    bind '"\e[6~": history-search-forward'
fi

export HISTSIZE=10000
export HISTFILESIZE=10000
export HISTCONTROL=ignoreboth:erasedups
export PROMPT_COMMAND='history -a'
export HISTIGNORE='ls:ps:hi:pwd'
export HISTTIMEFORMAT='%d.%m.%Y %H:%M:%S: '

export COMPOSE_DOCKER_CLI_BUILD=1
export DOCKER_BUILDKIT=1
export EDITOR=mcedit

alias dockersrm='docker stop $(docker ps -a -q) && docker rm $(docker ps -a -q) -f && docker system prune -f'
alias dockersrmi='docker rmi $(docker images -q) -f && docker system prune -f'
alias dcserv='docker compose ps --services'
EOF

# Добавление SSH-ключа, если он задан
if [[ -n "$SSH_KEY" ]]; then
    mkdir -p "/home/$NEW_USER/.ssh"
    echo "$SSH_KEY" >> "/home/$NEW_USER/.ssh/authorized_keys"
    chmod 700 "/home/$NEW_USER/.ssh"
    chmod 600 "/home/$NEW_USER/.ssh/authorized_keys"
    chown -R "$NEW_USER:$NEW_USER" "/home/$NEW_USER/.ssh"
    log_info "SSH-ключ добавлен"
fi

log_info "Часть A завершена"

# ==============================================
# ЧАСТЬ B: Установка Docker и утилит (из vps_ubuntu.sh)
# ==============================================
log_info "=== ЧАСТЬ B: Обновление системы и установка Docker ==="

# Обновление системы (неинтерактивно)
export DEBIAN_FRONTEND=noninteractive
apt update -qq || error_exit ${LINENO} "Не удалось обновить списки пакетов"
apt upgrade -y -qq || error_exit ${LINENO} "Не удалось обновить пакеты"

# Установка утилит
apt install -y -qq ca-certificates curl gnupg lsb-release git net-tools make mc || error_exit ${LINENO} "Не удалось установить утилиты"

# Установка Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg || error_exit ${LINENO} "Ошибка при добавлении GPG ключа Docker"
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update -qq || error_exit ${LINENO} "Ошибка при обновлении после добавления Docker репозитория"
apt install -y -qq docker-ce docker-ce-cli containerd.io || error_exit ${LINENO} "Не удалось установить Docker"

# Добавление пользователя в группу docker
usermod -aG docker "$NEW_USER" || error_exit ${LINENO} "Не удалось добавить пользователя в группу docker"

# Установка Docker Compose
DOCKER_COMPOSE_VERSION="$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d '"' -f 4)"
if [[ -n "$DOCKER_COMPOSE_VERSION" ]]; then
    curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose || error_exit ${LINENO} "Не удалось скачать Docker Compose"
    chmod +x /usr/local/bin/docker-compose
    log_info "Docker Compose ${DOCKER_COMPOSE_VERSION} установлен"
else
    log_warn "Не удалось определить версию Docker Compose, пропускаем"
fi

log_info "Часть B завершена"

# ==============================================
# ЧАСТЬ C: Безопасная настройка SSH (из vps_ubuntu_newssh.sh)
# ==============================================
log_info "=== ЧАСТЬ C: Настройка безопасности SSH ==="

SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP_FILE="/etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)"

# Резервная копия
cp "$SSHD_CONFIG" "$BACKUP_FILE" || error_exit ${LINENO} "Не удалось создать резервную копию sshd_config"
log_info "Резервная копия создана"

# Функция обновления параметров SSH
update_ssh_config() {
    local param="$1"
    local value="$2"
    sed -i "/^[#[:space:]]*$param/d" "$SSHD_CONFIG"
    echo "$param $value" >> "$SSHD_CONFIG"
}

# Применение безопасных настроек (без интерактива)
update_ssh_config "Port" "$SSH_PORT"
update_ssh_config "PermitRootLogin" "no"
update_ssh_config "PasswordAuthentication" "no"
update_ssh_config "ChallengeResponseAuthentication" "no"
update_ssh_config "KbdInteractiveAuthentication" "no"
update_ssh_config "UsePAM" "no"
update_ssh_config "PubkeyAuthentication" "yes"
update_ssh_config "AcceptEnv" "LANG LC_*"
update_ssh_config "AllowUsers" "$NEW_USER"

# Проверка синтаксиса
if ! sshd -t -f "$SSHD_CONFIG" 2>/dev/null; then
    error_exit ${LINENO} "Ошибка синтаксиса в sshd_config"
fi

# Отключение ssh.socket (если активен)
if systemctl list-unit-files | grep -q ssh.socket 2>/dev/null; then
    systemctl disable --now ssh.socket 2>/dev/null || true
fi

# Перезапуск SSH
systemctl restart ssh || error_exit ${LINENO} "Не удалось перезапустить SSH"

# Настройка UFW (если активен)
if command -v ufw &>/dev/null; then
    if ufw status | grep -q "Status: active"; then
        ufw allow "$SSH_PORT"/tcp comment 'SSH custom port' 2>/dev/null || true
        ufw delete allow 22/tcp 2>/dev/null || true
        ufw reload 2>/dev/null || true
        log_info "UFW настроен"
    fi
fi

# Настройка локали (без интерактива)
if [[ -f /etc/default/locale ]]; then
    sed -i 's/^LANG=.*/LANG=ru_RU.UTF-8/' /etc/default/locale
    sed -i 's/^LC_ALL=.*/LC_ALL=ru_RU.UTF-8/' /etc/default/locale
else
    echo "LANG=ru_RU.UTF-8" > /etc/default/locale
    echo "LC_ALL=ru_RU.UTF-8" >> /etc/default/locale
fi

# Генерация русской локали
if ! locale -a 2>/dev/null | grep -q "ru_RU.utf8"; then
    locale-gen ru_RU.UTF-8 2>/dev/null || true
fi

log_info "Часть C завершена"

# ==============================================
# ФИНАЛИЗАЦИЯ - ОТПРАВКА CALLBACK ОБ УСПЕХЕ
# ==============================================
log_info "=== ОТПРАВКА CALLBACK УВЕДОМЛЕНИЯ ==="

# Отправляем успешный callback
send_callback "OK" ""

echo ""
log_info "==============================================="
log_info "✅ СКРИПТ УСПЕШНО ВЫПОЛНЕН!"
log_info "==============================================="
echo ""
log_info "📋 ИТОГОВАЯ ИНФОРМАЦИЯ:"
echo "  • Пользователь: $NEW_USER"
echo "  • SSH порт: $SSH_PORT"
echo "  • Docker: установлен"
echo "  • IP сервера: $SERVER_IP"
echo "  • Callback отправлен: ${CALLBACK_BASE_URL}?status=OK"
echo ""
log_warn "⚠️  ПРОВЕРЬТЕ ПОДКЛЮЧЕНИЕ В НОВОМ ТЕРМИНАЛЕ:"
echo "  ssh -p $SSH_PORT $NEW_USER@$SERVER_IP"
echo ""

exit 0