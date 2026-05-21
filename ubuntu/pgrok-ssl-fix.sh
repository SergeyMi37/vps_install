#!/bin/bash

# Скрипт для повторной попытки получения SSL сертификатов

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

INSTALL_DIR=${1:-/opt/pgrok}
DOMAIN=${2:-}

if [ -z "$DOMAIN" ]; then
    if [ -f "$INSTALL_DIR/.env" ]; then
        DOMAIN=$(grep PGROK_DOMAIN "$INSTALL_DIR/.env" | cut -d'=' -f2)
    else
        print_error "Укажите домен: $0 /path/to/install domain.example.com"
        exit 1
    fi
fi

print_info "Диагностика SSL для $domain в $INSTALL_DIR"

cd "$INSTALL_DIR" || exit 1

print_info "Статус контейнеров:"
docker compose ps

print_info "Логи nginx:"
docker compose logs --tail=50 nginx

print_info "Проверка занятости портов:"
ss -tuln | grep -E ":80|:443" || print_warning "Порты 80/443 свободны"

print_info "Проверка вебрута:"
docker compose exec nginx ls -la /var/www/certbot/ 2>/dev/null || print_warning "Вебрут не доступен"

print_info "Тестовый запрос к вебруту:"
curl -v "http://$DOMAIN/.well-known/acme-challenge/test" 2>&1 | head -20

print_info "Попытка dry-run получения сертификата..."
docker compose run --rm certbot certonly \
    --webroot \
    --webroot-path=/var/www/certbot \
    --email "$(grep PGROK_ADMIN_EMAIL .env | cut -d'=' -f2)" \
    --agree-tos \
    --no-eff-email \
    --dry-run \
    -d "$DOMAIN" 2>&1

if [ $? -eq 0 ]; then
    print_success "Dry-run успешен! Запускаем полноценное получение..."
    docker compose run --rm certbot certonly \
        --webroot \
        --webroot-path=/var/www/certbot \
        --email "$(grep PGROK_ADMIN_EMAIL .env | cut -d'=' -f2)" \
        --agree-tos \
        --no-eff-email \
        --force-renewal \
        -d "$DOMAIN"
else
    print_error "Dry-run не удался. Проверьте:"
    print_error "1. DNS запись домена указывает на этот сервер"
    print_error "2. Порты 80 и 443 открыты во фаерволе"
    print_error "3. Нет других сервисов на портах 80/443"
    exit 1
fi
