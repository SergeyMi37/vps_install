#!/bin/bash
# =============================================================================
# Автоматическая установка Aspia Router/Relay с поддержкой субдомена
# wget https://raw.githubusercontent.com/SergeyMi37/vps_install/master/ubuntu/vps_ubuntu_install_aspia_all.sh && sudo chmod +x vps_ubuntu_install_aspia_all.sh && sudo ./vps_ubuntu_install_aspia_all.sh
# =============================================================================

set -e

# --- Цвета для вывода ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
print_debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }

# --- Проверка root ---
if [[ $EUID -ne 0 ]]; then
   print_error "Скрипт должен запускаться от root (sudo)"
   exit 1
fi

# --- Установка wget если нужно ---
if ! command -v wget &> /dev/null; then
    print_warn "Устанавливаю wget..."
    apt update && apt install wget -y
fi

# --- Функция установки компонента ---
install_component() {
    local COMP_NAME=$1
    local PKG_NAME=$2
    local VERSION="2.7.0"
    local URL="https://github.com/dchapyshev/aspia/releases/download/v${VERSION}/${PKG_NAME}-${VERSION}-x86_64.deb"

    print_step "Установка ${COMP_NAME}..."
    cd /tmp
    rm -f "${PKG_NAME}"*.deb 2>/dev/null

    if wget -q --show-progress "${URL}"; then
        apt install -y "./${PKG_NAME}-${VERSION}-x86_64.deb" > /dev/null 2>&1
        print_info "${COMP_NAME} установлен"
    else
        print_error "Не удалось скачать ${COMP_NAME}"
        exit 1
    fi
}

# --- Функция настройки фаервола (UFW) ---
setup_firewall() {
    if ! command -v ufw &> /dev/null; then
        apt install -y ufw
    fi
    
    print_step "Настройка фаервола..."
    ufw allow 22/tcp comment 'SSH' > /dev/null 2>&1
    ufw allow 80/tcp comment 'HTTP' > /dev/null 2>&1
    ufw allow 443/tcp comment 'HTTPS' > /dev/null 2>&1
    ufw allow 8070/tcp comment 'Aspia Router' > /dev/null 2>&1
    ufw allow 8080/tcp comment 'Aspia Relay' > /dev/null 2>&1
    
    echo "y" | ufw enable > /dev/null 2>&1
    print_info "Порты открыты: 22, 80, 443, 8070, 8080"
}

# --- Функция проверки DNS ---
check_dns() {
    local DOMAIN=$1
    print_step "Проверка DNS для ${DOMAIN}..."
    
    local SERVER_IP=$(curl -s ifconfig.me)
    local DOMAIN_IP=$(dig +short ${DOMAIN} | head -1)
    
    if [[ -z "$DOMAIN_IP" ]]; then
        print_error "Домен ${DOMAIN} не резолвится в DNS!"
        print_warn "Добавьте A-запись: ${DOMAIN} -> ${SERVER_IP}"
        return 1
    fi
    
    if [[ "$DOMAIN_IP" != "$SERVER_IP" ]]; then
        print_error "Домен ${DOMAIN} указывает на ${DOMAIN_IP}, но сервер имеет IP ${SERVER_IP}"
        print_warn "Исправьте DNS запись или используйте --ip параметр"
        return 1
    fi
    
    print_info "✓ DNS проверена: ${DOMAIN} -> ${DOMAIN_IP}"
    return 0
}

# --- Функция настройки субдомена с SSL (Nginx + Certbot) ---
setup_domain() {
    local DOMAIN=$1
    local EMAIL=${2:-"admin@${DOMAIN}"}
    
    print_step "Настройка субдомена: ${DOMAIN}"
    
    # Проверка DNS перед продолжением
    if ! check_dns "$DOMAIN"; then
        print_error "SSL сертификат не может быть выдан из-за проблем с DNS"
        print_info "Продолжаем установку без SSL (только HTTP)..."
        return 1
    fi
    
    # Установка Nginx и Certbot
    apt update > /dev/null 2>&1
    apt install -y nginx certbot python3-certbot-nginx curl dnsutils > /dev/null 2>&1
    
    # Останавливаем nginx если он мешает
    systemctl stop nginx 2>/dev/null || true
    
    # Создание конфига Nginx для HTTP (временный)
    cat > /etc/nginx/sites-available/aspia <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    root /var/www/html;
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    
    location / {
        proxy_pass http://127.0.0.1:8070;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
    
    # Активация сайта
    ln -sf /etc/nginx/sites-available/aspia /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    # Проверка и запуск Nginx
    nginx -t
    systemctl start nginx
    systemctl enable nginx
    
    # Создание временной директории для проверки
    mkdir -p /var/www/html/.well-known/acme-challenge/
    chown -R www-data:www-data /var/www/html/
    
    # Получение SSL сертификата с отладкой
    print_info "Получение SSL сертификата для ${DOMAIN}..."
    
    # Пробуем получить сертификат в тестовом режиме
    if certbot certonly --webroot -w /var/www/html \
        -d "${DOMAIN}" \
        --email "${EMAIL}" \
        --agree-tos \
        --no-eff-email \
        --staging \
        --debug-challenges \
        --non-interactive; then
        
        print_info "Тестовый сертификат получен, получаем реальный..."
        
        # Получаем реальный сертификат
        certbot --nginx -d "${DOMAIN}" \
            --email "${EMAIL}" \
            --agree-tos \
            --no-eff-email \
            --redirect \
            --non-interactive
        
    else
        print_warn "Тестовый режим не удался, пробуем реальный..."
        
        # Пробуем получить реальный сертификат
        if certbot --nginx -d "${DOMAIN}" \
            --email "${EMAIL}" \
            --agree-tos \
            --no-eff-email \
            --redirect \
            --non-interactive \
            --force-renewal; then
            
            print_info "SSL сертификат успешно получен"
        else
            print_error "Не удалось получить SSL сертификат"
            print_warn "Проверьте:"
            echo "  1. DNS запись ${DOMAIN} указывает на этот сервер"
            echo "  2. Порт 80 открыт в firewall"
            echo "  3. Nginx запущен и слушает порт 80"
            echo ""
            print_info "Продолжаем работу без HTTPS (только HTTP)"
            
            # Убираем редирект на HTTPS
            sed -i 's/return 301 https/#return 301 https/' /etc/nginx/sites-available/aspia
            systemctl reload nginx
            return 1
        fi
    fi
    
    print_info "Субдомен ${DOMAIN} настроен с SSL"
    return 0
}

# --- Функция настройки Router ---
setup_router() {
    local DOMAIN=$1
    
    print_step "Установка Aspia Router"
    install_component "Aspia Router" "aspia-router"
    
    # Генерация конфига
    aspia_router --create-config > /dev/null 2>&1
    
    # Если указан домен - добавляем его в конфиг
    if [[ -n "$DOMAIN" ]]; then
        sed -i "s/\"peerAddress\": \"[^\"]*\"/\"peerAddress\": \"${DOMAIN}\"/" /etc/aspia/router.json
        print_info "Домен ${DOMAIN} добавлен в конфиг Router"
    fi
    
    # Запуск сервиса
    systemctl enable aspia-router > /dev/null 2>&1
    systemctl start aspia-router
    
    # Проверка статуса
    sleep 2
    if systemctl is-active --quiet aspia-router; then
        print_info "✓ Aspia Router запущен"
    else
        print_warn "Aspia Router не запустился, проверьте: journalctl -u aspia-router"
    fi
    
    # Сохраняем публичный ключ
    PUB_KEY=$(cat /etc/aspia/router.pub 2>/dev/null || echo "Файл ключа не найден")
    
    print_info "✓ Aspia Router установлен"
    echo -e "${YELLOW}📋 Публичный ключ Router (сохраните для Relay):${NC}"
    echo -e "${BLUE}${PUB_KEY}${NC}"
    echo ""
}

# --- Функция настройки Relay ---
setup_relay() {
    local ROUTER_IP=$1
    local ROUTER_PUB_KEY=$2
    local PEER_DOMAIN=$3
    local ROUTER_PORT=${4:-8070}
    local RELAY_PORT=${5:-8080}
    
    print_step "Установка Aspia Relay"
    install_component "Aspia Relay" "aspia-relay"
    
    # Автоматическое создание конфига
    cat > /etc/aspia/relay.json <<EOF
{
  "routerAddress": "${ROUTER_IP}",
  "routerPort": ${ROUTER_PORT},
  "routerPublicKey": "${ROUTER_PUB_KEY}",
  "peerAddress": "${PEER_DOMAIN}",
  "peerPort": ${RELAY_PORT},
  "relayPort": 8081,
  "enableRelay": true,
  "enableSTUN": true,
  "enableTURN": false,
  "iceServers": []
}
EOF
    
    # Запуск сервиса
    systemctl enable aspia-relay > /dev/null 2>&1
    systemctl start aspia-relay
    
    # Проверка статуса
    sleep 2
    if systemctl is-active --quiet aspia-relay; then
        print_info "✓ Aspia Relay запущен"
    else
        print_warn "Aspia Relay не запустился, проверьте: journalctl -u aspia-relay"
    fi
    
    print_info "✓ Aspia Relay установлен"
    print_info "Relay адрес: ${PEER_DOMAIN}:${RELAY_PORT}"
}

# --- Парсинг аргументов ---
MODE="$1"
shift

# Параметры по умолчанию
DOMAIN=""
ROUTER_IP="127.0.0.1"
ROUTER_PORT="8070"
ROUTER_PUB_KEY=""
RELAY_PORT="8080"
EMAIL=""

# Парсинг флагов
while [[ $# -gt 0 ]]; do
    case "$1" in
        --domain|-d)
            DOMAIN="$2"
            shift 2
            ;;
        --router-ip)
            ROUTER_IP="$2"
            shift 2
            ;;
        --router-port)
            ROUTER_PORT="$2"
            shift 2
            ;;
        --router-pub)
            ROUTER_PUB_KEY="$2"
            shift 2
            ;;
        --relay-port)
            RELAY_PORT="$2"
            shift 2
            ;;
        --email|-e)
            EMAIL="$2"
            shift 2
            ;;
        --skip-ssl)
            SKIP_SSL=1
            shift
            ;;
        --help|-h)
            echo "Использование: $0 [режим] [опции]"
            echo ""
            echo "Режимы:"
            echo "  router              - установить только Router"
            echo "  relay               - установить только Relay"
            echo "  both                - установить Router+Relay на одном сервере"
            echo ""
            echo "Опции:"
            echo "  --domain, -d DOMAIN       - субдомен для Relay (обязательно для relay/both)"
            echo "  --router-ip IP            - IP адрес Router (по умолчанию: 127.0.0.1)"
            echo "  --router-port PORT        - порт Router (по умолчанию: 8070)"
            echo "  --router-pub KEY          - публичный ключ Router (обязательно для relay)"
            echo "  --relay-port PORT         - порт Relay (по умолчанию: 8080)"
            echo "  --email, -e EMAIL         - email для SSL сертификата"
            echo "  --skip-ssl                - пропустить настройку SSL"
            echo ""
            echo "Примеры:"
            echo "  $0 router --domain router.example.com"
            echo "  $0 relay --domain relay.example.com --router-ip 10.0.0.1 --router-pub \"AAAAB3Nza...\""
            echo "  $0 both --domain my.aspia.com --email admin@my.aspia.com --skip-ssl"
            exit 0
            ;;
        *)
            print_error "Неизвестный параметр: $1"
            echo "Используйте --help для справки"
            exit 1
            ;;
    esac
done

# --- Проверка обязательных параметров ---
case "$MODE" in
    router)
        if [[ -z "$DOMAIN" ]]; then
            print_warn "Домен не указан, будет использован IP-адрес сервера"
        fi
        ;;
    relay)
        if [[ -z "$DOMAIN" ]]; then
            print_error "Для Relay необходимо указать --domain"
            exit 1
        fi
        if [[ -z "$ROUTER_PUB_KEY" ]]; then
            print_error "Для Relay необходимо указать --router-pub"
            exit 1
        fi
        ;;
    both)
        if [[ -z "$DOMAIN" ]]; then
            print_error "Для режима both необходимо указать --domain"
            exit 1
        fi
        ;;
    *)
        print_error "Неверный режим. Используйте: router, relay или both"
        echo "Пример: $0 both --domain my.aspia.com"
        exit 1
        ;;
esac

# --- Основная логика ---
echo "============================================="
echo "   Aspia Auto Installer с поддержкой домена"
echo "============================================="
echo ""

# Обновление системы
print_step "Обновление пакетов..."
apt update > /dev/null 2>&1

# Настройка фаервола
setup_firewall

# Выполнение в зависимости от режима
case "$MODE" in
    router)
        setup_router "$DOMAIN"
        if [[ -n "$DOMAIN" ]] && [[ -z "$SKIP_SSL" ]]; then
            setup_domain "$DOMAIN" "${EMAIL}" || true
        fi
        ;;
    
    relay)
        setup_relay "$ROUTER_IP" "$ROUTER_PUB_KEY" "$DOMAIN" "$ROUTER_PORT" "$RELAY_PORT"
        # Для Relay не настраиваем веб-интерфейс
        ;;
    
    both)
        print_step "Установка Router + Relay на одном сервере"
        
        # Устанавливаем Router
        setup_router "$DOMAIN"
        
        # Получаем публичный ключ
        PUB_KEY=$(cat /etc/aspia/router.pub)
        
        # Настраиваем Router для работы с Relay
        if grep -q "relayWhiteList" /etc/aspia/router.json; then
            sed -i 's/"relayWhiteList": \[\]/"relayWhiteList": ["127.0.0.1"]/' /etc/aspia/router.json
        else
            sed -i '/{/a "relayWhiteList": ["127.0.0.1"],' /etc/aspia/router.json
        fi
        
        systemctl restart aspia-router > /dev/null 2>&1
        
        # Устанавливаем Relay
        setup_relay "127.0.0.1" "$PUB_KEY" "$DOMAIN" "8070" "8080"
        
        # Настраиваем домен с SSL (если не пропущено)
        if [[ -z "$SKIP_SSL" ]]; then
            setup_domain "$DOMAIN" "${EMAIL}" || true
        fi
        
        print_info "✓ Router и Relay успешно настроены на одном сервере"
        ;;
esac

# --- Финальная информация ---
echo ""
echo "============================================="
print_info "🎉 Установка завершена!"
echo "============================================="
echo ""

case "$MODE" in
    router)
        echo "🌐 Aspia Router:"
        echo "   - Порт: 8070"
        echo "   - Логин/пароль по умолчанию: admin / admin"
        if [[ -n "$DOMAIN" ]] && [[ -z "$SKIP_SSL" ]]; then
            echo "   - Веб-интерфейс: https://${DOMAIN}"
        elif [[ -n "$DOMAIN" ]]; then
            echo "   - Веб-интерфейс: http://${DOMAIN}"
        fi
        echo "   - Публичный ключ: /etc/aspia/router.pub"
        ;;
    relay)
        echo "🔄 Aspia Relay:"
        echo "   - Адрес для клиентов: ${DOMAIN}:${RELAY_PORT}"
        echo "   - Порт Relay: 8081 (внутренний)"
        echo "   - Router IP: ${ROUTER_IP}:${ROUTER_PORT}"
        ;;
    both)
        echo "🚀 Aspia Router + Relay (одна машина):"
        echo "   - Router порт: 8070"
        echo "   - Relay порт: 8080"
        echo "   - Адрес клиентов: ${DOMAIN}:8080"
        echo "   - Публичный ключ Router: /etc/aspia/router.pub"
        if [[ -z "$SKIP_SSL" ]]; then
            echo "   - Веб-интерфейс Router: https://${DOMAIN}"
        else
            echo "   - Веб-интерфейс Router: http://${DOMAIN}"
        fi
        ;;
esac

echo ""
print_warn "⚠️  Важные действия после установки:"
echo "   1. Смените пароль admin через Aspia Console"
echo "   2. Проверьте статус служб:"
echo "      systemctl status aspia-router aspia-relay"
echo "   3. Посмотрите логи при проблемах:"
echo "      journalctl -u aspia-router -f"
echo "      journalctl -u aspia-relay -f"
echo ""
print_info "Подробная документация: https://habr.com/ru/articles/711122/"