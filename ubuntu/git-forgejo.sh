#!/bin/bash
# wget https://raw.githubusercontent.com/SergeyMi37/vps_install/master/ubuntu/git-forgejo.sh && sudo chmod +x git-forgejo.sh && ./git-forgejo.sh

# Скрипт автоматической установки Forgejo + Nginx + Let's Encrypt (SSL)
# Адаптирован для работы рядом с другими сайтами на том же сервере
# Работоспособность проверена на Ubuntu 20.04/22.04/24.04

set -e  # Остановить скрипт при любой ошибке

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Функция для проверки команды
check_command() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${YELLOW}⚠️  $1 не установлен, будет установлен позже${NC}"
        return 1
    fi
    return 0
}

# Функция проверки существующего домена в Nginx
check_domain_in_nginx() {
    local domain=$1
    if grep -r "server_name.*$domain" /etc/nginx/sites-enabled/ 2>/dev/null | grep -v "forgejo" > /dev/null; then
        echo -e "${RED}❌ Ошибка: Домен $domain уже используется в другом конфиге Nginx!${NC}"
        echo -e "${YELLOW}Найденные конфиги:${NC}"
        grep -r "server_name.*$domain" /etc/nginx/sites-enabled/ 2>/dev/null | grep -v "forgejo"
        echo ""
        echo -e "${YELLOW}Пожалуйста, используйте другой домен или удалите существующую конфигурацию.${NC}"
        exit 1
    fi
}

# Функция проверки SSL сертификата для домена
check_ssl_certificate() {
    local domain=$1
    if [ -d "/etc/letsencrypt/live/$domain" ]; then
        echo -e "${YELLOW}⚠️  SSL сертификат для $domain уже существует!${NC}"
        read -p "Использовать существующий сертификат? (y/n): " use_existing
        if [[ $use_existing == "y" || $use_existing == "Y" ]]; then
            USE_EXISTING_SSL=true
        else
            echo -e "${RED}Установка прервана пользователем.${NC}"
            exit 1
        fi
    else
        USE_EXISTING_SSL=false
    fi
}

# 1. ЗАПРОС ДАННЫХ У ПОЛЬЗОВАТЕЛЯ
echo -e "${GREEN}--------------------------------------------------------------------${NC}"
echo "Добро пожаловать в установщик Forgejo!"
echo -e "${YELLOW}Скрипт настроен для работы рядом с другими сайтами на Nginx${NC}"
echo "--------------------------------------------------------------------"

# Запрос домена
read -p "Введите ваше доменное имя (например, git.example.com): " DOMAIN
if [ -z "$DOMAIN" ]; then
    echo -e "${RED}Ошибка: Домен не может быть пустым.${NC}"
    exit 1
fi

# Проверка, не используется ли домен уже в Nginx
check_domain_in_nginx $DOMAIN

# Запрос email для Let's Encrypt
read -p "Введите ваш email для уведомлений Let's Encrypt: " EMAIL
if [ -z "$EMAIL" ]; then
    echo -e "${RED}Ошибка: Email не может быть пустым.${NC}"
    exit 1
fi

# Проверка существующего SSL сертификата
check_ssl_certificate $DOMAIN

echo "--------------------------------------------------------------------"
echo "Установка будет выполнена для домена: $DOMAIN"
echo "Email для SSL: $EMAIL"
echo "--------------------------------------------------------------------"
read -p "Нажмите Enter, чтобы продолжить, или Ctrl+C для отмены..."

# 2. ОБНОВЛЕНИЕ СИСТЕМЫ И УСТАНОВКА ЗАВИСИМОСТЕЙ
echo -e "${GREEN}==> Обновление списка пакетов и установка зависимостей...${NC}"
sudo apt update
sudo apt install -y curl wget git git-lfs nginx certbot python3-certbot-nginx

# Создаем бэкап существующих конфигов Nginx
echo -e "${GREEN}==> Создание бэкапа конфигурации Nginx...${NC}"
BACKUP_DIR="/etc/nginx/backup_$(date +%Y%m%d_%H%M%S)"
sudo mkdir -p $BACKUP_DIR
sudo cp -r /etc/nginx/sites-available/* $BACKUP_DIR/ 2>/dev/null || true
sudo cp -r /etc/nginx/sites-enabled/* $BACKUP_DIR/ 2>/dev/null || true
echo -e "${GREEN}Бэкап сохранен в $BACKUP_DIR${NC}"

# 3. СОЗДАНИЕ ПОЛЬЗОВАТЕЛЯ git
echo -e "${GREEN}==> Создание системного пользователя 'git'...${NC}"
if id "git" &>/dev/null; then
    echo -e "${YELLOW}Пользователь git уже существует, пропускаем...${NC}"
else
    sudo adduser --system --shell /bin/bash --gecos 'Git Version Control' \
      --group --disabled-password --home /home/git git
fi

# 4. ЗАГРУЗКА И УСТАНОВКА БИНАРНОГО ФАЙЛА FORGEJO
echo -e "${GREEN}==> Загрузка последней стабильной версии Forgejo...${NC}"
# Определяем архитектуру
ARCH=$(uname -m)
if [ "$ARCH" == "x86_64" ]; then
    ARCH="amd64"
elif [ "$ARCH" == "aarch64" ]; then
    ARCH="arm64"
else
    ARCH="amd64" # fallback
fi

# Используем последний стабильный релиз
VERSION="10.0.3"
BINARY_URL="https://codeberg.org/forgejo/forgejo/releases/download/v${VERSION}/forgejo-${VERSION}-linux-${ARCH}"

echo "Загрузка с $BINARY_URL"
sudo wget -O /usr/local/bin/forgejo $BINARY_URL
sudo chmod +x /usr/local/bin/forgejo

# 5. СОЗДАНИЕ ДИРЕКТОРИЙ
echo -e "${GREEN}==> Создание директорий для данных и конфигурации...${NC}"
sudo mkdir -p /var/lib/forgejo /etc/forgejo
sudo chown -R git:git /var/lib/forgejo
sudo chmod 750 /var/lib/forgejo
sudo chown -R root:git /etc/forgejo
sudo chmod 770 /etc/forgejo

# 6. СОЗДАНИЕ SERVICE (SYSTEMD)
echo -e "${GREEN}==> Создание systemd сервиса...${NC}"
sudo tee /etc/systemd/system/forgejo.service > /dev/null <<EOF
[Unit]
Description=Forgejo Git Server
After=network.target

[Service]
Type=simple
User=git
Group=git
WorkingDirectory=/var/lib/forgejo
ExecStart=/usr/local/bin/forgejo web --config /etc/forgejo/app.ini
Restart=always
Environment=USER=git HOME=/home/git

[Install]
WantedBy=multi-user.target
EOF

# 7. БАЗОВАЯ КОНФИГУРАЦИЯ
echo -e "${GREEN}==> Создание базового конфига app.ini...${NC}"
sudo tee /etc/forgejo/app.ini > /dev/null <<EOF
[server]
PROTOCOL     = http
DOMAIN       = $DOMAIN
ROOT_URL     = http://$DOMAIN
HTTP_PORT    = 3000
HTTP_ADDR    = 0.0.0.0
LANDING_PAGE = /explore
APP_DATA_PATH = /var/lib/forgejo/data

[database]
DB_TYPE  = sqlite3
PATH     = /var/lib/forgejo/forgejo.db

[repository]
ROOT = /var/lib/forgejo/repositories

[security]
INSTALL_LOCK = true
SECRET_KEY = $(openssl rand -base64 24)

[log]
MODE = file
LEVEL = Info
ROOT_PATH = /var/lib/forgejo/log
EOF

# Выдаем права
sudo chown git:git /etc/forgejo/app.ini
sudo chmod 640 /etc/forgejo/app.ini

# 8. ЗАПУСК FORGEJO
echo -e "${GREEN}==> Запуск Forgejo...${NC}"
sudo systemctl daemon-reload
sudo systemctl enable forgejo
sudo systemctl start forgejo

# 9. КОНФИГУРАЦИЯ NGINX (добавляем только наш location)
echo -e "${GREEN}==> Настройка Nginx (добавление конфига для $DOMAIN)...${NC}"

# Создаем отдельный файл конфига для Forgejo
sudo tee /etc/nginx/sites-available/forgejo > /dev/null <<EOF
# Forgejo configuration for $DOMAIN
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    # Логи только для этого домена
    access_log /var/log/nginx/forgejo_access.log;
    error_log /var/log/nginx/forgejo_error.log;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Увеличиваем таймауты для больших репозиториев
        proxy_connect_timeout 3600;
        proxy_send_timeout 3600;
        proxy_read_timeout 3600;
        
        # Увеличиваем максимальный размер тела запроса (для больших файлов)
        client_max_body_size 512M;
    }
}
EOF

# Активируем сайт, если он еще не активирован
if [ ! -f /etc/nginx/sites-enabled/forgejo ]; then
    sudo ln -s /etc/nginx/sites-available/forgejo /etc/nginx/sites-enabled/
fi

# Проверяем конфигурацию Nginx
echo -e "${GREEN}==> Проверка конфигурации Nginx...${NC}"
if sudo nginx -t; then
    echo -e "${GREEN}✓ Конфигурация Nginx корректна${NC}"
    sudo systemctl reload nginx
else
    echo -e "${RED}✗ Ошибка в конфигурации Nginx!${NC}"
    echo -e "${YELLOW}Восстанавливаем бэкап...${NC}"
    sudo cp $BACKUP_DIR/* /etc/nginx/sites-available/ 2>/dev/null || true
    sudo systemctl reload nginx
    exit 1
fi

# 10. ПОЛУЧЕНИЕ SSL СЕРТИФИКАТА (LET'S ENCRYPT)
if [ "$USE_EXISTING_SSL" = true ]; then
    echo -e "${GREEN}==> Используем существующий SSL сертификат для $DOMAIN...${NC}"
    
    # Обновляем конфиг Nginx для использования HTTPS с существующим сертификатом
    sudo tee -a /etc/nginx/sites-available/forgejo > /dev/null <<EOF

# HTTPS конфигурация с существующим сертификатом
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    
    access_log /var/log/nginx/forgejo_access_ssl.log;
    error_log /var/log/nginx/forgejo_error_ssl.log;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        proxy_connect_timeout 3600;
        proxy_send_timeout 3600;
        proxy_read_timeout 3600;
        client_max_body_size 512M;
    }
}

# Редирект с HTTP на HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    return 301 https://\$server_name\$request_uri;
}
EOF

else
    echo -e "${GREEN}==> Получение SSL сертификата от Let's Encrypt...${NC}"
    
    # Временно останавливаем nginx для certbot в режиме standalone (если порт 80 занят другими сайтами)
    # Используем webroot метод, который не мешает другим сайтам
    sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email $EMAIL --redirect
    
    # Certbot сам добавит HTTPS секцию в наш конфиг и настроит редирект
fi

# 11. ОБНОВЛЕНИЕ КОНФИГА FORGEJO НА HTTPS
echo -e "${GREEN}==> Обновление конфигурации Forgejo для работы через HTTPS...${NC}"
sudo sed -i "s|ROOT_URL = http://$DOMAIN|ROOT_URL = https://$DOMAIN|" /etc/forgejo/app.ini
sudo sed -i "s|PROTOCOL     = http|PROTOCOL     = https|" /etc/forgejo/app.ini

# 12. ПЕРЕЗАПУСК
echo -e "${GREEN}==> Перезапуск сервисов...${NC}"
sudo systemctl restart forgejo
sudo systemctl reload nginx

# 13. ФИНАЛЬНЫЕ ШАГИ
echo -e "${GREEN}--------------------------------------------------------------------${NC}"
echo -e "${GREEN}✅ Установка успешно завершена!${NC}"
echo -e "Перейдите по адресу: ${GREEN}https://$DOMAIN${NC}"
echo "--------------------------------------------------------------------"
echo -e "${YELLOW}📝 Важная информация:${NC}"
echo "1. Первый зарегистрированный пользователь автоматически станет администратором."
echo "2. Конфигурация Forgejo: /etc/forgejo/app.ini"
echo "3. Данные репозиториев: /var/lib/forgejo/repositories"
echo "4. Бэкап Nginx сохранен в: $BACKUP_DIR"
echo "5. Если у вас есть другие сайты, их конфигурация не пострадала"
echo "--------------------------------------------------------------------"

# Проверяем, что Forgejo действительно запустилась
sleep 5
if curl -s http://127.0.0.1:3000 > /dev/null; then
    echo -e "${GREEN}✅ Forgejo успешно запущена на порту 3000${NC}"
else
    echo -e "${RED}⚠️  Внимание: Forgejo не отвечает на порту 3000${NC}"
    echo -e "${YELLOW}Проверьте логи: sudo journalctl -u forgejo -n 50${NC}"
fi

# Проверяем статус Nginx
if systemctl is-active --quiet nginx; then
    echo -e "${GREEN}✅ Nginx работает и обслуживает все сайты${NC}"
else
    echo -e "${RED}⚠️  Проблема с Nginx!${NC}"
fi