#!/bin/bash
set -e

# ==============================================
# ЕДИНЫЙ POST-INSTALL СКРИПТ ДЛЯ HOSTKEY VPS
# С сохранением лога в ~/post-install.log
# ==============================================

# --- 1. Параметры конфигурации (измените под себя) ---
NEW_USER="msw"
NEW_USER_PASSWORD="P@S5w0rd"
SSH_KEY="ssh-ed25519 AAAAC3... user@host"
SSH_PORT="2222"

# --- 2. Настройки логирования ---
LOG_FILE="/home/${NEW_USER}/post-install.log"
mkdir -p "/home/${NEW_USER}" 2>/dev/null || true

# Функция записи в лог и вывода в консоль
log_write() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_line="[${timestamp}] [${level}] ${message}"
    echo "$log_line" | tee -a "$LOG_FILE"
}

log_info() { log_write "INFO" "$1"; }
log_warn() { log_write "WARN" "$1"; }
log_error() { log_write "ERROR" "$1"; }

# --- 3. Настройки Callback ---
SERVER_IP=$(ip -4 route get 1 | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' 2>/dev/null || curl -s ifconfig.me 2>/dev/null || echo "unknown")
CALLBACK_BASE_URL="http://${SERVER_IP}:8080/hostkey/callback"

# --- 4. Функции для callback уведомлений ---
send_callback() {
    local status="$1"
    local error_info="$2"
    local url=""
    
    if [[ "$status" == "OK" ]]; then
        url="${CALLBACK_BASE_URL}?status=OK"
        log_info "Отправка callback: SUCCESS"
    else
        local encoded_error=$(echo "$error_info" | sed 's/ /%20/g; s/&/%26/g; s/?/%3F/g')
        url="${CALLBACK_BASE_URL}?status=Err&Code=${encoded_error}"
        log_error "Отправка callback: FAILED - ${error_info}"
    fi
    
    curl -s -X GET "$url" --max-time 5 --connect-timeout 2 >/dev/null 2>&1 &
    log_info "Callback отправлен на: $url"
}

# --- 5. Обработка ошибок ---
error_exit() {
    local line_number=$1
    local error_message=$2
    local error_code="LINE_${line_number}: ${error_message}"
    
    log_error "КРИТИЧЕСКАЯ ОШИБКА: ${error_code}"
    send_callback "Err" "$error_code"
    
    # Сохраняем финальный статус в лог
    echo "========================================" >> "$LOG_FILE"
    echo "СТАТУС: ОШИБКА (${error_code})" >> "$LOG_FILE"
    echo "ВРЕМЯ: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
    echo "========================================" >> "$LOG_FILE"
    
    exit 1
}

trap 'error_exit ${LINENO} "Неожиданная ошибка (код $?)"' ERR

# --- 6. Заголовок лога ---
cat > "$LOG_FILE" << EOF
========================================
POST-INSTALL SCRIPT EXECUTION LOG
========================================
Время запуска: $(date '+%Y-%m-%d %H:%M:%S')
Хост: $(hostname)
IP адрес: ${SERVER_IP}
Пользователь: ${NEW_USER}
SSH порт: ${SSH_PORT}
========================================

EOF

log_info "=== НАЧАЛО ВЫПОЛНЕНИЯ POST-INSTALL СКРИПТА ==="
log_info "Лог-файл создан: ${LOG_FILE}"

# ==============================================
# ЧАСТЬ A: Создание пользователя
# ==============================================
log_info "=== ЧАСТЬ A: Создание пользователя ${NEW_USER} ==="

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
    error_exit ${LINENO} "Скрипт должен запускаться с правами root"
fi
log_info "Права root проверены"

# Создание пользователя
if id "$NEW_USER" &>/dev/null; then
    log_warn "Пользователь ${NEW_USER} уже существует, пропускаем создание"
else
    log_info "Создание пользователя ${NEW_USER}..."
    useradd -m -s /bin/bash "$NEW_USER" || error_exit ${LINENO} "Не удалось создать пользователя"
    echo "$NEW_USER:$NEW_USER_PASSWORD" | chpasswd || error_exit ${LINENO} "Не удалось установить пароль"
    usermod -aG sudo "$NEW_USER" || error_exit ${LINENO} "Не удалось добавить в группу sudo"
    log_info "Пользователь ${NEW_USER} успешно создан"
fi

# Добавление bash-алиасов
log_info "Добавление bash-алиасов в .bashrc..."
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
log_info "Bash-алиасы добавлены"

# Добавление SSH-ключа
if [[ -n "$SSH_KEY" ]]; then
    log_info "Добавление SSH-ключа для пользователя ${NEW_USER}..."
    mkdir -p "/home/$NEW_USER/.ssh"
    echo "$SSH_KEY" >> "/home/$NEW_USER/.ssh/authorized_keys"
    chmod 700 "/home/$NEW_USER/.ssh"
    chmod 600 "/home/$NEW_USER/.ssh/authorized_keys"
    chown -R "$NEW_USER:$NEW_USER" "/home/$NEW_USER/.ssh"
    log_info "SSH-ключ успешно добавлен"
else
    log_warn "SSH-ключ не указан, пропускаем"
fi

log_info "Часть A завершена успешно"

# ==============================================
# ЧАСТЬ B: Установка Docker и утилит
# ==============================================
log_info "=== ЧАСТЬ B: Обновление системы и установка Docker ==="

# Неинтерактивный режим
export DEBIAN_FRONTEND=noninteractive

log_info "Обновление списков пакетов..."
apt update -qq || error_exit ${LINENO} "Не удалось обновить списки пакетов"
log_info "Обновление пакетов..."
apt upgrade -y -qq || error_exit ${LINENO} "Не удалось обновить пакеты"

log_info "Установка вспомогательных утилит..."
apt install -y -qq ca-certificates curl gnupg lsb-release git net-tools make mc || error_exit ${LINENO} "Не удалось установить утилиты"

log_info "Установка Docker..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg || error_exit ${LINENO} "Ошибка при добавлении GPG ключа Docker"
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update -qq || error_exit ${LINENO} "Ошибка при обновлении после добавления Docker репозитория"
apt install -y -qq docker-ce docker-ce-cli containerd.io || error_exit ${LINENO} "Не удалось установить Docker"

log_info "Добавление пользователя ${NEW_USER} в группу docker..."
usermod -aG docker "$NEW_USER" || error_exit ${LINENO} "Не удалось добавить пользователя в группу docker"

log_info "Установка Docker Compose..."
DOCKER_COMPOSE_VERSION="$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d '"' -f 4)"
if [[ -n "$DOCKER_COMPOSE_VERSION" ]]; then
    curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose || error_exit ${LINENO} "Не удалось скачать Docker Compose"
    chmod +x /usr/local/bin/docker-compose
    log_info "Docker Compose ${DOCKER_COMPOSE_VERSION} установлен"
else
    log_warn "Не удалось определить версию Docker Compose, пропускаем"
fi

# Проверка установки Docker
if docker --version &>/dev/null; then
    log_info "Docker версия: $(docker --version 2>&1)"
else
    log_warn "Docker установлен, но команда не выполняется"
fi

log_info "Часть B завершена успешно"

# ==============================================
# ЧАСТЬ C: Безопасная настройка SSH
# ==============================================
log_info "=== ЧАСТЬ C: Настройка безопасности SSH ==="

SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP_FILE="/etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)"

# Резервная копия
log_info "Создание резервной копии ${SSHD_CONFIG} -> ${BACKUP_FILE}"
cp "$SSHD_CONFIG" "$BACKUP_FILE" || error_exit ${LINENO} "Не удалось создать резервную копию sshd_config"

# Функция обновления параметров SSH
update_ssh_config() {
    local param="$1"
    local value="$2"
    sed -i "/^[#[:space:]]*$param/d" "$SSHD_CONFIG"
    echo "$param $value" >> "$SSHD_CONFIG"
    log_info "Параметр SSH обновлен: ${param} = ${value}"
}

# Применение безопасных настроек
log_info "Применение безопасных настроек SSH..."
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
log_info "Проверка синтаксиса sshd_config..."
if ! sshd -t -f "$SSHD_CONFIG" 2>/dev/null; then
    log_error "Ошибка синтаксиса в sshd_config"
    sshd -t -f "$SSHD_CONFIG" 2>&1 | tee -a "$LOG_FILE"
    error_exit ${LINENO} "Ошибка синтаксиса в sshd_config"
fi
log_info "Синтаксис sshd_config корректен"

# Отключение ssh.socket
if systemctl list-unit-files | grep -q ssh.socket 2>/dev/null; then
    if systemctl is-active ssh.socket &>/dev/null; then
        log_info "Отключение ssh.socket..."
        systemctl disable --now ssh.socket 2>/dev/null || true
        log_info "ssh.socket отключен"
    fi
fi

# Перезапуск SSH
log_info "Перезапуск SSH сервиса..."
systemctl restart ssh || error_exit ${LINENO} "Не удалось перезапустить SSH"
log_info "SSH сервис успешно перезапущен"

# Настройка UFW
if command -v ufw &>/dev/null; then
    if ufw status | grep -q "Status: active"; then
        log_info "Настройка UFW..."
        ufw allow "$SSH_PORT"/tcp comment 'SSH custom port' 2>/dev/null || true
        ufw delete allow 22/tcp 2>/dev/null || true
        ufw reload 2>/dev/null || true
        log_info "UFW настроен: порт ${SSH_PORT} открыт"
    else
        log_info "UFW не активен, пропускаем настройку"
    fi
fi

# Настройка локали
log_info "Настройка системной локали..."
if [[ -f /etc/default/locale ]]; then
    sed -i 's/^LANG=.*/LANG=ru_RU.UTF-8/' /etc/default/locale
    sed -i 's/^LC_ALL=.*/LC_ALL=ru_RU.UTF-8/' /etc/default/locale
else
    echo "LANG=ru_RU.UTF-8" > /etc/default/locale
    echo "LC_ALL=ru_RU.UTF-8" >> /etc/default/locale
fi

# Генерация русской локали
if ! locale -a 2>/dev/null | grep -q "ru_RU.utf8"; then
    log_info "Генерация русской локали..."
    locale-gen ru_RU.UTF-8 2>/dev/null || true
fi
log_info "Локаль настроена: ru_RU.UTF-8"

log_info "Часть C завершена успешно"

# ==============================================
# ФИНАЛИЗАЦИЯ
# ==============================================
log_info "=== ФИНАЛИЗАЦИЯ ==="

# Установка правильных прав на лог-файл
chown "${NEW_USER}:${NEW_USER}" "$LOG_FILE" 2>/dev/null || true
log_info "Права на лог-файл установлены"

# Сохраняем финальный статус в лог
echo "" >> "$LOG_FILE"
echo "========================================" >> "$LOG_FILE"
echo "СТАТУС: УСПЕХ" >> "$LOG_FILE"
echo "ВРЕМЯ ЗАВЕРШЕНИЯ: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
echo "========================================" >> "$LOG_FILE"

# Отправляем успешный callback
send_callback "OK" ""

# Финальный вывод
echo ""
log_info "==============================================="
log_info "✅ СКРИПТ УСПЕШНО ВЫПОЛНЕН!"
log_info "==============================================="
echo ""
log_info "📋 ИТОГОВАЯ ИНФОРМАЦИЯ:"
echo "  • Пользователь: $NEW_USER"
echo "  • SSH порт: $SSH_PORT"
echo "  • Docker: $(docker --version 2>&1 | head -1)"
echo "  • Docker Compose: $(docker-compose --version 2>&1 | head -1)"
echo "  • IP сервера: $SERVER_IP"
echo "  • Лог-файл: $LOG_FILE"
echo "  • Callback отправлен: ${CALLBACK_BASE_URL}?status=OK"
echo ""
log_warn "⚠️  ПРОВЕРЬТЕ ПОДКЛЮЧЕНИЕ В НОВОМ ТЕРМИНАЛЕ:"
echo "  ssh -p $SSH_PORT $NEW_USER@$SERVER_IP"
echo ""
log_info "Для просмотра лога выполните: cat $LOG_FILE"
echo ""

exit 0