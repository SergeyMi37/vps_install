#!/bin/bash
# sudo wget https://raw.githubusercontent.com/SergeyMi37/vps_install/master/ubuntu/sir_tunnel.sh && sudo chmod +x sir_tunnel.sh && sudo ./sir_tunnel.sh

# sir_tunnel.sh - Неинтерактивная установка SirTunnel на сервере
# Запускать от root или через sudo

set -euo pipefail

# Цвета для вывода (опционально, для читаемости)
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Функции логирования
log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Проверка запуска от root
if [[ $EUID -ne 0 ]]; then
   log_error "Этот скрипт должен запускаться от root (для установки Caddy и прав на порт 443)"
fi

# 1. Обновление системы и установка зависимостей
log_info "Обновление списка пакетов и установка curl, python3, openssh-server..."
apt-get update -qq
apt-get install -y -qq curl python3 openssh-server > /dev/null

# 2. Установка Caddy (официальный скрипт)
log_info "Установка Caddy..."
curl -fsSL https://getcaddy.com | bash -s personal > /dev/null 2>&1 || log_error "Не удалось установить Caddy"

# 3. Настройка Caddy для работы с SirTunnel
log_info "Настройка Caddy..."
mkdir -p /etc/caddy
cat > /etc/caddy/Caddyfile <<EOF
{
    admin localhost:2019
}

# Динамическая настройка будет производиться через API Caddy
# (SirTunnel сам добавляет и удаляет reverse proxy через API)
EOF

# 4. Загрузка sirtunnel.py из репозитория
log_info "Загрузка sirtunnel.py..."
curl -fsSL -o /usr/local/bin/sirtunnel.py https://raw.githubusercontent.com/matiboy/SirTunnel/master/sirtunnel.py || log_error "Не удалось скачать sirtunnel.py"
chmod +x /usr/local/bin/sirtunnel.py

# 5. Настройка прав для порта 443 (CAP_NET_BIND_SERVICE)
log_info "Настройка прав для Caddy на привязку к порту 443..."
setcap 'cap_net_bind_service=+ep' $(which caddy) || log_error "Не удалось установить CAP_NET_BIND_SERVICE для caddy"

# 6. Создание systemd сервиса для Caddy
log_info "Создание systemd-сервиса для Caddy..."
cat > /etc/systemd/system/caddy.service <<EOF
[Unit]
Description=Caddy web server
After=network.target

[Service]
User=root
Group=root
ExecStart=$(which caddy) run --config /etc/caddy/Caddyfile
ExecReload=/bin/kill -USR1 \$MAINPID
LimitNOFILE=1048576
LimitNPROC=512
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

# 7. Включение и запуск Caddy
log_info "Запуск Caddy..."
systemctl daemon-reload
systemctl enable caddy > /dev/null 2>&1
systemctl restart caddy || log_error "Не удалось запустить Caddy"

# 8. Убедиться, что SSH сервер запущен и разрешены удаленные туннели
log_info "Проверка SSH сервера..."
systemctl enable ssh > /dev/null 2>&1 || true
systemctl restart ssh || log_error "Не удалось запустить SSH сервер"

# Включаем GatewayPorts для публичного доступа к туннелю (опционально, но часто нужно)
if ! grep -q "^GatewayPorts yes" /etc/ssh/sshd_config; then
    echo "GatewayPorts yes" >> /etc/ssh/sshd_config
    systemctl restart ssh
    log_info "Включено GatewayPorts в SSH (позволяет открывать туннель на 0.0.0.0)"
fi

# 9. Финальная проверка
log_info "Проверка работоспособности..."
if systemctl is-active --quiet caddy; then
    log_info "Caddy успешно запущен"
else
    log_error "Caddy не запущен"
fi

if pgrep -f "sshd" > /dev/null; then
    log_info "SSH сервер работает"
else
    log_error "SSH сервер не работает"
fi

if command -v sirtunnel.py > /dev/null; then
    log_info "sirtunnel.py установлен в PATH"
else
    log_error "sirtunnel.py не найден в PATH"
fi

log_info "Установка SirTunnel завершена успешно!"
log_info "Для создания туннеля используйте команду:"
log_info "  ssh -tR 9001:localhost:8080 user@example.com sirtunnel.py subdomain.example.com 9001"