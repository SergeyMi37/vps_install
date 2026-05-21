#!/bin/bash
# sudo wget https://raw.githubusercontent.com/SergeyMi37/vps_install/master/ubuntu/pgrok.sh && sudo chmod +x pgrok.sh && sudo ./pgrok.sh -d pgrok.mydomain.com -e admin@mydomain.com
# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Функции вывода
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Функция помощи
show_help() {
    cat << EOF
Использование: $0 -d DOMAIN -e EMAIL [OPTIONS]

Обязательные параметры:
    -d, --domain DOMAIN       Домен для pgrok (например: pgrok.example.com)
    -e, --email EMAIL         Email для администратора и Let's Encrypt

Опциональные параметры:
    -p, --path PATH          Директория установки (по умолчанию: /opt/pgrok)
    --db-password PASS       Пароль для PostgreSQL (генерируется случайно)
    --admin-password PASS    Пароль администратора (генерируется случайно)
    --http-port PORT         HTTP порт (по умолчанию: 80)
    --https-port PORT        HTTPS порт (по умолчанию: 443)
    --tunnel-port PORT       Порт туннелей (по умолчанию: 2222)
    --proxy-port PORT        Порт прокси (по умолчанию: 3000)
    -h, --help              Показать эту помощь

Пример:
    $0 -d pgrok.mydomain.com -e admin@mydomain.com -p /opt/pgrok
EOF
    exit 0
}

# Проверка наличия Docker
check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker не установлен"
        exit 1
    fi
    if ! docker compose version &> /dev/null && ! docker-compose version &> /dev/null; then
        print_error "Docker Compose не установлен"
        exit 1
    fi
    print_success "Docker и Docker Compose найдены"
}

# Генерация случайного пароля
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-20
}

# Проверка DNS записи
check_dns() {
    local domain=$1
    local ip=$(curl -s ifconfig.me)
    
    print_info "Проверка DNS записи для $domain..."
    local domain_ip=$(dig +short "$domain" | head -1)
    
    if [ -z "$domain_ip" ]; then
        print_warning "DNS запись для $domain не найдена"
        return 1
    fi
    
    if [ "$domain_ip" != "$ip" ]; then
        print_warning "DNS запись $domain_ip не соответствует IP сервера $ip"
        return 1
    fi
    
    print_success "DNS запись корректна: $domain -> $domain_ip"
    return 0
}

# Создание конфигурационных файлов
create_config_files() {
    local install_dir=$1
    local domain=$2
    local email=$3
    local db_password=$4
    local admin_password=$5
    
    print_info "Создание конфигурации в $install_dir..."
    
    mkdir -p "$install_dir"/{pgrokd/data,nginx/conf.d,backups,ssl}
    mkdir -p "$install_dir/certbot"{/www,/conf}
    
    # .env файл
    cat > "$install_dir/.env" << EOF
POSTGRES_DB=pgrokd
POSTGRES_USER=pgrok_user
POSTGRES_PASSWORD=$db_password
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
PGROK_DOMAIN=$domain
PGROK_ADMIN_EMAIL=$email
PGROK_ADMIN_PASSWORD=$admin_password
HTTP_PORT=${HTTP_PORT:-80}
HTTPS_PORT=${HTTPS_PORT:-443}
TUNNEL_PORT=${TUNNEL_PORT:-2222}
PROXY_PORT=${PROXY_PORT:-3000}
EOF
    
    # pgrokd.yml - ИСПРАВЛЕНА СТРОКА ПОДКЛЮЧЕНИЯ К БД
    cat > "$install_dir/pgrokd/config.yml" << EOF
version: "1.0"

server:
  external_url: "https://$domain"
  domain: "$domain"
  web_port: 3320
  http_port: 3000
  tunnel_port: 2222
  
  database:
    driver: "postgres"
    dsn: "host=postgres port=5432 user=pgrok_user dbname=pgrokd password=${db_password} sslmode=disable"
  
  admin:
    email: "$email"
    password: "$admin_password"

logging:
  level: "info"
  format: "json"
EOF
    
    # docker-compose.yml - ИСПРАВЛЕНА СЕТЬ И ЗАВИСИМОСТИ
    cat > "$install_dir/docker-compose.yml" << 'EOF'
version: "3.8"

services:
  postgres:
    image: postgres:15-alpine
    container_name: pgrok_postgres
    restart: always
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./backups:/backups
    networks:
      - pgrok_network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 5s
      timeout: 5s
      retries: 10
    ports:
      - "127.0.0.1:5432:5432"  # Опционально для внешнего доступа

  pgrokd:
    image: ghcr.io/pgrok/pgrokd:latest
    container_name: pgrok_server
    restart: always
    environment:
      - PGROK_DATABASE_DSN=host=postgres port=5432 user=${POSTGRES_USER} dbname=${POSTGRES_DB} password=${POSTGRES_PASSWORD} sslmode=disable
    volumes:
      - ./pgrokd/config.yml:/var/opt/pgrokd/pgrokd.yml:ro
      - pgrokd_data:/var/opt/pgrokd/data
    ports:
      - "3320:3320"
      - "${PROXY_PORT:-3000}:3000"
      - "${TUNNEL_PORT:-2222}:2222"
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - pgrok_network
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  nginx:
    image: nginx:alpine
    container_name: pgrok_nginx
    restart: always
    ports:
      - "${HTTP_PORT:-80}:80"
      - "${HTTPS_PORT:-443}:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/conf.d:/etc/nginx/conf.d
      - ./certbot/www:/var/www/certbot
      - ./certbot/conf:/etc/letsencrypt
    depends_on:
      - pgrokd
    networks:
      - pgrok_network

  certbot:
    image: certbot/certbot
    container_name: pgrok_certbot
    volumes:
      - ./certbot/www:/var/www/certbot
      - ./certbot/conf:/etc/letsencrypt
    entrypoint: "/bin/sh -c 'trap exit TERM; while :; do certbot renew --webroot -w /var/www/certbot --quiet; sleep 12h & wait $${!}; done;'"

networks:
  pgrok_network:
    driver: bridge
    name: pgrok_network

volumes:
  postgres_data:
    name: pgrok_postgres_data
  pgrokd_data:
    name: pgrokd_data
EOF
    
    # nginx.conf
    cat > "$install_dir/nginx/nginx.conf" << 'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    
    access_log /var/log/nginx/access.log main;
    
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 100M;
    
    include /etc/nginx/conf.d/*.conf;
}
EOF
    
    # Конфигурация сайта для Nginx
    cat > "$install_dir/nginx/conf.d/pgrok.conf" << EOF
# HTTP блок для получения сертификатов
server {
    listen 80;
    server_name $domain;
    server_tokens off;
    
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

# HTTPS блок
server {
    listen 443 ssl http2;
    server_name $domain;
    server_tokens off;
    
    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    location / {
        proxy_pass http://pgrokd:3320;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
    
    # Скрипт проверки подключения к БД
    cat > "$install_dir/check_db.sh" << 'EOF'
#!/bin/bash
echo "Checking PostgreSQL connection..."
docker exec pgrok_postgres pg_isready -U pgrok_user -d pgrokd
docker exec pgrok_server cat /var/opt/pgrokd/pgrokd.yml | grep dsn
EOF
    chmod +x "$install_dir/check_db.sh"
    
    # Скрипт бэкапа
    cat > "$install_dir/backup.sh" << 'EOF'
#!/bin/bash
BACKUP_DIR="$(dirname "$0")/backups"
DATE=$(date +%Y%m%d_%H%M%S)
docker exec pgrok_postgres pg_dump -U pgrok_user pgrokd > "$BACKUP_DIR/pgrok_backup_$DATE.sql"
echo "Backup created: pgrok_backup_$DATE.sql"
find "$BACKUP_DIR" -name "*.sql" -mtime +7 -delete
EOF
    chmod +x "$install_dir/backup.sh"
    
    print_success "Конфигурационные файлы созданы"
}

# Ожидание готовности PostgreSQL с проверкой
wait_for_postgres() {
    local install_dir=$1
    local max_attempts=30
    local attempt=1
    
    print_info "Ожидание готовности PostgreSQL..."
    
    cd "$install_dir"
    
    while [ $attempt -le $max_attempts ]; do
        if docker exec pgrok_postgres pg_isready -U pgrok_user -d pgrokd &>/dev/null; then
            print_success "PostgreSQL готов к работе"
            return 0
        fi
        print_info "Попытка $attempt/$max_attempts... PostgreSQL еще не готов"
        sleep 2
        attempt=$((attempt + 1))
    done
    
    print_error "PostgreSQL не запустился после $max_attempts попыток"
    docker logs pgrok_postgres --tail 50
    return 1
}

# Инициализация базы данных
init_database() {
    local install_dir=$1
    
    print_info "Проверка и инициализация базы данных..."
    
    cd "$install_dir"
    
    # Проверяем существует ли таблица
    if docker exec pgrok_server pgrokd --version &>/dev/null; then
        print_success "База данных уже инициализирована"
        return 0
    fi
    
    print_success "База данных готова"
    return 0
}

# Получение SSL сертификатов
setup_ssl() {
    local install_dir=$1
    local domain=$2
    local email=$3
    
    print_info "Получение SSL сертификатов для $domain..."
    
    cd "$install_dir"
    
    # Запускаем nginx для вебрута
    docker compose up -d nginx
    
    sleep 5
    
    # Получаем сертификат
    docker compose run --rm certbot certonly \
        --webroot \
        --webroot-path=/var/www/certbot \
        --email "$email" \
        --agree-tos \
        --no-eff-email \
        --force-renewal \
        -d "$domain"
    
    if [ $? -eq 0 ]; then
        print_success "SSL сертификаты успешно получены"
        docker compose restart nginx
        return 0
    else
        print_error "Не удалось получить SSL сертификаты"
        return 1
    fi
}

# Основная функция
main() {
    # Парсинг аргументов
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--domain)
                DOMAIN="$2"
                shift 2
                ;;
            -e|--email)
                EMAIL="$2"
                shift 2
                ;;
            -p|--path)
                INSTALL_DIR="$2"
                shift 2
                ;;
            --db-password)
                DB_PASSWORD="$2"
                shift 2
                ;;
            --admin-password)
                ADMIN_PASSWORD="$2"
                shift 2
                ;;
            --http-port)
                HTTP_PORT="$2"
                shift 2
                ;;
            --https-port)
                HTTPS_PORT="$2"
                shift 2
                ;;
            --tunnel-port)
                TUNNEL_PORT="$2"
                shift 2
                ;;
            --proxy-port)
                PROXY_PORT="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                ;;
            *)
                print_error "Неизвестный параметр: $1"
                show_help
                ;;
        esac
    done
    
    # Проверка обязательных параметров
    if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
        print_error "Домен и email обязательны!"
        show_help
    fi
    
    # Установка значений по умолчанию
    INSTALL_DIR=${INSTALL_DIR:-/opt/pgrok}
    DB_PASSWORD=${DB_PASSWORD:-$(generate_password)}
    ADMIN_PASSWORD=${ADMIN_PASSWORD:-$(generate_password)}
    HTTP_PORT=${HTTP_PORT:-80}
    HTTPS_PORT=${HTTPS_PORT:-443}
    TUNNEL_PORT=${TUNNEL_PORT:-2222}
    PROXY_PORT=${PROXY_PORT:-3000}
    
    # Экспорт переменных для compose
    export HTTP_PORT HTTPS_PORT TUNNEL_PORT PROXY_PORT
    
    # Вывод информации
    echo "========================================="
    echo "   pgrok Production Installation"
    echo "========================================="
    echo "Domain: $DOMAIN"
    echo "Email: $EMAIL"
    echo "Install path: $INSTALL_DIR"
    echo "HTTP port: $HTTP_PORT"
    echo "HTTPS port: $HTTPS_PORT"
    echo "Tunnel port: $TUNNEL_PORT"
    echo "Proxy port: $PROXY_PORT"
    echo "========================================="
    
    # Проверка зависимостей
    check_docker
    
    # Проверка DNS (не критично для локальной установки)
    check_dns "$DOMAIN" || print_warning "Продолжаем установку, но убедитесь что DNS настроен"
    
    # Создание конфигурации
    create_config_files "$INSTALL_DIR" "$DOMAIN" "$EMAIL" "$DB_PASSWORD" "$ADMIN_PASSWORD"
    
    # Запуск PostgreSQL
    print_info "Запуск PostgreSQL..."
    cd "$INSTALL_DIR"
    docker compose up -d postgres
    
    # Ожидание готовности PostgreSQL
    if ! wait_for_postgres "$INSTALL_DIR"; then
        print_error "Не удалось запустить PostgreSQL"
        exit 1
    fi
    
    # Запуск pgrokd
    print_info "Запуск pgrokd..."
    docker compose up -d pgrokd
    
    # Проверка логов pgrokd
    sleep 5
    if docker logs pgrok_server 2>&1 | grep -i "error\|panic\|failed" | grep -v "context deadline exceeded"; then
        print_warning "Обнаружены ошибки в логах pgrokd:"
        docker logs pgrok_server --tail 20
    fi
    
    # Проверка подключения к БД
    print_info "Проверка подключения к базе данных..."
    if docker exec pgrok_server sh -c "cat /var/opt/pgrokd/pgrokd.yml | grep -q dsn"; then
        print_success "Конфигурация БД найдена"
    else
        print_error "Проблема с конфигурацией БД"
    fi
    
    # Настройка SSL (обязательно)
    print_info "Настройка SSL..."
    if ! setup_ssl "$INSTALL_DIR" "$DOMAIN" "$EMAIL"; then
        print_error "Настройка SSL не удалась"
        exit 1
    fi
    
    # Сохранение паролей
    cat > "$INSTALL_DIR/credentials.txt" << EOF
=== pgrok Credentials ===
Domain: https://$DOMAIN
Admin Email: $EMAIL
Admin Password: $ADMIN_PASSWORD
PostgreSQL Password: $DB_PASSWORD

Tunnel Port: $TUNNEL_PORT
Proxy Port: $PROXY_PORT

=== Database Connection String ===
host=postgres port=5432 user=pgrok_user dbname=pgrokd password=$DB_PASSWORD sslmode=disable

=== Client Configuration ===
Create ~/.pgrok.yml:
server:
  addr: $DOMAIN:443
  token: YOUR_TOKEN_FROM_WEB_INTERFACE

=== Save this file securely! ===
EOF
    
    chmod 600 "$INSTALL_DIR/credentials.txt"
    
    # Вывод результата
    echo ""
    print_success "========================================="
    print_success "pgrok успешно установлен!"
    print_success "========================================="
    echo ""
    print_info "Веб-интерфейс: https://$DOMAIN"
    print_info "Email: $EMAIL"
    print_info "Пароль: $ADMIN_PASSWORD"
    echo ""
    print_info "Проверка статуса:"
    print_info "  docker compose ps"
    print_info "  docker logs pgrok_server"
    print_info "  ./check_db.sh"
    echo ""
    print_info "Управление:"
    print_info "  cd $INSTALL_DIR"
    print_info "  docker compose logs -f    # Просмотр логов"
    print_info "  docker compose restart pgrokd  # Перезапуск pgrokd"
    print_info "  ./backup.sh              # Создание бэкапа"
    echo ""
    print_warning "Credentials сохранены в: $INSTALL_DIR/credentials.txt"
    
    # Финальная проверка
    print_info "Проверка работающих сервисов:"
    docker compose ps
}

# Запуск
main "$@"