#!/bin/bash

# ============================================
# CLI-установщик Pangolin Server
# Версия: 1.1
# ============================================

set -euo pipefail

# === ЗНАЧЕНИЯ ПО УМОЛЧАНИЮ, ПЕРЕОПРЕДЕЛЯЮТСЯ ЧЕРЕЗ CLI ===
PUBLIC_IP=$(ip -4 route get 1 | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
SUBDOMAIN=""
ADMIN_EMAIL=""
PANGO_VERSION="latest"
INSTALL_DIR="/opt/pangolin"
LOG_FILE="/root/pangolin_install.log"
CLIENT_INSTRUCTIONS_FILE="/root/pangolin_client_instructions.txt"
CREDENTIALS_FILE="/root/pangolin_credentials.txt"
INSTALLATION_INFO_FILE="/root/pangolin_installation_info.txt"
HEALTH_CHECK_FILE="/usr/local/bin/pangolin-health-check"
HEALTH_LOG_FILE="/var/log/pangolin-health.log"

GERBIL_PORT="51820"
GERBIL_PEERS_PORT="51821"
TRAEFIK_PORT="80"
TRAEFIK_SECURE_PORT="443"
TRAEFIK_DASHBOARD_PORT="8080"
NEWT_PORT="8443"
API_PORT="9000"
API_SECURE_PORT="9001"
DOCKER_NETWORK="pangolin_network"

usage() {
    printf '%s\n' \
        "Usage: sudo $0 --subdomain DOMAIN --admin-email EMAIL [OPTIONS]" \
        "" \
        "Required:" \
        "  -d, --subdomain DOMAIN              Домен Pangolin, например pangolin.example.com" \
        "  -e, --admin-email EMAIL             Email администратора и Let's Encrypt" \
        "" \
        "Optional:" \
        "  -i, --public-ip IP                  Публичный IP (по умолчанию: автоопределение)" \
        "  -v, --pango-version VERSION         Версия Pangolin для инструкций (по умолчанию: latest)" \
        "      --install-dir PATH              Директория установки (по умолчанию: /opt/pangolin)" \
        "      --log-file PATH                 Лог установки (по умолчанию: /root/pangolin_install.log)" \
        "      --client-instructions-file PATH Инструкции клиентам" \
        "      --credentials-file PATH         Файл с учетными данными администратора" \
        "      --installation-info-file PATH   Файл с информацией об установке" \
        "      --health-check-file PATH        Путь скрипта health-check" \
        "      --health-log-file PATH          Лог health-check" \
        "      --gerbil-port PORT              WireGuard порт (по умолчанию: 51820)" \
        "      --gerbil-peers-port PORT        WireGuard peers порт (по умолчанию: 51821)" \
        "      --traefik-port PORT             HTTP порт (по умолчанию: 80)" \
        "      --traefik-secure-port PORT      HTTPS порт (по умолчанию: 443)" \
        "      --traefik-dashboard-port PORT   Traefik dashboard порт (по умолчанию: 8080)" \
        "      --newt-port PORT                Newt порт (по умолчанию: 8443)" \
        "      --api-port PORT                 API порт (по умолчанию: 9000)" \
        "      --api-secure-port PORT          Secure API порт (по умолчанию: 9001)" \
        "      --docker-network NAME           Docker сеть (по умолчанию: pangolin_network)" \
        "  -h, --help                          Показать справку" \
        "" \
        "Example:" \
        "  sudo $0 -d pangolin.example.com -e admin@example.com --public-ip 203.0.113.10"
}

require_value() {
    if [ -z "${2:-}" ]; then
        echo "ОШИБКА: параметр $1 требует значение" >&2
        exit 1
    fi
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -d|--subdomain) require_value "$1" "${2:-}"; SUBDOMAIN="$2"; shift 2 ;;
            -e|--admin-email) require_value "$1" "${2:-}"; ADMIN_EMAIL="$2"; shift 2 ;;
            -i|--public-ip) require_value "$1" "${2:-}"; PUBLIC_IP="$2"; shift 2 ;;
            -v|--pango-version) require_value "$1" "${2:-}"; PANGO_VERSION="$2"; shift 2 ;;
            --install-dir) require_value "$1" "${2:-}"; INSTALL_DIR="$2"; shift 2 ;;
            --log-file) require_value "$1" "${2:-}"; LOG_FILE="$2"; shift 2 ;;
            --client-instructions-file) require_value "$1" "${2:-}"; CLIENT_INSTRUCTIONS_FILE="$2"; shift 2 ;;
            --credentials-file) require_value "$1" "${2:-}"; CREDENTIALS_FILE="$2"; shift 2 ;;
            --installation-info-file) require_value "$1" "${2:-}"; INSTALLATION_INFO_FILE="$2"; shift 2 ;;
            --health-check-file) require_value "$1" "${2:-}"; HEALTH_CHECK_FILE="$2"; shift 2 ;;
            --health-log-file) require_value "$1" "${2:-}"; HEALTH_LOG_FILE="$2"; shift 2 ;;
            --gerbil-port) require_value "$1" "${2:-}"; GERBIL_PORT="$2"; shift 2 ;;
            --gerbil-peers-port) require_value "$1" "${2:-}"; GERBIL_PEERS_PORT="$2"; shift 2 ;;
            --traefik-port) require_value "$1" "${2:-}"; TRAEFIK_PORT="$2"; shift 2 ;;
            --traefik-secure-port) require_value "$1" "${2:-}"; TRAEFIK_SECURE_PORT="$2"; shift 2 ;;
            --traefik-dashboard-port) require_value "$1" "${2:-}"; TRAEFIK_DASHBOARD_PORT="$2"; shift 2 ;;
            --newt-port) require_value "$1" "${2:-}"; NEWT_PORT="$2"; shift 2 ;;
            --api-port) require_value "$1" "${2:-}"; API_PORT="$2"; shift 2 ;;
            --api-secure-port) require_value "$1" "${2:-}"; API_SECURE_PORT="$2"; shift 2 ;;
            --docker-network) require_value "$1" "${2:-}"; DOCKER_NETWORK="$2"; shift 2 ;;
            -h|--help) usage; exit 0 ;;
            *) echo "ОШИБКА: неизвестный параметр: $1" >&2; usage; exit 1 ;;
        esac
    done
}

validate_config() {
    if [ -z "$SUBDOMAIN" ] || [ -z "$ADMIN_EMAIL" ]; then
        echo "ОШИБКА: обязательны --subdomain и --admin-email" >&2
        usage
        exit 1
    fi
}

start_logging() {
    exec > >(tee -a "$LOG_FILE") 2>&1

    echo "========================================"
    echo "Установка Pangolin Server начата: $(date)"
    echo "========================================"
    echo "Публичный IP: $PUBLIC_IP"
    echo "Субдомен: $SUBDOMAIN"
    echo "Email: $ADMIN_EMAIL"
    echo "Директория установки: $INSTALL_DIR"
    echo "========================================"
}

# ============================================
# ФУНКЦИЯ ЛОГИРОВАНИЯ
# ============================================
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# ============================================
# ФУНКЦИЯ ПРОВЕРКИ ОШИБОК
# ============================================
check_error() {
    if [ $? -ne 0 ]; then
        log "ОШИБКА: $1"
        echo "КРИТИЧЕСКАЯ ОШИБКА: $1" >> "$LOG_FILE"
        exit 1
    fi
}

# ============================================
# ОПРЕДЕЛЕНИЕ ОС
# ============================================
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION_ID=$VERSION_ID
    else
        log "Не удалось определить ОС"
        exit 1
    fi
    log "Определена ОС: $OS $VERSION_ID"
}

# ============================================
# УСТАНОВКА ЗАВИСИМОСТЕЙ
# ============================================
install_dependencies() {
    log "Установка зависимостей..."
    
    case $OS in
        ubuntu|debian)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -y
            apt-get install -y curl wget git ufw certbot python3-certbot-nginx nginx
            ;;
        almalinux|rocky|centos|rhel|fedora)
            if command -v dnf &> /dev/null; then
                dnf install -y epel-release
                dnf install -y curl wget git firewalld certbot python3-certbot-nginx nginx
                systemctl enable --now firewalld
            else
                yum install -y epel-release
                yum install -y curl wget git firewalld certbot python3-certbot-nginx nginx
                systemctl enable --now firewalld
            fi
            ;;
        *)
            log "Неподдерживаемая ОС: $OS"
            exit 1
            ;;
    esac
    check_error "Не удалось установить зависимости"
    log "Зависимости установлены успешно"
}

# ============================================
# НАСТРОЙКА БРАНДМАУЭРА
# ============================================
configure_firewall() {
    log "Настройка брандмауэра..."
    
    # Порты для Pangolin
    PORTS=(
        "$TRAEFIK_PORT"
        "$TRAEFIK_SECURE_PORT"
        "$GERBIL_PORT"
        "$GERBIL_PEERS_PORT"
        "$NEWT_PORT"
        "$TRAEFIK_DASHBOARD_PORT"
        "$API_PORT"
        "$API_SECURE_PORT"
    )
    
    case $OS in
        ubuntu|debian)
            ufw --force enable
            for port in "${PORTS[@]}"; do
                ufw allow $port/tcp
                ufw allow $port/udp
            done
            ufw reload
            ;;
        almalinux|rocky|centos|rhel|fedora)
            for port in "${PORTS[@]}"; do
                firewall-cmd --permanent --add-port=$port/tcp
                firewall-cmd --permanent --add-port=$port/udp
            done
            firewall-cmd --reload
            ;;
    esac
    check_error "Не удалось настроить брандмауэр"
    log "Брандмауэр настроен: порты ${PORTS[*]} открыты"
}

# ============================================
# УСТАНОВКА DOCKER И DOCKER COMPOSE
# ============================================
install_docker() {
    log "Установка Docker и Docker Compose..."
    
    # Установка Docker
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sh /tmp/get-docker.sh
    check_error "Не удалось установить Docker"
    
    # Установка Docker Compose
    LATEST_COMPOSE=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | cut -d'"' -f4)
    curl -L "https://github.com/docker/compose/releases/download/${LATEST_COMPOSE}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    # Запуск Docker
    systemctl enable --now docker
    check_error "Не удалось запустить Docker"
    
    log "Docker и Docker Compose установлены: $(docker --version), $(docker-compose --version)"
}

# ============================================
# УСТАНОВКА PANGO
# ============================================
install_pangolin() {
    log "Установка Pangolin..."
    
    # Создание директории
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    
    # Клонирование репозитория
    git clone https://github.com/fosrl/pangolin.git .
    check_error "Не удалось клонировать репозиторий Pangolin"
    
    # Создание .env файла
    cat > .env << EOF
# Pangolin конфигурация
PANGO_PUBLIC_IP=${PUBLIC_IP}
PANGO_DOMAIN=${SUBDOMAIN}
PANGO_EMAIL=${ADMIN_EMAIL}
PANGO_ADMIN_EMAIL=${ADMIN_EMAIL}
PANGO_ADMIN_PASSWORD=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-24)

# База данных
POSTGRES_PASSWORD=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-24)
DATABASE_URL=postgresql://pangolin:${POSTGRES_PASSWORD}@postgres:5432/pangolin

# Redis
REDIS_PASSWORD=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-24)

# Gerbil (WireGuard)
GERBIL_PORT=${GERBIL_PORT}
GERBIL_PEERS_PORT=${GERBIL_PEERS_PORT}

# Traefik
TRAEFIK_PORT=${TRAEFIK_PORT}
TRAEFIK_SECURE_PORT=${TRAEFIK_SECURE_PORT}
TRAEFIK_DASHBOARD_PORT=${TRAEFIK_DASHBOARD_PORT}

# Newt (прокси)
NEWT_PORT=${NEWT_PORT}

# API порт
API_PORT=${API_PORT}
API_SECURE_PORT=${API_SECURE_PORT}

# Docker сеть
DOCKER_NETWORK=${DOCKER_NETWORK}
EOF
    
    # Запуск через Docker Compose
    docker-compose up -d
    check_error "Не удалось запустить Pangolin"
    
    log "Pangolin запущен успешно"
    
    # Сохранение пароля администратора
    ADMIN_PASSWORD=$(grep PANGO_ADMIN_PASSWORD .env | cut -d'=' -f2)
    echo "ПАРОЛЬ АДМИНИСТРАТОРА PANGO: $ADMIN_PASSWORD" > "$CREDENTIALS_FILE"
    chmod 600 "$CREDENTIALS_FILE"
     
    log "Учетные данные сохранены в $CREDENTIALS_FILE"
}

# ============================================
# НАСТРОЙКА NGINX И HTTPS
# ============================================
configure_https() {
    log "Настройка HTTPS для $SUBDOMAIN..."
    
    # Проверка DNS записи
    RESOLVED_IP=$(dig +short "$SUBDOMAIN" | tail -1)
    if [ "$RESOLVED_IP" != "$PUBLIC_IP" ]; then
        log "ВНИМАНИЕ: DNS запись $SUBDOMAIN указывает на $RESOLVED_IP, ожидается $PUBLIC_IP"
        log "Сертификат может не быть выпущен. Проверьте DNS настройки."
        echo "ВНИМАНИЕ: DNS запись $SUBDOMAIN указывает на $RESOLVED_IP, ожидается $PUBLIC_IP" >> "$LOG_FILE"
        return 1
    fi
    
    # Остановка Traefik для выпуска сертификата
    docker-compose stop traefik 2>/dev/null || true
    
    # Временная Nginx конфигурация для ACME
    cat > /etc/nginx/sites-available/pangolin << EOF
server {
    listen ${TRAEFIK_PORT};
    server_name ${SUBDOMAIN};
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    
    location / {
        return 301 https://\$host\$request_uri;
    }
}
EOF
    
    ln -sf /etc/nginx/sites-available/pangolin /etc/nginx/sites-enabled/
    systemctl restart nginx
    
    # Выпуск сертификата
    certbot certonly --webroot -w /var/www/html \
        --non-interactive \
        --agree-tos \
        --email "$ADMIN_EMAIL" \
        -d "$SUBDOMAIN"
    
    if [ $? -eq 0 ]; then
        log "SSL сертификат выпущен успешно"
        
        # Копирование сертификатов для Pangolin
        mkdir -p "$INSTALL_DIR/certs"
        cp /etc/letsencrypt/live/$SUBDOMAIN/fullchain.pem "$INSTALL_DIR/certs/"
        cp /etc/letsencrypt/live/$SUBDOMAIN/privkey.pem "$INSTALL_DIR/certs/"
        chmod 600 "$INSTALL_DIR/certs/privkey.pem"
        
        # Обновление .env для HTTPS
        cat >> "$INSTALL_DIR/.env" << EOF

# SSL сертификаты
SSL_CERT_PATH=/certs/fullchain.pem
SSL_KEY_PATH=/certs/privkey.pem
EOF
        
        log "Сертификаты скопированы в $INSTALL_DIR/certs/"
    else
        log "ВНИМАНИЕ: Не удалось выпустить SSL сертификат. Проверьте DNS настройки."
        echo "ВНИМАНИЕ: Не удалось выпустить SSL сертификат" >> "$LOG_FILE"
    fi
    
    # Удаление временной конфигурации
    rm -f /etc/nginx/sites-enabled/pangolin
    
    # Перезапуск Pangolin
    docker-compose up -d
}

# ============================================
# НАСТРОЙКА АВТООБНОВЛЕНИЯ
# ============================================
configure_auto_update() {
    log "Настройка автоматического обновления..."
    
    cat > /etc/cron.d/pangolin-update << EOF
# Ежедневное обновление Pangolin в 3:00
0 3 * * * root cd $INSTALL_DIR && docker-compose pull && docker-compose up -d >> $LOG_FILE 2>&1

# Обновление сертификатов Let's Encrypt
0 2 * * * root certbot renew --quiet --post-hook "cp /etc/letsencrypt/live/$SUBDOMAIN/fullchain.pem $INSTALL_DIR/certs/ && cp /etc/letsencrypt/live/$SUBDOMAIN/privkey.pem $INSTALL_DIR/certs/ && cd $INSTALL_DIR && docker-compose restart" >> $LOG_FILE 2>&1
EOF
    
    chmod 644 /etc/cron.d/pangolin-update
    log "Автоматическое обновление настроено"
}

# ============================================
# СОЗДАНИЕ ИНСТРУКЦИЙ ДЛЯ КЛИЕНТОВ
# ============================================
create_client_instructions() {
    log "Создание инструкций для клиентов..."
    
    cat > "$CLIENT_INSTRUCTIONS_FILE" << EOF
========================================================
ИНСТРУКЦИИ ПО УСТАНОВКЕ КЛИЕНТА PANGO
========================================================

Сервер: ${SUBDOMAIN}
Публичный IP: ${PUBLIC_IP}
Версия: ${PANGO_VERSION}

========================================================
1. WINDOWS
========================================================

Шаг 1: Скачайте клиент Pangolin
Откройте PowerShell от имени администратора и выполните:

Invoke-WebRequest -Uri "https://github.com/fosrl/pangolin/releases/latest/download/pangolin-windows-amd64.exe" -OutFile "\$env:USERPROFILE\Downloads\pangolin.exe"

Шаг 2: Установка и настройка
1. Запустите скачанный файл pangolin.exe
2. В окне настроек введите:
   - Server Address: ${SUBDOMAIN}
   - Server Port: ${TRAEFIK_SECURE_PORT}
   - API Port: ${API_SECURE_PORT}
3. Нажмите "Connect" и следуйте инструкциям
4. При запросе учетных данных используйте данные администратора

Шаг 3: Добавление в автозагрузку
- Нажмите Win+R, введите shell:startup
- Создайте ярлык для pangolin.exe
- Или в настройках программы включите "Run at startup"

========================================================
2. UBUNTU / DEBIAN
========================================================

Шаг 1: Установка через скрипт
curl -fsSL https://raw.githubusercontent.com/fosrl/pangolin/main/scripts/install-client.sh | bash

Шаг 2: Ручная установка
# Скачивание клиента
wget https://github.com/fosrl/pangolin/releases/latest/download/pangolin-linux-amd64 -O /usr/local/bin/pangolin
chmod +x /usr/local/bin/pangolin

# Настройка
sudo pangolin config set --server ${SUBDOMAIN} --port ${TRAEFIK_SECURE_PORT} --api-port ${API_SECURE_PORT}

# Автозапуск как сервис
sudo tee /etc/systemd/system/pangolin-client.service > /dev/null << 'CLIENT_SERVICE_EOF'
[Unit]
Description=Pangolin Client Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/pangolin client
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
CLIENT_SERVICE_EOF

sudo systemctl daemon-reload
sudo systemctl enable --now pangolin-client

Шаг 3: Проверка статуса
sudo systemctl status pangolin-client

========================================================
3. ALMALINUX / RHEL / CENTOS
========================================================

Шаг 1: Скачивание и установка
wget https://github.com/fosrl/pangolin/releases/latest/download/pangolin-linux-amd64 -O /usr/local/bin/pangolin
chmod +x /usr/local/bin/pangolin

# Если используете SELinux
chcon -t bin_t /usr/local/bin/pangolin

# Настройка брандмауэра (если нужно)
sudo firewall-cmd --permanent --add-port=${GERBIL_PORT}/udp
sudo firewall-cmd --reload

Шаг 2: Настройка клиента
pangolin config set --server ${SUBDOMAIN} --port ${TRAEFIK_SECURE_PORT} --api-port ${API_SECURE_PORT}

Шаг 3: Создание systemd сервиса
cat > /etc/systemd/system/pangolin-client.service << 'CLIENT_SERVICE_EOF'
[Unit]
Description=Pangolin Client Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/pangolin client
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
CLIENT_SERVICE_EOF

systemctl daemon-reload
systemctl enable --now pangolin-client

Шаг 4: Настройка SELinux (если включен)
semanage fcontext -a -t bin_t /usr/local/bin/pangolin
restorecon -v /usr/local/bin/pangolin

========================================================
4. ПРОВЕРКА ПОДКЛЮЧЕНИЯ
========================================================

После установки клиента:

1. Откройте веб-браузер и перейдите по адресу:
   https://${SUBDOMAIN}

2. Войдите с учетными данными администратора

3. В панели управления проверьте статус подключения:
   - Зеленый индикатор = подключено
   - Красный индикатор = проблемы с подключением

4. Для тестирования тоннеля выполните на клиенте:
   pangolin test-connection

========================================================
5. РЕШЕНИЕ ПРОБЛЕМ
========================================================

Проблема: Не удается подключиться к серверу
Решение:
- Проверьте, что порты ${TRAEFIK_SECURE_PORT} и ${API_SECURE_PORT} открыты на клиенте
- Проверьте DNS разрешение: nslookup ${SUBDOMAIN}
- Проверьте доступность сервера: telnet ${SUBDOMAIN} ${TRAEFIK_SECURE_PORT}

Проблема: Сертификат недействителен
Решение:
- Убедитесь, что системное время синхронизировано
- Linux: sudo ntpdate pool.ntp.org
- Windows: w32tm /resync

Проблема: Брандмауэр блокирует подключение
Решение:
- Linux: sudo ufw allow ${TRAEFIK_SECURE_PORT}/tcp && sudo ufw allow ${API_SECURE_PORT}/tcp
- Windows: Добавьте pangolin.exe в исключения брандмауэра

========================================================
ДАННЫЕ ДЛЯ ПОДКЛЮЧЕНИЯ:
========================================================
Сервер: ${SUBDOMAIN}
Порт: ${TRAEFIK_SECURE_PORT}
API порт: ${API_SECURE_PORT}
Админ-панель: https://${SUBDOMAIN}
Логин: admin
Пароль: (указан в ${CREDENTIALS_FILE} на сервере)

========================================================
Установка завершена: $(date)
========================================================
EOF
    
    chmod 644 "$CLIENT_INSTRUCTIONS_FILE"
    log "Инструкции сохранены в $CLIENT_INSTRUCTIONS_FILE"
}

# ============================================
# СОЗДАНИЕ СКРИПТА ПРОВЕРКИ
# ============================================
create_health_check() {
    log "Создание скрипта проверки здоровья..."
    
    cat > "$HEALTH_CHECK_FILE" << EOF
#!/bin/bash
# Скрипт проверки состояния Pangolin

DOCKER_COMPOSE_DIR="${INSTALL_DIR}"
LOG_FILE="${HEALTH_LOG_FILE}"

check_service() {
    echo "=== Проверка Pangolin: \$(date) ===" | tee -a "\$LOG_FILE"
     
    # Проверка Docker контейнеров
    cd "\$DOCKER_COMPOSE_DIR" || exit 1
    docker-compose ps | tee -a "\$LOG_FILE"
     
    # Проверка портов
    echo "Проверка портов:" | tee -a "\$LOG_FILE"
    for port in ${TRAEFIK_PORT} ${TRAEFIK_SECURE_PORT} ${NEWT_PORT} ${API_PORT} ${API_SECURE_PORT} ${GERBIL_PORT}; do
        if netstat -tuln | grep -q ":\$port "; then
            echo "  Порт \$port: ОТКРЫТ" | tee -a "\$LOG_FILE"
        else
            echo "  Порт \$port: ЗАКРЫТ" | tee -a "\$LOG_FILE"
        fi
    done
     
    # Проверка использования ресурсов
    echo "Использование ресурсов:" | tee -a "\$LOG_FILE"
    docker stats --no-stream | grep pangolin | tee -a "\$LOG_FILE"
}

check_service
EOF
     
    chmod +x "$HEALTH_CHECK_FILE"
     
    # Добавление в cron (каждые 6 часов)
    echo "0 */6 * * * root $HEALTH_CHECK_FILE" > /etc/cron.d/pangolin-health
}

# ============================================
# ФИНАЛЬНЫЕ ДЕЙСТВИЯ
# ============================================
finalize_installation() {
    log "Завершение установки..."
    
    # Сохранение информации об установке
    cat > "$INSTALLATION_INFO_FILE" << EOF
========================================
ИНФОРМАЦИЯ ОБ УСТАНОВКЕ PANGO
========================================

Дата установки: $(date)
Публичный IP: ${PUBLIC_IP}
Домен: ${SUBDOMAIN}
Email администратора: ${ADMIN_EMAIL}

Веб-интерфейс: https://${SUBDOMAIN}
API: https://${SUBDOMAIN}:${API_SECURE_PORT}

Директория установки: ${INSTALL_DIR}
Файл конфигурации: ${INSTALL_DIR}/.env

Учетные данные: ${CREDENTIALS_FILE}
Инструкции для клиентов: ${CLIENT_INSTRUCTIONS_FILE}
Лог установки: ${LOG_FILE}

Управление сервисом:
- Статус: cd ${INSTALL_DIR} && docker-compose ps
- Перезапуск: cd ${INSTALL_DIR} && docker-compose restart
- Обновление: cd ${INSTALL_DIR} && docker-compose pull && docker-compose up -d
- Логи: cd ${INSTALL_DIR} && docker-compose logs -f

========================================
EOF
    
    chmod 600 "$INSTALLATION_INFO_FILE"
    log "Финальная информация сохранена"
}

# ============================================
# ГЛАВНАЯ ФУНКЦИЯ
# ============================================
main() {
    parse_args "$@"
    validate_config
    start_logging

    log "========================================="
    log "НАЧАЛО УСТАНОВКИ PANGO SERVER"
    log "========================================="
    
    detect_os
    install_dependencies
    configure_firewall
    install_docker
    install_pangolin
    configure_https
    configure_auto_update
    create_client_instructions
    create_health_check
    finalize_installation
    
    log "========================================="
    log "УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!"
    log "========================================="
    log "Веб-интерфейс: https://${SUBDOMAIN}"
    log "Инструкции для клиентов: ${CLIENT_INSTRUCTIONS_FILE}"
    log "Лог установки: ${LOG_FILE}"
    log "========================================="
    
    # Вывод финальной информации
    echo ""
    echo "✅ Pangolin успешно установлен!"
    echo "🌐 Веб-интерфейс: https://${SUBDOMAIN}"
    echo "📝 Инструкции: ${CLIENT_INSTRUCTIONS_FILE}"
    echo "📋 Лог: ${LOG_FILE}"
    echo "🔑 Учетные данные: ${CREDENTIALS_FILE}"
    echo ""
}

# Запуск установки
main "$@"

exit 0
