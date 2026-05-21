#!/bin/bash

# Скрипт для быстрой диагностики проблем с контейнерами

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

echo "========================================="
echo "  Диагностика pgrok контейнеров"
echo "========================================="

print_info "Статус контейнеров:"
docker compose ps

echo ""
print_info "Логи nginx (последние 50 строк):"
echo "-----------------------------------------"
docker compose logs --tail=50 nginx
echo ""

print_info "Логи pgrokd (последние 50 строк):"
echo "-----------------------------------------"
docker compose logs --tail=50 pgrokd
echo ""

print_info "Проверка конфигурационных файлов:"
echo "-----------------------------------------"
if [ -f "nginx/nginx.conf" ]; then
    print_success "nginx/nginx.conf существует"
else
    print_error "nginx/nginx.conf не най!"
fi

if [ -f "nginx/conf.d/pgrok.conf" ]; then
    print_success "nginx/conf.d/pgrok.conf существует"
else
    print_error "nginx/conf.d/pgrok.conf не най!"
fi

if [ -f "pgrokd/config.yml" ]; then
    print_success "pgrokd/config.yml существует"
else
    print_error "pgrokd/config.yml не най!"
fi

echo ""
print_info "Проверка прав на файлы:"
echo "-----------------------------------------"
ls -la nginx/
ls -la nginx/conf.d/
ls -la pgrokd/

echo ""
print_info "Проверка mount volumes:"
echo "-----------------------------------------"
docker compose ps -q nginx | xargs docker inspect --format 'Nginx volumes:' {{range .Mounts}}{{if eq .Type "bind"}}{{.Source}} -> {{.Destination}}{{end}}{{end}}
docker compose ps -q pgrokd | xargs docker inspect --format 'Pgrokd volumes:' {{range .Mounts}}{{if eq .Type "bind"}}{{.Source}} -> {{.Destination}}{{end}}{{end}}

echo ""
print_info "Проверка сети:"
echo "-----------------------------------------"
docker network ls | grep pgrok
docker compose ps -q | xargs docker inspect --format '{{.Name}}: {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
