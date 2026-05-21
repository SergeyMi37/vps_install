#!/bin/bash

# Скрипт для быстрого исправления проблем с SSL

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

cd "$INSTALL_DIR" || exit 1

print_info "Создание самоподписанного сертификата для тестирования..."

# Создаем директорию для сертификатов
mkdir -p certbot/conf/live/$(grep PGROK_DOMAIN .env | cut -d'=' -f2)

# Генерируем самоподписанный сертификат
DOMAIN=$(grep PGROK_DOMAIN .env | cut -d'=' -f2)
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "certbot/conf/live/$DOMAIN/privkey.pem" \
    -out "certbot/conf/live/$DOMAIN/fullchain.pem" \
    -subj "/CN=$DOMAIN" 2>/dev/null

print_success "Самоподписанный сертификат создан"

# Перезапускаем nginx
print_info "Перезапуск nginx..."
docker compose restart nginx

sleep 3

print_info "Статус контейнеров:"
docker compose ps
