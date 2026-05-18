#!/bin/bash

# ============================================
# Неинтерактивный установщик Pangolin Server
# Версия: 1.0
# ============================================

set -euo pipefail

# === КОНФИГУРАЦИЯ (ИЗМЕНИТЕ ПОД СВОИ ДАННЫЕ) ===
PUBLIC_IP="ВАШ_ПУБЛИЧНЫЙ_IP"                    # Например: 203.0.113.10
SUBDOMAIN="pangolin.my.site"                    # Ваш субдомен
ADMIN_EMAIL="admin@my.site"                     # Email для Let's Encrypt
PANGO_VERSION="latest"                          # Версия Pangolin
INSTALL_DIR="/opt/pangolin"                     # Директория установки
LOG_FILE="/root/pangolin_install.log"           # Файл протокола
CLIENT_INSTRUCTIONS_FILE="/root/pangolin_client_instructions.txt"  # Инструкции для клиентов

# ============================================
# НАЧАЛО ЛОГИРОВАНИЯ
# ============================================
exec > >(tee -a "$LOG_FILE") 2>&1

echo "========================================"
echo "Установка Pangolin Server начата: $(date)"
echo "========================================"
echo "Публичный IP: $PUBLIC_IP"
echo "Субдомен: $SUBDOMAIN"
echo "Email: $ADMIN_EMAIL"
echo "========================================"

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
    PORTS=(80 443 51820 51821 8443 8080 9000 9001)
    
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
GERBIL_PORT=51820
GERBIL_PEERS_PORT=51821

# Traefik
TRAEFIK_PORT=80
TRAEFIK_SECURE_PORT=443
TRAEFIK_DASHBOARD_PORT=8080

# Newt (прокси)
NEWT_PORT=8443

# API порт
API_PORT=9000
API_SECURE_PORT=9001

# Docker сеть
DOCKER_NETWORK=pangolin_network
EOF
    
    # Запуск через Docker Compose
    docker-compose up -d
    check_error "Не удалось запустить Pangolin"
    
    log "Pangolin запущен успешно"
    
    # Сохранение пароля администратора
    ADMIN_PASSWORD=$(grep PANGO_ADMIN_PASSWORD .env | cut -d'=' -f2)
    echo "ПАРОЛЬ АДМИНИСТРАТОРА PANGO: $ADMIN_PASSWORD" > /root/pangolin_credentials.txt
    chmod 600 /root/pangolin_credentials.txt
    
    log "Учетные данные сохранены в /root/pangolin_credentials.txt"
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
    listen 80;
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
   - Server Port: 443
   - API Port: 9001
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
sudo pangolin config set --server ${SUBDOMAIN} --port 443 --api-port 9001

# Автозапуск как сервис
sudo tee /etc/systemd/system/pangolin-client.service > /dev/null << EOF
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
EOF

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
sudo firewall-cmd --permanent --add-port=51820/udp
sudo firewall-cmd --reload

Шаг 2: Настройка клиента
pangolin config set --server ${SUBDOMAIN} --port 443 --api-port 9001

Шаг 3: Создание systemd сервиса
cat > /etc/systemd/system/pangolin-client.service << EOF
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
EOF

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
- Проверьте, что порты 443 и 9001 открыты на клиенте
- Проверьте DNS разрешение: nslookup ${SUBDOMAIN}
- Проверьте доступность сервера: telnet ${SUBDOMAIN} 443

Проблема: Сертификат недействителен
Решение:
- Убедитесь, что системное время синхронизировано
- Linux: sudo ntpdate pool.ntp.org
- Windows: w32tm /resync

Проблема: Брандмауэр блокирует подключение
Решение:
- Linux: sudo ufw allow 443/tcp && sudo ufw allow 9001/tcp
- Windows: Добавьте pangolin.exe в исключения брандмауэра

========================================================
ДАННЫЕ ДЛЯ ПОДКЛЮЧЕНИЯ:
========================================================
Сервер: ${SUBDOMAIN}
Порт: 443
API порт: 9001
Админ-панель: https://${SUBDOMAIN}
Логин: admin
Пароль: (указан в /root/pangolin_credentials.txt на сервере)

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
    
    cat > /usr/local/bin/pangolin-health-check << 'EOF'
#!/bin/bash
# Скрипт проверки состояния Pangolin

DOCKER_COMPOSE_DIR="/opt/pangolin"
LOG_FILE="/var/log/pangolin-health.log"

check_service() {
    echo "=== Проверка Pangolin: $(date) ===" | tee -a "$LOG_FILE"
    
    # Проверка Docker контейнеров
    cd "$DOCKER_COMPOSE_DIR" || exit 1
    docker-compose ps | tee -a "$LOG_FILE"
    
    # Проверка портов
    echo "Проверка портов:" | tee -a "$LOG_FILE"
    for port in 80 443 8443 9000 9001 51820; do
        if netstat -tuln | grep -q ":$port "; then
            echo "  Порт $port: ОТКРЫТ" | tee -a "$LOG_FILE"
        else
            echo "  Порт $port: ЗАКРЫТ" | tee -a "$LOG_FILE"
        fi
    done
    
    # Проверка использования ресурсов
    echo "Использование ресурсов:" | tee -a "$LOG_FILE"
    docker stats --no-stream | grep pangolin | tee -a "$LOG_FILE"
}

check_service
EOF
    
    chmod +x /usr/local/bin/pangolin-health-check
    
    # Добавление в cron (каждые 6 часов)
    echo "0 */6 * * * root /usr/local/bin/pangolin-health-check" > /etc/cron.d/pangolin-health
}

# ============================================
# ФИНАЛЬНЫЕ ДЕЙСТВИЯ
# ============================================
finalize_installation() {
    log "Завершение установки..."
    
    # Сохранение информации об установке
    cat > /root/pangolin_installation_info.txt << EOF
========================================
ИНФОРМАЦИЯ ОБ УСТАНОВКЕ PANGO
========================================

Дата установки: $(date)
Публичный IP: ${PUBLIC_IP}
Домен: ${SUBDOMAIN}
Email администратора: ${ADMIN_EMAIL}

Веб-интерфейс: https://${SUBDOMAIN}
API: https://${SUBDOMAIN}:9001

Директория установки: ${INSTALL_DIR}
Файл конфигурации: ${INSTALL_DIR}/.env

Учетные данные: /root/pangolin_credentials.txt
Инструкции для клиентов: ${CLIENT_INSTRUCTIONS_FILE}
Лог установки: ${LOG_FILE}

Управление сервисом:
- Статус: cd ${INSTALL_DIR} && docker-compose ps
- Перезапуск: cd ${INSTALL_DIR} && docker-compose restart
- Обновление: cd ${INSTALL_DIR} && docker-compose pull && docker-compose up -d
- Логи: cd ${INSTALL_DIR} && docker-compose logs -f

========================================
EOF
    
    chmod 600 /root/pangolin_installation_info.txt
    log "Финальная информация сохранена"
}

# ============================================
# ГЛАВНАЯ ФУНКЦИЯ
# ============================================
main() {
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
    echo "🔑 Учетные данные: /root/pangolin_credentials.txt"
    echo ""
}

# Запуск установки
main

exit 0