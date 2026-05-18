#!/bin/bash
# Неинтерактивное создание sudo-пользователя и безопасная настройка SSH.
# sudo wget https://raw.githubusercontent.com/SergeyMi37/vps_install/master/ubuntu/vps_ubuntu_new_user_ssh.sh && sudo chmod +x vps_ubuntu_new_user_ssh.sh && sudo ./vps_ubuntu_new_user_ssh.sh --user msw --key "ssh-ed25519 AAAAC3... user@host" --port 6553
# Пример:
#   sudo ./vps_ubuntu_new_user_ssh.sh --user msw --key "ssh-ed25519 AAAAC3... user@host" --port 2222

set -euo pipefail

NEW_USER="msw"
PUBLIC_KEY=""
SSH_PORT="2222"
ALLOW_EXISTING="yes"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

show_help() {
    cat << EOF
Использование: sudo $0 [ОПЦИИ]

Опции:
  --user USERNAME       Имя пользователя. По умолчанию: ${NEW_USER}
  --key PUBLIC_KEY      Публичный SSH-ключ пользователя
  --port PORT           Новый SSH-порт. По умолчанию: ${SSH_PORT}
  --no-allow-existing   Завершиться ошибкой, если пользователь уже существует
  --help                Показать эту справку

Пример:
  sudo $0 --user john --key "ssh-ed25519 AAAAC3... john@local" --port 2222

Важно:
  Скрипт не задает пароль пользователю и отключает SSH-вход по паролю.
  Если --key не указан, у пользователя уже должен быть непустой authorized_keys.
EOF
    exit 0
}

error_exit() {
    print_error "$1"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --user)
            NEW_USER="${2:-}"
            shift 2
            ;;
        --key)
            PUBLIC_KEY="${2:-}"
            shift 2
            ;;
        --port)
            SSH_PORT="${2:-}"
            shift 2
            ;;
        --no-allow-existing)
            ALLOW_EXISTING="no"
            shift
            ;;
        --help)
            show_help
            ;;
        *)
            error_exit "Неизвестный параметр: $1"
            ;;
    esac
done

[[ $EUID -eq 0 ]] || error_exit "Запустите скрипт от root: sudo $0 ..."
[[ -n "$NEW_USER" ]] || error_exit "Имя пользователя не может быть пустым"
[[ "$NEW_USER" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] || error_exit "Некорректное имя пользователя: $NEW_USER"
[[ "$SSH_PORT" =~ ^[0-9]+$ ]] || error_exit "SSH-порт должен быть числом"
(( SSH_PORT >= 1 && SSH_PORT <= 65535 )) || error_exit "SSH-порт вне диапазона 1-65535"

if [[ -n "$PUBLIC_KEY" ]] && [[ ! "$PUBLIC_KEY" =~ ^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp[0-9]+)[[:space:]] ]]; then
    error_exit "Некорректный публичный SSH-ключ"
fi

export DEBIAN_FRONTEND=noninteractive

add_user_shell_settings() {
    local username="$1"
    local bashrc="/home/${username}/.bashrc"
    local profile="/home/${username}/.profile"

    grep -q "# vps_ubuntu_new_user_ssh" "$bashrc" 2>/dev/null && return 0

    cat >> "$bashrc" << 'EOF'

# vps_ubuntu_new_user_ssh
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
export LANG=ru_RU.UTF-8
export LC_ALL=ru_RU.UTF-8
export LANGUAGE=ru_RU:ru

alias dockersrm='docker stop $(docker ps -a -q) && docker rm $(docker ps -a -q) -f && docker system prune -f'
alias dockersrmi='docker rmi $(docker images -q) -f && docker system prune -f'
alias dcserv='docker compose ps --services'
alias e="echo -e '\e[8;50;150;t'"
alias ee="echo -e '\e[8;55;160;t'"
alias eee="echo -e '\e[8;60;190;t'"
EOF

    grep -q "LANG=ru_RU.UTF-8" "$profile" 2>/dev/null || cat >> "$profile" << 'EOF'

# Настройки локали для корректного отображения кириллицы и псевдографики
export LANG=ru_RU.UTF-8
export LC_ALL=ru_RU.UTF-8
export LANGUAGE=ru_RU:ru
EOF

    chown "$username:$username" "$bashrc" "$profile"
}

add_ssh_key() {
    local username="$1"
    local key="$2"
    local user_home
    user_home=$(getent passwd "$username" | cut -d: -f6)
    local ssh_dir="${user_home}/.ssh"
    local auth_keys="${ssh_dir}/authorized_keys"

    install -d -m 700 -o "$username" -g "$username" "$ssh_dir"
    touch "$auth_keys"
    chown "$username:$username" "$auth_keys"
    chmod 600 "$auth_keys"

    if [[ -n "$key" ]] && ! grep -qF "$key" "$auth_keys"; then
        echo "$key" >> "$auth_keys"
    fi
}

update_ssh_config() {
    local param="$1"
    local value="$2"
    local file="$3"

    sed -i "/^[#[:space:]]*$param[[:space:]]/d" "$file"
    sed -i "/^[#[:space:]]*$param$/d" "$file"
    echo "$param $value" >> "$file"
}

restart_ssh_service() {
    if systemctl list-unit-files | grep -q '^ssh\.service'; then
        systemctl restart ssh
    elif systemctl list-unit-files | grep -q '^sshd\.service'; then
        systemctl restart sshd
    else
        service ssh restart
    fi
}

print_info "Обновление списка пакетов..."
apt update -qq

print_info "Проверка UTF-8 локали..."
if ! locale -a 2>/dev/null | grep -qi '^ru_RU\.utf8$'; then
    locale-gen ru_RU.UTF-8 2>/dev/null || true
fi

print_info "Создание/настройка пользователя ${NEW_USER}..."
if id "$NEW_USER" &>/dev/null; then
    [[ "$ALLOW_EXISTING" == "yes" ]] || error_exit "Пользователь ${NEW_USER} уже существует"
    print_warning "Пользователь ${NEW_USER} уже существует, используем его"
else
    adduser --gecos "" --disabled-password "$NEW_USER"
    print_success "Пользователь ${NEW_USER} создан"
fi

usermod -aG sudo "$NEW_USER"
if getent group docker >/dev/null; then
    usermod -aG docker "$NEW_USER"
fi
add_user_shell_settings "$NEW_USER"
add_ssh_key "$NEW_USER" "$PUBLIC_KEY"

USER_HOME=$(getent passwd "$NEW_USER" | cut -d: -f6)
AUTH_KEYS_FILE="${USER_HOME}/.ssh/authorized_keys"
[[ -s "$AUTH_KEYS_FILE" ]] || error_exit "SSH-ключ не указан и ${AUTH_KEYS_FILE} пуст. Передайте --key, иначе вход по SSH будет невозможен."
print_success "SSH-ключи пользователя готовы"

SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP_FILE="/etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)"
TEMP_CONFIG=$(mktemp)

print_info "Создание резервной копии ${SSHD_CONFIG} -> ${BACKUP_FILE}"
cp "$SSHD_CONFIG" "$BACKUP_FILE"
cp "$SSHD_CONFIG" "$TEMP_CONFIG"

print_info "Обновление конфигурации SSH..."
update_ssh_config "Port" "$SSH_PORT" "$TEMP_CONFIG"
update_ssh_config "PermitRootLogin" "no" "$TEMP_CONFIG"
update_ssh_config "PasswordAuthentication" "no" "$TEMP_CONFIG"
update_ssh_config "ChallengeResponseAuthentication" "no" "$TEMP_CONFIG"
update_ssh_config "KbdInteractiveAuthentication" "no" "$TEMP_CONFIG"
update_ssh_config "UsePAM" "no" "$TEMP_CONFIG"
update_ssh_config "PubkeyAuthentication" "yes" "$TEMP_CONFIG"
update_ssh_config "AcceptEnv" "LANG LC_*" "$TEMP_CONFIG"
update_ssh_config "AllowUsers" "$NEW_USER" "$TEMP_CONFIG"

print_info "Проверка синтаксиса sshd_config..."
if ! sshd -t -f "$TEMP_CONFIG"; then
    rm -f "$TEMP_CONFIG"
    error_exit "Ошибка синтаксиса SSH-конфигурации. Исходный файл не изменен."
fi

cp "$TEMP_CONFIG" "$SSHD_CONFIG"
rm -f "$TEMP_CONFIG"

if systemctl list-unit-files | grep -q '^ssh\.socket' && systemctl is-active ssh.socket &>/dev/null; then
    print_info "Отключение ssh.socket..."
    systemctl disable --now ssh.socket
fi

print_info "Перезапуск SSH..."
if ! restart_ssh_service; then
    print_error "SSH не перезапустился. Восстанавливаем резервную копию."
    cp "$BACKUP_FILE" "$SSHD_CONFIG"
    restart_ssh_service || true
    exit 1
fi

if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
    print_info "Настройка UFW..."
    ufw allow "$SSH_PORT"/tcp comment 'SSH custom port'
    if ufw status | grep -q "22/tcp"; then
        yes | ufw delete allow 22/tcp || true
    fi
    ufw reload
fi

print_info "Настройка системной локали..."
if [[ -f /etc/default/locale ]]; then
    sed -i 's/^LANG=.*/LANG=ru_RU.UTF-8/' /etc/default/locale
    sed -i 's/^LC_ALL=.*/LC_ALL=ru_RU.UTF-8/' /etc/default/locale
else
    echo "LANG=ru_RU.UTF-8" > /etc/default/locale
    echo "LC_ALL=ru_RU.UTF-8" >> /etc/default/locale
fi
grep -q "LANG=ru_RU.UTF-8" /etc/environment 2>/dev/null || echo "LANG=ru_RU.UTF-8" >> /etc/environment

SERVER_IP=$(ip -4 route get 1 | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1); exit}' 2>/dev/null || hostname -I | awk '{print $1}')
INFO_FILE="/root/ssh_setup_${NEW_USER}_$(date +%Y%m%d_%H%M%S).txt"

cat > "$INFO_FILE" << EOF
SSH НАСТРОЙКИ ОТ $(date)
==========================
Сервер: ${SERVER_IP}
Пользователь: ${NEW_USER}
Порт: ${SSH_PORT}
Команда подключения: ssh -p ${SSH_PORT} ${NEW_USER}@${SERVER_IP}
Резервная копия конфига: ${BACKUP_FILE}
Для восстановления:
  cp ${BACKUP_FILE} ${SSHD_CONFIG}
  systemctl restart ssh || systemctl restart sshd || service ssh restart
EOF

print_success "✅ Настройка завершена"
echo "  Пользователь: ${NEW_USER}"
echo "  SSH порт: ${SSH_PORT}"
echo "  Подключение: ssh -p ${SSH_PORT} ${NEW_USER}@${SERVER_IP}"
echo "  Информация: ${INFO_FILE}"
print_warning "Проверьте вход в новом терминале до закрытия текущей сессии."
