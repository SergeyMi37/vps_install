#!/bin/bash
# wget https://raw.githubusercontent.com/SergeyMi37/vps_install/master/ubuntu/vps_ubuntu_install_aspia_all.sh && sudo chmod +x vps_ubuntu_install_aspia_all.sh && sudo ./vps_ubuntu_install_aspia_all.sh

# Скрипт для установки Aspia Router / Relay на Debian/Ubuntu
# =============================================================================
# Автоматическая установка Aspia Router/Relay с поддержкой субдомена
# Версия: 1.0
# =============================================================================
# Использование:
#   Установка Router:        ./aspia_auto.sh router --domain router.example.com
#   Установка Relay:         ./aspia_auto.sh relay --router-ip 1.2.3.4 --router-pub "КЛЮЧ" --domain relay.example.com
#   Установка Both (всё в 1): ./aspia_auto.sh both --domain my.aspia.com
#   Только Router без домена: ./aspia_auto.sh router
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
    ufw allow 8070/tcp comment 'Aspia Router' > /dev/null 2>&1
    ufw allow 8080/tcp comment 'Aspia Relay' > /dev/null 2>&1
    
    echo "y" | ufw enable > /dev/null 2>&1
    print_info "Порты открыты: 22, 8070, 8080"
}

# --- Функция настройки субдомена с SSL (Nginx + Certbot) ---
setup_domain() {
    local DOMAIN=$1
    local EMAIL=${2:-"admin@${DOMAIN}"}
    
    print_step "Настройка субдомена: ${DOMAIN}"
    
    # Установка Nginx и Certbot
    apt update > /dev/null 2>&1
    apt install -y nginx certbot python3-certbot-nginx > /dev/null 2>&1
    
    # Создание конфига Nginx
    cat > /etc/nginx/sites-available/aspia <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    
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
    nginx -t > /dev/null 2>&1
    systemctl reload nginx
    
    # Получение SSL сертификата
    print_info "Получение SSL сертификата для ${DOMAIN}..."
    certbot --nginx -d "${DOMAIN}" --non-interactive --agree-tos --email "${EMAIL}" --redirect > /dev/null 2>&1
    
    print_info "Субдомен ${DOMAIN} настроен с SSL"
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
    
    # Сохраняем публичный ключ для вывода
    local PUB_KEY=$(cat /etc/aspia/router.pub 2>/dev/null || echo "Файл ключа не найден")
    
    print_info "✓ Aspia Router установлен и запущен"
    echo -e "${YELLOW}📋 Публичный ключ Router (сохраните для Relay):${NC}"
    echo -e "${BLUE}${PUB_KEY}${NC}"
    echo ""
    
    # Возвращаем путь к ключу для использования в both режиме
    echo "/etc/aspia/router.pub"
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
    
    print_info "✓ Aspia Relay установлен и запущен"
    print_info "Relay адрес: ${PEER_DOMAIN}:${RELAY_PORT}"
}

# --- Функция изменения пароля admin ---
change_admin_password() {
    print_step "Смена пароля admin (по умолчанию admin:admin)"
    
    # Проверяем, существует ли aspia_router
    if command -v aspia_router &> /dev/null; then
        read -s -p "Введите новый пароль для admin: " NEW_PASS
        echo ""
        if [[ -n "$NEW_PASS" ]]; then
            # Aspia не имеет прямого CLI для смены пароля, но можно через создание нового конфига
            print_warn "Для смены пароля используйте Aspia Console после установки"
            print_warn "Инструкция: https://habr.com/ru/articles/711122/"
        fi
    fi
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
            echo ""
            echo "Примеры:"
            echo "  $0 router --domain router.example.com"
            echo "  $0 relay --domain relay.example.com --router-ip 10.0.0.1 --router-pub \"AAAAB3Nza...\""
            echo "  $0 both --domain my.aspia.com --email admin@my.aspia.com"
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
        setup_router "$DOMAIN" > /dev/null
        if [[ -n "$DOMAIN" ]]; then
            setup_domain "$DOMAIN" "${EMAIL}"
        fi
        ;;
    
    relay)
        setup_relay "$ROUTER_IP" "$ROUTER_PUB_KEY" "$DOMAIN" "$ROUTER_PORT" "$RELAY_PORT"
        # Для Relay не настраиваем веб-интерфейс
        ;;
    
    both)
        print_step "Установка Router + Relay на одном сервере"
        
        # Устанавливаем Router
        setup_router "$DOMAIN" > /tmp/router_pub_path.txt
        local PUB_KEY=$(cat /etc/aspia/router.pub)
        
        # Настраиваем Router для работы с Relay (добавляем localhost в белый список)
        sed -i 's/"relayWhiteList": \[\]/"relayWhiteList": ["127.0.0.1"]/' /etc/aspia/router.json
        systemctl restart aspia-router > /dev/null 2>&1
        
        # Устанавливаем Relay
        setup_relay "127.0.0.1" "$PUB_KEY" "$DOMAIN" "8070" "8080"
        
        # Настраиваем домен с SSL
        setup_domain "$DOMAIN" "${EMAIL}"
        
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
        if [[ -n "$DOMAIN" ]]; then
            echo "   - Веб-интерфейс (если доступен): https://${DOMAIN}"
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
        echo "   - Веб-интерфейс Router: https://${DOMAIN}"
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