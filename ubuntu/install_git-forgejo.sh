#!/bin/bash
# wget https://raw.githubusercontent.com/SergeyMi37/vps_install/master/ubuntu/install_git-forgejo.sh && sudo chmod +x git-forgejo.sh && ./git-forgejo.sh
# =====================================================
# FINAL SCRIPT - Forgejo Installation with all fixes
# Исправлены все ошибки:
# - Permission denied for /usr/local/bin/data
# - HTTP_ADDR binding to 127.0.0.1
# - AppDataPath configuration
# - Systemd service setup
# - Firewall configuration
# =====================================================

set -e  # Остановить скрипт при любой ошибке

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Функция для вывода шагов
step() {
    echo -e "${GREEN}==>${NC} ${BLUE}$1${NC}"
}

# Функция для ошибок
error() {
    echo -e "${RED}❌ Ошибка: $1${NC}"
    exit 1
}

# Функция для предупреждений
warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Проверка прав root
if [ "$EUID" -ne 0 ]; then 
    error "Пожалуйста, запустите скрипт с sudo: sudo $0"
fi

clear
echo -e "${GREEN}====================================================================${NC}"
echo -e "${GREEN}     Forgejo Installation Script - Production Ready${NC}"
echo -e "${GREEN}====================================================================${NC}"
echo ""

# Запрос данных
read -p "Введите домен или IP-адрес сервера (например, git.example.com или 193.247.77.73): " SERVER_ADDR
if [ -z "$SERVER_ADDR" ]; then
    SERVER_ADDR=$(curl -s ifconfig.me)
    warning "Адрес не введен, использую публичный IP: $SERVER_ADDR"
fi

read -p "Введите email для SSL сертификата (оставьте пустым, если не нужен HTTPS): " EMAIL

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

echo ""
echo -e "${GREEN}====================================================================${NC}"
echo "Параметры установки:"
echo "  • Адрес сервера: $SERVER_ADDR"
echo "  • Архитектура: $ARCH"
echo "  • Версия Forgejo: $FORGEJO_VERSION"
echo "  • Путь установки: /opt/forgejo"
echo -e "${GREEN}====================================================================${NC}"
echo ""
read -p "Нажмите Enter для продолжения или Ctrl+C для отмены..."

# =====================================================
# 1. ОБНОВЛЕНИЕ СИСТЕМЫ И УСТАНОВКА ЗАВИСИМОСТЕЙ
# =====================================================
step "Обновление системы и установка зависимостей..."
apt update
apt install -y curl wget git git-lfs nginx certbot python3-certbot-nginx ufw

# =====================================================
# 2. СОЗДАНИЕ ПОЛЬЗОВАТЕЛЯ git
# =====================================================
step "Создание пользователя git..."
if id "git" &>/dev/null; then
    warning "Пользователь git уже существует"
else
    adduser --system --shell /bin/bash --gecos 'Git Version Control' \
      --group --disabled-password --home /home/git git
fi

# =====================================================
# 3. ЗАГРУЗКА И УСТАНОВКА FORGEJO
# =====================================================
step "Загрузка Forgejo..."
FORGEJO_URL="https://codeberg.org/forgejo/forgejo/releases/download/v${FORGEJO_VERSION}/forgejo-${FORGEJO_VERSION}-linux-${ARCH}"

if [ -f /usr/local/bin/forgejo ]; then
    warning "Forgejo уже установлен, создаю бэкап..."
    cp /usr/local/bin/forgejo /usr/local/bin/forgejo.bak
fi

wget -O /usr/local/bin/forgejo "$FORGEJO_URL" || error "Не удалось загрузить Forgejo"
chmod +x /usr/local/bin/forgejo

# =====================================================
# 4. СОЗДАНИЕ ДИРЕКТОРИЙ (КЛЮЧЕВОЕ ИСПРАВЛЕНИЕ!)
# =====================================================
step "Создание директорий с правильными правами..."
# Используем /opt/forgejo вместо /var/lib/forgejo для избежания проблем
FORGEJO_HOME="/opt/forgejo"
mkdir -p ${FORGEJO_HOME}/{data,repositories,log,git}
chown -R git:git ${FORGEJO_HOME}
chmod 755 ${FORGEJO_HOME}
chmod 750 ${FORGEJO_HOME}/{data,repositories,log,git}

mkdir -p /etc/forgejo
chown root:git /etc/forgejo
chmod 770 /etc/forgejo

# =====================================================
# 5. СОЗДАНИЕ КОНФИГУРАЦИИ (С ПРАВИЛЬНЫМИ ПАРАМЕТРАМИ)
# =====================================================
step "Создание конфигурационного файла..."
SECRET_KEY=$(openssl rand -base64 24 | head -c 24)

cat > /etc/forgejo/app.ini <<EOF
[server]
PROTOCOL = http
DOMAIN = ${SERVER_ADDR}
ROOT_URL = http://${SERVER_ADDR}:3000
HTTP_PORT = 3000
HTTP_ADDR = 0.0.0.0
APP_DATA_PATH = ${FORGEJO_HOME}/data
LFS_CONTENT_PATH = ${FORGEJO_HOME}/data/lfs

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
EOF

# Даем правильные права на конфиг
chown git:git /etc/forgejo/app.ini
chmod 640 /etc/forgejo/app.ini

# =====================================================
# 6. ПРОВЕРКА КОНФИГУРАЦИИ
# =====================================================
step "Проверка конфигурации..."
if sudo -u git /usr/local/bin/forgejo web --config /etc/forgejo/app.ini --test 2>/dev/null; then
    echo -e "${GREEN}✓ Конфигурация корректна${NC}"
else
    warning "Проверка конфигурации выдала предупреждение, но продолжаем..."
fi

# =====================================================
# 7. СОЗДАНИЕ SYSTEMD СЕРВИСА
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
# 8. ЗАПУСК FORGEJO
# =====================================================
step "Запуск Forgejo..."
systemctl daemon-reload
systemctl enable forgejo
systemctl start forgejo

sleep 5

# Проверяем статус
if systemctl is-active --quiet forgejo; then
    echo -e "${GREEN}✓ Forgejo успешно запущена${NC}"
else
    error "Forgejo не запустилась. Логи:"
    journalctl -u forgejo -n 20 --no-pager
fi

# =====================================================
# 9. НАСТРОЙКА БРАНДМАУЭРА
# =====================================================
step "Настройка брандмауэра..."
# Открываем порты
ufw allow 22/tcp comment 'SSH'
ufw allow 80/tcp comment 'HTTP'
ufw allow 3000/tcp comment 'Forgejo'
echo "y" | ufw enable 2>/dev/null || true
ufw reload

# =====================================================
# 10. НАСТРОЙКА NGINX (ОПЦИОНАЛЬНО)
# =====================================================
step "Настройка Nginx..."

# Создаем конфиг Nginx
cat > /etc/nginx/sites-available/forgejo <<EOF
server {
    listen 80;
    server_name ${SERVER_ADDR};

    access_log /var/log/nginx/forgejo_access.log;
    error_log /var/log/nginx/forgejo_error.log;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Увеличиваем лимиты для больших файлов
        client_max_body_size 512M;
        
        # Таймауты для долгих операций
        proxy_connect_timeout 3600;
        proxy_send_timeout 3600;
        proxy_read_timeout 3600;
        
        # Отключаем буферизацию для WebSocket
        proxy_buffering off;
        proxy_request_buffering off;
    }
}
EOF

# Активируем сайт
ln -sf /etc/nginx/sites-available/forgejo /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default 2>/dev/null

# Проверяем и перезапускаем Nginx
if nginx -t 2>/dev/null; then
    systemctl restart nginx
    echo -e "${GREEN}✓ Nginx настроен и работает${NC}"
else
    warning "Проблема с конфигурацией Nginx, но Forgejo работает на порту 3000"
fi

# =====================================================
# 11. НАСТРОЙКА HTTPS (ЕСЛИ УКАЗАН EMAIL)
# =====================================================
if [ -n "$EMAIL" ] && [[ "$SERVER_ADDR" =~ \.[a-z]{2,}$ ]]; then
    step "Настройка HTTPS через Let's Encrypt..."
    
    # Получаем сертификат
    certbot --nginx -d ${SERVER_ADDR} --non-interactive --agree-tos --email ${EMAIL} --redirect 2>/dev/null || {
        warning "Не удалось получить SSL сертификат. Проверьте, что домен направлен на этот сервер"
    }
    
    # Обновляем конфиг Forgejo для HTTPS
    if [ -f "/etc/letsencrypt/live/${SERVER_ADDR}/fullchain.pem" ]; then
        sed -i 's/PROTOCOL = http/PROTOCOL = https/' /etc/forgejo/app.ini
        sed -i "s|ROOT_URL = http://${SERVER_ADDR}:3000|ROOT_URL = https://${SERVER_ADDR}|" /etc/forgejo/app.ini
        systemctl restart forgejo
        echo -e "${GREEN}✓ HTTPS настроен: https://${SERVER_ADDR}${NC}"
    fi
fi

# =====================================================
# 12. ФИНАЛЬНЫЕ ПРОВЕРКИ
# =====================================================
step "Финальные проверки..."

# Проверяем, что порт слушается
if ss -tlnp | grep -q ":3000"; then
    echo -e "${GREEN}✓ Порт 3000 слушается${NC}"
else
    warning "Порт 3000 не слушается"
fi

# Проверяем локальный доступ
if curl -s http://127.0.0.1:3000 > /dev/null; then
    echo -e "${GREEN}✓ Локальный доступ работает${NC}"
else
    warning "Проблема с локальным доступом"
fi

# Получаем публичный IP если не указан
if [ "$SERVER_ADDR" = "$(curl -s ifconfig.me)" ] || [ "$SERVER_ADDR" = "$(hostname -I | awk '{print $1}')" ]; then
    PUBLIC_URL="http://${SERVER_ADDR}:3000"
else
    PUBLIC_URL="http://${SERVER_ADDR}:3000"
fi

# =====================================================
# 13. ВЫВОД ИНФОРМАЦИИ
# =====================================================
echo ""
echo -e "${GREEN}====================================================================${NC}"
echo -e "${GREEN}✅ УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!${NC}"
echo -e "${GREEN}====================================================================${NC}"
echo ""
echo -e "${BLUE}🌐 Доступ к Forgejo:${NC}"
echo -e "   ${GREEN}${PUBLIC_URL}${NC}"
echo -e "   (или http://${SERVER_ADDR}:3000)"
echo ""
echo -e "${BLUE}📝 Данные для входа:${NC}"
echo -e "   Первый зарегистрированный пользователь становится АДМИНИСТРАТОРОМ"
echo ""
echo -e "${BLUE}📂 Важные пути:${NC}"
echo -e "   • Конфигурация: /etc/forgejo/app.ini"
echo -e "   • Данные: ${FORGEJO_HOME}/"
echo -e "   • Репозитории: ${FORGEJO_HOME}/repositories"
echo -e "   • Логи: journalctl -u forgejo -f"
echo ""
echo -e "${BLUE}🛠 Полезные команды:${NC}"
echo -e "   • Статус: sudo systemctl status forgejo"
echo -e "   • Логи: sudo journalctl -u forgejo -f"
echo -e "   • Перезапуск: sudo systemctl restart forgejo"
echo -e "   • Остановка: sudo systemctl stop forgejo"
echo ""
echo -e "${BLUE}🔒 Безопасность:${NC}"
echo -e "   • Порт 3000 открыт для прямого доступа"
echo -e "   • Nginx настроен на порту 80 (и 443 если есть SSL)"
echo ""
echo -e "${YELLOW}⚠️  Важно:${NC}"
echo -e "   1. Сразу после входа смените пароль администратора"
echo -e "   2. Настройте SSH-ключи для удобной работы"
echo -e "   3. Регулярно делайте бэкапы: ${FORGEJO_HOME}/"
echo ""
echo -e "${GREEN}====================================================================${NC}"
echo -e "${GREEN}🎉 Поздравляем! Ваш Git-сервер готов к работе!${NC}"
echo -e "${GREEN}====================================================================${NC}"