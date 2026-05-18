#!/bin/bash
# =====================================================
# НЕИНТЕРАКТИВНЫЙ СКРИПТ УСТАНОВКИ FORGEJO
# Для локального компьютера с туннелированием через pgrok/pangolin
# Работает на порту 3000, записывает логи установки
# =====================================================

set -e  # Остановить скрипт при любой ошибке

# Файл протокола установки
LOGFILE="/var/log/forgejo_install_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOGFILE") 2>&1

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Функция для вывода шагов
step() {
    echo -e "${GREEN}==>${NC} ${BLUE}$1${NC}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - STEP: $1" >> "$LOGFILE"
}

# Функция для ошибок
error() {
    echo -e "${RED}❌ Ошибка: $1${NC}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1" >> "$LOGFILE"
    exit 1
}

# Функция для предупреждений
warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - WARNING: $1" >> "$LOGFILE"
}

# Проверка прав root
if [ "$EUID" -ne 0 ]; then 
    error "Пожалуйста, запустите скрипт с sudo: sudo $0"
fi

# =====================================================
# 1. ОПРЕДЕЛЕНИЕ ПАРАМЕТРОВ ДЛЯ ТУННЕЛИРОВАНИЯ
# =====================================================
step "Настройка для работы через туннелирование..."

# Запрашиваем домен туннеля (единственный интерактивный момент)
echo -e "${YELLOW}Для работы через туннель необходим внешний домен${NC}"
read -p "Введите домен для доступа к Forgejo (например, git.yourdomain.com): " TUNNEL_DOMAIN

if [ -z "$TUNNEL_DOMAIN" ]; then
    error "Домен не указан. Для работы через туннель необходим внешний домен"
fi

# Определяем локальный IP
LOCAL_IP=$(hostname -I | awk '{print $1}')
if [ -z "$LOCAL_IP" ]; then
    LOCAL_IP="127.0.0.1"
fi

# Автоматическое определение архитектуры
ARCH=$(uname -m)
if [ "$ARCH" == "x86_64" ]; then
    ARCH="amd64"
elif [ "$ARCH" == "aarch64" ]; then
    ARCH="arm64"
else
    ARCH="amd64"
fi

# Версия Forgejo
FORGEJO_VERSION="10.0.3"

echo "$(date '+%Y-%m-%d %H:%M:%S') - Параметры: DOMAIN=$TUNNEL_DOMAIN, LOCAL_IP=$LOCAL_IP, ARCH=$ARCH" >> "$LOGFILE"

echo -e "${GREEN}====================================================================${NC}"
echo "Параметры установки:"
echo "  • Домен туннеля: $TUNNEL_DOMAIN"
echo "  • Локальный IP: $LOCAL_IP"
echo "  • Архитектура: $ARCH"
echo "  • Версия Forgejo: $FORGEJO_VERSION"
echo "  • Порт: 3000 (внутренний)"
echo "  • Режим: подготовка к туннелированию"
echo -e "${GREEN}====================================================================${NC}"
echo ""

# =====================================================
# 2. ОБНОВЛЕНИЕ СИСТЕМЫ И УСТАНОВКА ЗАВИСИМОСТЕЙ
# =====================================================
step "Обновление системы и установка зависимостей..."
apt update >> "$LOGFILE" 2>&1 || error "Не удалось обновить списки пакетов"
apt install -y curl wget git git-lfs nginx >> "$LOGFILE" 2>&1 || warning "Некоторые пакеты не установлены"

echo "$(date '+%Y-%m-%d %H:%M:%S') - Зависимости установлены" >> "$LOGFILE"

# =====================================================
# 3. СОЗДАНИЕ ПОЛЬЗОВАТЕЛЯ git
# =====================================================
step "Создание пользователя git..."
if id "git" &>/dev/null; then
    warning "Пользователь git уже существует"
else
    adduser --system --shell /bin/bash --gecos 'Git Version Control' \
      --group --disabled-password --home /home/git git >> "$LOGFILE" 2>&1 || error "Не удалось создать пользователя git"
fi

# =====================================================
# 4. ЗАГРУЗКА И УСТАНОВКА FORGEJO
# =====================================================
step "Загрузка Forgejo..."
FORGEJO_URL="https://codeberg.org/forgejo/forgejo/releases/download/v${FORGEJO_VERSION}/forgejo-${FORGEJO_VERSION}-linux-${ARCH}"

if [ -f /usr/local/bin/forgejo ]; then
    warning "Forgejo уже установлен, создаю бэкап..."
    cp /usr/local/bin/forgejo /usr/local/bin/forgejo.bak >> "$LOGFILE" 2>&1
fi

wget -O /usr/local/bin/forgejo "$FORGEJO_URL" >> "$LOGFILE" 2>&1 || error "Не удалось загрузить Forgejo"
chmod +x /usr/local/bin/forgejo >> "$LOGFILE" 2>&1

# =====================================================
# 5. СОЗДАНИЕ ДИРЕКТОРИЙ
# =====================================================
step "Создание директорий..."
FORGEJO_HOME="/opt/forgejo"
mkdir -p ${FORGEJO_HOME}/{data,repositories,log,git} >> "$LOGFILE" 2>&1
chown -R git:git ${FORGEJO_HOME} >> "$LOGFILE" 2>&1
chmod 755 ${FORGEJO_HOME} >> "$LOGFILE" 2>&1
chmod 750 ${FORGEJO_HOME}/{data,repositories,log,git} >> "$LOGFILE" 2>&1

mkdir -p /etc/forgejo >> "$LOGFILE" 2>&1
chown root:git /etc/forgejo >> "$LOGFILE" 2>&1
chmod 770 /etc/forgejo >> "$LOGFILE" 2>&1

# =====================================================
# 6. СОЗДАНИЕ КОНФИГУРАЦИИ ДЛЯ ТУННЕЛИРОВАНИЯ
# =====================================================
step "Создание конфигурации для работы через туннель..."
SECRET_KEY=$(openssl rand -base64 24 | head -c 24)

cat > /etc/forgejo/app.ini <<EOF
# =====================================================
# Конфигурация Forgejo для работы через туннель
# ВАЖНО: После настройки туннеля замените PROTOCOL на https
# =====================================================

[server]
# Временно http, после настройки SSL в туннеле поменять на https
PROTOCOL = http
DOMAIN = ${TUNNEL_DOMAIN}
ROOT_URL = http://${TUNNEL_DOMAIN}
HTTP_PORT = 3000
HTTP_ADDR = 127.0.0.1
APP_DATA_PATH = ${FORGEJO_HOME}/data
LFS_CONTENT_PATH = ${FORGEJO_HOME}/data/lfs

# Важные настройки для обратного прокси
SSH_DOMAIN = ${TUNNEL_DOMAIN}
START_SSH_SERVER = false
OFFLINE_MODE = false
LANDING_PAGE = explore

[database]
DB_TYPE = sqlite3
PATH = ${FORGEJO_HOME}/forgejo.db

[repository]
ROOT = ${FORGEJO_HOME}/repositories

[security]
INSTALL_LOCK = true
SECRET_KEY = ${SECRET_KEY}

[log]
MODE = file
LEVEL = Info
ROOT_PATH = ${FORGEJO_HOME}/log

[attachment]
PATH = ${FORGEJO_HOME}/data/attachments
MAX_SIZE = 50
ALLOWED_TYPES = */*

[git]
HOME_PATH = ${FORGEJO_HOME}/git

[ui]
DEFAULT_THEME = auto
THEMES = auto,arc-green

[markdown]
ENABLE_HARD_LINE_BREAK = true

[service]
DISABLE_REGISTRATION = false
REQUIRE_SIGNIN_VIEW = false

[mailer]
ENABLED = false

[picture]
DISABLE_GRAVATAR = false
ENABLE_FEDERATED_AVATAR = false

[openid]
ENABLE_OPENID_SIGNIN = false
ENABLE_OPENID_SIGNUP = false

[cron]
ENABLED = true
EOF

chown git:git /etc/forgejo/app.ini >> "$LOGFILE" 2>&1
chmod 640 /etc/forgejo/app.ini >> "$LOGFILE" 2>&1
echo "$(date '+%Y-%m-%d %H:%M:%S') - Конфигурация создана" >> "$LOGFILE"

# =====================================================
# 7. СОЗДАНИЕ КОНФИГУРАЦИИ NGINX ДЛЯ ТУННЕЛЯ
# =====================================================
step "Настройка Nginx для работы с туннелем..."

cat > /etc/nginx/sites-available/forgejo <<EOF
# Конфигурация для туннелирования через pgrok/pangolin
server {
    listen 80;
    server_name ${TUNNEL_DOMAIN};

    access_log /var/log/nginx/forgejo_access.log;
    error_log /var/log/nginx/forgejo_error.log;

    # Максимальный размер загружаемых файлов
    client_max_body_size 512M;

    location / {
        proxy_pass http://127.0.0.1:3000;
        
        # Стандартные заголовки прокси
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Важные заголовки для Forgejo за прокси
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Server \$host;
        
        # Таймауты для долгих операций
        proxy_connect_timeout 3600;
        proxy_send_timeout 3600;
        proxy_read_timeout 3600;
        
        # Поддержка WebSocket
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Отключаем буферизацию
        proxy_buffering off;
        proxy_request_buffering off;
        
        # Перенаправление ошибок
        proxy_intercept_errors on;
        error_page 502 503 504 /502.html;
    }
    
    # Для работы SSH (если нужно)
    location /ssh/ {
        proxy_pass http://127.0.0.1:2222/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

ln -sf /etc/nginx/sites-available/forgejo /etc/nginx/sites-enabled/ >> "$LOGFILE" 2>&1
rm -f /etc/nginx/sites-enabled/default 2>/dev/null

if nginx -t 2>/dev/null; then
    systemctl restart nginx >> "$LOGFILE" 2>&1
    echo -e "${GREEN}✓ Nginx настроен${NC}"
else
    warning "Проблема с конфигурацией Nginx"
fi

# =====================================================
# 8. СОЗДАНИЕ SYSTEMD СЕРВИСА
# =====================================================
step "Создание systemd сервиса..."
cat > /etc/systemd/system/forgejo.service <<EOF
[Unit]
Description=Forgejo Git Server
After=network.target

[Service]
Type=simple
User=git
Group=git
WorkingDirectory=${FORGEJO_HOME}
ExecStart=/usr/local/bin/forgejo web --config /etc/forgejo/app.ini
Restart=on-failure
RestartSec=5
Environment=HOME=${FORGEJO_HOME}
Environment=USER=git
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# =====================================================
# 9. ЗАПУСК FORGEJO
# =====================================================
step "Запуск Forgejo..."
systemctl daemon-reload >> "$LOGFILE" 2>&1
systemctl enable forgejo >> "$LOGFILE" 2>&1
systemctl start forgejo >> "$LOGFILE" 2>&1

sleep 5

if systemctl is-active --quiet forgejo; then
    echo -e "${GREEN}✓ Forgejo запущена${NC}"
else
    error "Forgejo не запустилась"
fi

# =====================================================
# 10. СОЗДАНИЕ СКРИПТА ДЛЯ ПЕРЕКЛЮЧЕНИЯ НА HTTPS
# =====================================================
step "Создание скрипта для активации HTTPS после настройки туннеля..."

cat > /usr/local/bin/forgejo-enable-https <<'SCRIPT'
#!/bin/bash
# Скрипт для переключения Forgejo на HTTPS после настройки SSL в туннеле

if [ "$EUID" -ne 0 ]; then 
    echo "Запустите с sudo"
    exit 1
fi

echo "Переключение Forgejo на HTTPS..."
echo "Убедитесь, что SSL настроен в вашем туннеле (pgrok/pangolin)"

# Меняем конфигурацию
sed -i 's/PROTOCOL = http/PROTOCOL = https/' /etc/forgejo/app.ini
sed -i 's|ROOT_URL = http://|ROOT_URL = https://|' /etc/forgejo/app.ini

# Перезапускаем сервисы
systemctl restart forgejo
systemctl restart nginx

echo "✓ Forgejo переключен на HTTPS"
echo "Проверьте доступ: https://$(grep DOMAIN /etc/forgejo/app.ini | head -1 | awk '{print $3}')"
SCRIPT

chmod +x /usr/local/bin/forgejo-enable-https

# =====================================================
# 11. СОЗДАНИЕ ИНСТРУКЦИИ ПО НАСТРОЙКЕ ТУННЕЛЯ
# =====================================================
step "Создание инструкции по настройке туннеля..."

cat > /root/forgejo_tunnel_setup.md <<EOF
# Настройка туннеля для Forgejo

## Вариант 1: pgrok
\`\`\`bash
# Установка pgrok
curl -sSL https://pgrok.dev/install.sh | bash

# Запуск туннеля
pgrok http 80 --domain=${TUNNEL_DOMAIN}
\`\`\`

## Вариант 2: Pangolin
\`\`\`bash
# Установка и настройка согласно документации Pangolin
# Пробросить порт 80 на ваш домен ${TUNNEL_DOMAIN}
\`\`\`

## После настройки SSL в туннеле:
\`\`\`bash
sudo forgejo-enable-https
\`\`\`

## Проверка:
1. Forgejo доступен локально: http://localhost:3000
2. Через туннель: http://${TUNNEL_DOMAIN}
3. После SSL: https://${TUNNEL_DOMAIN}
EOF

# =====================================================
# 12. ФИНАЛЬНЫЕ ПРОВЕРКИ
# =====================================================
step "Финальные проверки..."

# Проверяем порты
if ss -tlnp | grep -q ":3000"; then
    echo -e "${GREEN}✓ Порт 3000 слушается${NC}"
else
    warning "Порт 3000 не слушается"
fi

if ss -tlnp | grep -q ":80"; then
    echo -e "${GREEN}✓ Nginx на порту 80 работает${NC}"
else
    warning "Порт 80 не слушается"
fi

# Проверяем локальный доступ
if curl -s http://127.0.0.1:3000 > /dev/null; then
    echo -e "${GREEN}✓ Локальный доступ работает${NC}"
else
    warning "Проблема с локальным доступом"
fi

# =====================================================
# 13. ВЫВОД ИНФОРМАЦИИ
# =====================================================
echo ""
echo -e "${GREEN}====================================================================${NC}"
echo -e "${GREEN}✅ УСТАНОВКА FORGEJO ДЛЯ ТУННЕЛИРОВАНИЯ ЗАВЕРШЕНА!${NC}"
echo -e "${GREEN}====================================================================${NC}"
echo ""
echo -e "${BLUE}🌐 Доступ к Forgejo:${NC}"
echo -e "   • Локальный: ${GREEN}http://localhost:3000${NC}"
echo -e "   • Через Nginx: ${GREEN}http://${LOCAL_IP}${NC}"
echo -e "   • После настройки туннеля: ${GREEN}http://${TUNNEL_DOMAIN}${NC}"
echo ""
echo -e "${YELLOW}📋 Следующие шаги:${NC}"
echo -e "   1. Настройте туннель (pgrok/pangolin) на порт 80"
echo -e "   2. После настройки SSL в туннеле выполните:"
echo -e "      ${GREEN}sudo forgejo-enable-https${NC}"
echo -e "   3. Откройте ${GREEN}http://${TUNNEL_DOMAIN}${NC} и создайте админа"
echo ""
echo -e "${BLUE}🔧 Конфигурация туннеля:${NC}"
echo -e "   • Nginx слушает порт 80 (для туннеля)"
echo -e "   • Forgejo на 127.0.0.1:3000 (только локально)"
echo -e "   • Туннель должен указывать на localhost:80"
echo ""
echo -e "${YELLOW}⚠️  Важно для туннелирования:${NC}"
echo -e "   • HTTP_ADDR = 127.0.0.1 (только локальные подключения)"
echo -e "   • Nginx проксирует запросы с правильными заголовками"
echo -e "   • После SSL выполните forgejo-enable-https"
echo ""
echo -e "${BLUE}📂 Файлы:${NC}"
echo -e "   • Конфигурация: /etc/forgejo/app.ini"
echo -e "   • Инструкция: /root/forgejo_tunnel_setup.md"
echo -e "   • Логи: ${LOGFILE}"
echo ""
echo -e "${GREEN}====================================================================${NC}"