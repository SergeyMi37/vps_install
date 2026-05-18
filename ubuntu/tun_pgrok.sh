#!/bin/bash

# =============================================================================
# Автоматическая установка сервера Pgrok (pgrokd) на VPS с Ubuntu 20.04/22.04
# Домен: pgrok.my.site
# Дата: $(date '+%Y-%m-%d')
# =============================================================================

set -e  # Прерывать выполнение при любой ошибке
set -u  # Прерывать при использовании неопределенных переменных

# -------------------- НАСТРАИВАЕМЫЕ ПАРАМЕТРЫ ---------------------------------
DOMAIN="pgrok.my.site"
PGROK_VERSION="v1.5.0"  # последняя стабильная версия на момент написания
POSTGRES_PASSWORD="$(openssl rand -base64 24)"
PGROK_ADMIN_PASSWORD="$(openssl rand -base64 16)"
SECRET_KEY="$(openssl rand -base64 32)"

# -------------------- ПЕРЕМЕННЫЕ И ФАЙЛЫ ЛОГОВ -------------------------------
LOG_FILE="/var/log/pgrok_installation.log"
CLIENT_INSTRUCTIONS_FILE="/var/log/pgrok_client_instructions.txt"
PROTOCOL_FILE="/var/log/pgrok_installation_protocol.txt"

# Определяем цветной вывод (только для интерактивных сессий, в лог пишем без цветов)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; NC=''
fi

# Функция для логирования с временной меткой
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} - $1" | tee -a "$LOG_FILE"
    echo -e "${timestamp} - $1" >> "$PROTOCOL_FILE"
}

# Функция для вывода на экран и в лог
print_status() {
    echo -e "${GREEN}==>${NC} $1" | tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$PROTOCOL_FILE"
}

print_error() {
    echo -e "${RED}ERROR:${NC} $1" | tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1" >> "$PROTOCOL_FILE"
}

print_warning() {
    echo -e "${YELLOW}WARNING:${NC} $1" | tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - WARNING: $1" >> "$PROTOCOL_FILE"
}

# -------------------- НАЧАЛО УСТАНОВКИ ----------------------------------------
clear
print_status "Начало автоматической установки Pgrok сервера для домена $DOMAIN"
print_status "Время начала: $(date)"

# Создаем заголовок протокола
cat > "$PROTOCOL_FILE" << EOF
================================================================================
ПРОТОКОЛ УСТАНОВКИ Pgrok СЕРВЕРА
================================================================================
Домен: $DOMAIN
Время установки: $(date)
Скрипт запущен: $(whoami)@$(hostname)
Версия Pgrok: $PGROK_VERSION

================================================================================
ХОД УСТАНОВКИ
================================================================================
EOF

# -------------------- ПРОВЕРКА ПРАВ СУПЕРПОЛЬЗОВАТЕЛЯ ------------------------
if [[ $EUID -ne 0 ]]; then
    print_error "Этот скрипт должен запускаться с правами root (sudo)"
    exit 1
fi

# -------------------- ПРОВЕРКА ОС -------------------------------------------------
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
    print_status "Обнаружена ОС: $OS $VER"
else
    print_error "Не удалось определить ОС"
    exit 1
fi

# Поддерживаем только Ubuntu
if [[ "$OS" != "ubuntu" ]]; then
    print_error "Скрипт поддерживает только Ubuntu. Обнаружено: $OS"
    exit 1
fi

# -------------------- ПРОВЕРКА DNS ЗАПИСЕЙ (предупреждение) --------------------
print_status "Проверка DNS записей для домена $DOMAIN..."
if command -v dig &> /dev/null; then
    SERVER_IP=$(curl -s ifconfig.me)
    DOMAIN_IP=$(dig +short $DOMAIN @8.8.8.8 | head -1)
    WILDCARD_IP=$(dig +short *.$DOMAIN @8.8.8.8 | head -1)
    
    if [[ "$DOMAIN_IP" != "$SERVER_IP" ]]; then
        print_warning "A-запись для $DOMAIN ($DOMAIN_IP) не соответствует IP сервера ($SERVER_IP)"
        print_warning "Пожалуйста, создайте A-запись для $DOMAIN, указывающую на $SERVER_IP"
    fi
    
    if [[ -z "$WILDCARD_IP" ]]; then
        print_warning "Wildcard A-запись для *.$DOMAIN не найдена"
        print_warning "Пожалуйста, создайте A-запись для *.$DOMAIN, указывающую на $SERVER_IP"
    fi
else
    print_warning "dig не установлен, пропускаем проверку DNS"
fi

# -------------------- ОБНОВЛЕНИЕ СИСТЕМЫ ---------------------------------------
print_status "Обновление списка пакетов..."
apt-get update -qq >> "$LOG_FILE" 2>&1

print_status "Установка необходимых зависимостей..."
apt-get install -y -qq wget curl gnupg2 software-properties-common \
    apt-transport-https ca-certificates lsb-release debian-archive-keyring \
    postgresql postgresql-contrib caddy jq ufw openssl >> "$LOG_FILE" 2>&1

# -------------------- НАСТРОЙКА FIREWALL ---------------------------------------
print_status "Настройка firewall (UFW)..."
ufw --force disable >> "$LOG_FILE" 2>&1 || true
ufw default deny incoming >> "$LOG_FILE" 2>&1
ufw default allow outgoing >> "$LOG_FILE" 2>&1
ufw allow 22/tcp comment 'SSH' >> "$LOG_FILE" 2>&1
ufw allow 80/tcp comment 'HTTP' >> "$LOG_FILE" 2>&1
ufw allow 443/tcp comment 'HTTPS' >> "$LOG_FILE" 2>&1
ufw allow 2222/tcp comment 'Pgrok Tunnel' >> "$LOG_FILE" 2>&1
ufw --force enable >> "$LOG_FILE" 2>&1
print_status "Firewall настроен: открыты порты 22, 80, 443, 2222"

# -------------------- УСТАНОВКА DOCKER (опционально для Pgrok) ----------------
print_status "Установка Docker и Docker Compose..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -qq >> "$LOG_FILE" 2>&1
apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin >> "$LOG_FILE" 2>&1
systemctl enable docker >> "$LOG_FILE" 2>&1
systemctl start docker

# -------------------- НАСТРОЙКА POSTGRESQL ------------------------------------
print_status "Настройка PostgreSQL..."
systemctl enable postgresql >> "$LOG_FILE" 2>&1
systemctl start postgresql

# Создаем базу данных и пользователя для Pgrok
sudo -u postgres psql -c "CREATE USER pgrok WITH PASSWORD '$POSTGRES_PASSWORD';" >> "$LOG_FILE" 2>&1
sudo -u postgres psql -c "CREATE DATABASE pgrokd OWNER pgrok;" >> "$LOG_FILE" 2>&1
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE pgrokd TO pgrok;" >> "$LOG_FILE" 2>&1

print_status "База данных PostgreSQL создана (пользователь: pgrok)"

# -------------------- СОЗДАНИЕ ДИРЕКТОРИЙ -------------------------------------
mkdir -p /opt/pgrok /var/lib/pgrok/data
chmod 755 /opt/pgrok /var/lib/pgrok/data

# -------------------- КОНФИГУРАЦИЯ PGROKD (YML) --------------------------------
print_status "Создание конфигурации Pgrokd..."

# Создаем временный файл конфигурации
cat > /opt/pgrok/pgrokd.yml << EOF
external_url: "https://$DOMAIN"

web:
  port: 3320

proxy:
  port: 3000
  scheme: "https"
  domain: "$DOMAIN"

sshd:
  port: 2222

database:
  host: "localhost"
  port: 5432
  user: "pgrok"
  password: "$POSTGRES_PASSWORD"
  database: "pgrokd"

identity_provider:
  type: "oidc"
  display_name: "Google"
  issuer: "https://accounts.google.com"
  client_id: "ВАШ_GOOGLE_CLIENT_ID"
  client_secret: "ВАШ_GOOGLE_CLIENT_SECRET"
  field_mapping:
    identifier: "email"
    display_name: "name"
    email: "email"
  # required_domain: "your-company.com"  # Раскомментируйте для ограничения доменов

# Секретный ключ для подписи JWT
secret_key: "$SECRET_KEY"
EOF

print_status "Конфигурация сохранена в /opt/pgrok/pgrokd.yml"
print_warning "ОБЯЗАТЕЛЬНО: Замените client_id и client_secret в конфигурации на реальные значения из Google Cloud Console"

# -------------------- ЗАГРУЗКА И ЗАПУСК PGROKD В DOCKER -----------------------
print_status "Загрузка и запуск Pgrokd в Docker контейнере..."

# Создаем docker-compose.yml
cat > /opt/pgrok/docker-compose.yml << EOF
version: "3.8"

services:
  pgrokd:
    image: jerson/pgrok:latest
    container_name: pgrokd
    entrypoint: pgrokd
    command: server --config /config/pgrokd.yml
    restart: unless-stopped
    volumes:
      - /opt/pgrok/pgrokd.yml:/config/pgrokd.yml:ro
      - /var/lib/pgrok/data:/data
    ports:
      - "2222:2222"
      - "3000:3000"
      - "3320:3320"
    networks:
      - pgrok_network

networks:
  pgrok_network:
    driver: bridge
EOF

cd /opt/pgrok
docker-compose pull -q >> "$LOG_FILE" 2>&1
docker-compose up -d >> "$LOG_FILE" 2>&1

sleep 5
if docker ps | grep -q pgrokd; then
    print_status "Pgrokd Docker контейнер успешно запущен"
else
    print_error "Не удалось запустить Pgrokd контейнер"
    docker logs pgrokd --tail 20 >> "$LOG_FILE" 2>&1
    exit 1
fi

# -------------------- НАСТРОЙКА CADDY (REVERSE PROXY) -------------------------
print_status "Настройка Caddy как reverse proxy..."

cat > /etc/caddy/Caddyfile << EOF
# Основной домен - веб-интерфейс Pgrok
https://$DOMAIN {
    reverse_proxy localhost:3320
}

# Wildcard домен - туннели пользователей
https://*.$DOMAIN {
    reverse_proxy localhost:3000
}
EOF

systemctl restart caddy >> "$LOG_FILE" 2>&1
systemctl enable caddy >> "$LOG_FILE" 2>&1

if systemctl is-active --quiet caddy; then
    print_status "Caddy успешно настроен и запущен"
else
    print_error "Caddy не запустился. Проверьте конфигурацию"
    journalctl -u caddy -n 20 --no-pager >> "$LOG_FILE" 2>&1
fi

# -------------------- НАСТРОЙКА АВТОЗАПУСКА И АВТООБНОВЛЕНИЙ -----------------
print_status "Настройка автоматического обновления Docker контейнеров..."

# Добавляем watchtower для автообновления
docker run -d \
    --name watchtower \
    --restart unless-stopped \
    -v /var/run/docker.sock:/var/run/docker.sock \
    containrrr/watchtower:latest \
    --cleanup --interval 86400 >> "$LOG_FILE" 2>&1

print_status "Watchtower настроен для ежедневного обновления контейнеров"

# -------------------- ПРОВЕРКА РАБОТОСПОСОБНОСТИ -----------------------------
print_status "Проверка работы сервисов..."

# Проверяем доступность веб-интерфейса
sleep 3
if curl -s -o /dev/null -w "%{http_code}" http://localhost:3320 | grep -q "200\|302\|401"; then
    print_status "Веб-интерфейс Pgrok доступен на порту 3320"
else
    print_warning "Веб-интерфейс не отвечает, проверьте логи: docker logs pgrokd"
fi

# -------------------- СОЗДАНИЕ ИНСТРУКЦИЙ ДЛЯ КЛИЕНТОВ ------------------------
print_status "Создание инструкций для клиентских компьютеров..."

cat > "$CLIENT_INSTRUCTIONS_FILE" << 'EOF'
================================================================================
                    ИНСТРУКЦИИ ПО УСТАНОВКЕ Pgrok КЛИЕНТА
================================================================================

Сервер Pgrok доступен по адресу: https://pgrok.my.site
Порт для туннелей: 2222

Перед началом работы:
1. Откройте https://pgrok.my.site в браузере
2. Авторизуйтесь через Google (OIDC)
3. После входа вы получите:
   - Токен (например: eyJhbGciOiJIUzI1NiIs...)
   - Ваш персональный URL (например: https://username.pgrok.my.site)

================================================================================
1. УСТАНОВКА НА WINDOWS
================================================================================

Способ A (Рекомендуемый) - Скачивание бинарного файла:
------------------------------------------------------
1. Скачайте последнюю версию pgrok.exe для Windows:
   https://github.com/jerson/pgrok/releases/latest
   (ищите файл *windows_amd64.zip или *windows_386.zip)

2. Распакуйте архив в папку, например: C:\pgrok\

3. Откройте командную строку (cmd) или PowerShell от имени администратора

4. Перейдите в папку с pgrok.exe:
   cd C:\pgrok

5. Инициализируйте конфигурацию (ЗАМЕНИТЕ {ВАШ_ТОКЕН} на полученный):
   pgrok.exe init --remote-addr pgrok.my.site:2222 --forward-addr http://localhost:3000 --token {ВАШ_ТОКЕН}

6. Запустите туннель:
   pgrok.exe http 3000

   (где 3000 - порт вашего локального сервера, например, для разработки)

7. Ваш локальный сервер станет доступен по адресу:
   https://username.pgrok.my.site

Способ B - Через WSL (Windows Subsystem for Linux):
----------------------------------------------------
Если у вас установлен WSL2, выполните команды внутри Ubuntu/WSL:
   brew install jerson/tap/pgrok
   pgrok init --remote-addr pgrok.my.site:2222 --forward-addr http://localhost:3000 --token {ВАШ_ТОКЕН}
   pgrok http 3000

Создание автозагрузки (Windows):
--------------------------------
1. Создайте файл pgrok-service.xml в папке C:\pgrok\ со следующим содержанием:

<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers>
    <BootTrigger>
      <Enabled>true</Enabled>
    </BootTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>true</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>true</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions>
    <Exec>
      <Command>C:\pgrok\pgrok.exe</Command>
      <Arguments>http 3000</Arguments>
      <WorkingDirectory>C:\pgrok\</WorkingDirectory>
    </Exec>
  </Actions>
</Task>

2. Импортируйте задачу в Планировщик заданий:
   schtasks /create /xml "C:\pgrok\pgrok-service.xml" /tn "PgrokTunnel"

================================================================================
2. УСТАНОВКА НА UBUNTU / DEBIAN / LINUX MINT
================================================================================

Способ A - Через пакетный менеджер (Рекомендуется):
---------------------------------------------------
# Добавление репозитория Homebrew (или используйте бинарный файл)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Установка pgrok
brew install jerson/tap/pgrok

# Инициализация конфигурации (ЗАМЕНИТЕ {ВАШ_ТОКЕН})
pgrok init --remote-addr pgrok.my.site:2222 --forward-addr http://localhost:3000 --token {ВАШ_ТОКЕН}

# Запуск туннеля
pgrok http 3000

Способ B - Скачивание бинарного файла:
--------------------------------------
# Скачайте последнюю версию
wget https://github.com/jerson/pgrok/releases/latest/download/pgrok-linux-amd64 -O /usr/local/bin/pgrok
chmod +x /usr/local/bin/pgrok

# Инициализация
pgrok init --remote-addr pgrok.my.site:2222 --forward-addr http://localhost:3000 --token {ВАШ_ТОКЕН}

# Запуск
pgrok http 3000

Создание systemd сервиса (для автозапуска):
-------------------------------------------
Создайте файл /etc/systemd/system/pgrok.service:

[Unit]
Description=Pgrok Tunnel
After=network.target

[Service]
Type=simple
User=%i
ExecStart=/usr/local/bin/pgrok http 3000
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target

Активируйте сервис:
sudo systemctl enable pgrok.service
sudo systemctl start pgrok.service

================================================================================
3. УСТАНОВКА НА ALMALINUX / RHEL / ROCKY LINUX / CENTOS
================================================================================

Способ A - Скачивание бинарного файла (Рекомендуется):
------------------------------------------------------
# Установка зависимостей
sudo dnf install -y wget

# Скачивание бинарного файла
sudo wget https://github.com/jerson/pgrok/releases/latest/download/pgrok-linux-amd64 -O /usr/local/bin/pgrok
sudo chmod +x /usr/local/bin/pgrok

# Инициализация (ЗАМЕНИТЕ {ВАШ_ТОКЕН})
pgrok init --remote-addr pgrok.my.site:2222 --forward-addr http://localhost:3000 --token {ВАШ_ТОКЕН}

# Запуск
pgrok http 3000

Способ B - Сборка из исходников (требуется Go):
------------------------------------------------
# Установка Golang
sudo dnf install -y golang git

# Клонирование и сборка
git clone https://github.com/jerson/pgrok.git
cd pgrok
make build

# Копирование бинарного файла
sudo cp bin/pgrok /usr/local/bin/

# Далее как в способе A

Создание systemd сервиса (AlmaLinux/RHEL 9+):
---------------------------------------------
Создайте файл /etc/systemd/system/pgrok.service:

[Unit]
Description=Pgrok Tunnel
After=network.target

[Service]
Type=simple
User=YOUR_USERNAME
ExecStart=/usr/local/bin/pgrok http 3000
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target

Активируйте сервис:
sudo systemctl daemon-reload
sudo systemctl enable pgrok.service
sudo systemctl start pgrok.service

================================================================================
4. РАБОТА С РАЗНЫМИ ЛОКАЛЬНЫМИ ПОРТАМИ
================================================================================

Если ваш локальный сервер работает не на порту 3000, используйте:

pgrok http 8080          # для порта 8080
pgrok http 5000          # для порта 5000
pgrok http https://localhost:3000  # для HTTPS сервера

Для TCP туннелирования (например, SSH, базы данных):
pgrok tcp 22

================================================================================
5. ПОЛЕЗНЫЕ КОМАНДЫ И ОТЛАДКА
================================================================================

# Просмотр текущей конфигурации
cat ~/.config/pgrok/pgrok.yml   # Linux
# или
type %LOCALAPPDATA%\pgrok\pgrok.yml   # Windows

# Запуск с подробным логированием
pgrok --debug http 3000

# Проверка соединения с сервером
nc -zv pgrok.my.site 2222

# Получение нового токена (если истек)
# Откройте https://pgrok.my.site и авторизуйтесь заново

================================================================================
6. ВАЖНЫЕ ЗАМЕЧАНИЯ
================================================================================

1. SSL/TLS сертификаты выдаются автоматически через Let's Encrypt (Caddy)

2. Для корректной работы убедитесь, что на клиентской машине открыт исходящий
   доступ к порту 2222 сервера pgrok.my.site

3. Токен доступа можно сбросить, войдя в веб-интерфейс https://pgrok.my.site

4. При использовании Docker на клиенте, укажите хост-машину:
   pgrok init --remote-addr pgrok.my.site:2222 --forward-addr http://host.docker.internal:3000

5. Для Windows возможно потребуется разрешить pgrok.exe в брандмауэре Windows

================================================================================
7. ПРИМЕРЫ ИСПОЛЬЗОВАНИЯ
================================================================================

Пример 1: Разработка веб-приложения на React (порт 3000):
---------------------------------------------------------
cd my-react-app
npm start          # запускает dev сервер на localhost:3000
pgrok http 3000    # в другом терминале

Результат: https://username.pgrok.my.site -> ваш React приложение

Пример 2: Демонстрация API на FastAPI (порт 8000):
--------------------------------------------------
uvicorn main:app --reload --port 8000
pgrok http 8000

Пример 3: Тестирование вебхуков на локальном сервере:
-----------------------------------------------------
# Настройте вебхук на отправку на https://username.pgrok.my.site/webhook
pgrok http 3000

Пример 4: Доступ к SSH с публичного интернета:
----------------------------------------------
pgrok tcp 22
# После запуска вы получите адрес типа: tcp://username.pgrok.my.site:12345
# Подключение: ssh user@username.pgrok.my.site -p 12345

================================================================================
Для получения дополнительной информации посетите:
- https://github.com/jerson/pgrok
- https://pgrok.my.site (ваш веб-интерфейс Pgrok)

Дата генерации инструкции: $(date '+%Y-%m-%d %H:%M:%S')
================================================================================
EOF

# Подставляем актуальные данные в инструкции
sed -i "s/pgrok.my.site/$DOMAIN/g" "$CLIENT_INSTRUCTIONS_FILE"

# Добавляем информацию о конфигурации сервера в протокол
cat >> "$PROTOCOL_FILE" << EOF

================================================================================
ДАННЫЕ ДОСТУПА К СЕРВЕРУ (СОХРАНИТЕ В БЕЗОПАСНОМ МЕСТЕ)
================================================================================

Домен: $DOMAIN
URL веб-интерфейса: https://$DOMAIN

Порт для туннелей клиентов: 2222
Порт reverse proxy: 3000
Порт управления: 3320

PostgreSQL:
- Хост: localhost
- База данных: pgrokd
- Пользователь: pgrok
- Пароль: $POSTGRES_PASSWORD

Pgrok Secret Key: $SECRET_KEY

Файлы конфигурации:
- /opt/pgrok/pgrokd.yml - Основная конфигурация Pgrok
- /etc/caddy/Caddyfile - Конфигурация reverse proxy

Логи:
- Docker контейнер: docker logs pgrokd
- Caddy: journalctl -u caddy -f
- PostgreSQL: tail -f /var/log/postgresql/postgresql-*.log

Управление сервисами:
- docker-compose -f /opt/pgrok/docker-compose.yml restart pgrokd
- systemctl restart caddy

================================================================================
ШАГИ ПОСЛЕ УСТАНОВКИ
================================================================================

1. Настройте OIDC аутентификацию (Google/OAuth):
   a) Перейдите в Google Cloud Console → APIs & Services → Credentials
   b) Создайте OAuth 2.0 Client ID для веб-приложения
   c) Укажите Authorized redirect URI: https://$DOMAIN/-/oidc/callback
   d) Скопируйте Client ID и Client Secret
   e) Обновите /opt/pgrok/pgrokd.yml (замените client_id и client_secret)
   f) Перезапустите контейнер: cd /opt/pgrok && docker-compose restart

2. Настройте DNS записи (если еще не сделали):
   - A запись: $DOMAIN -> $(curl -s ifconfig.me)
   - A запись: *.$DOMAIN -> $(curl -s ifconfig.me)

3. Проверьте работу сервера:
   curl -I https://$DOMAIN
   curl -I http://localhost:3320

4. Проверьте работу туннеля (с клиентской машины):
   pgrok init --remote-addr $DOMAIN:2222 --forward-addr http://httpbin.org --token ТЕСТОВЫЙ_ТОКЕН
   pgrok http 80

================================================================================
ИНСТРУКЦИИ ДЛЯ КЛИЕНТОВ СОХРАНЕНЫ В ФАЙЛЕ: $CLIENT_INSTRUCTIONS_FILE
================================================================================
EOF

# Добавляем информацию об инструкциях в основной лог
print_status "Инструкции для клиентов сохранены в: $CLIENT_INSTRUCTIONS_FILE"
print_status "Полный протокол установки сохранен в: $PROTOCOL_FILE"

# -------------------- ФИНАЛЬНАЯ ИНФОРМАЦИЯ ------------------------------------
echo ""
echo "================================================================================="
echo "${GREEN}УСТАНОВКА PGROK УСПЕШНО ЗАВЕРШЕНА${NC}"
echo "================================================================================="
echo ""
echo "📋 Логи и протоколы:"
echo "   - Общий лог установки: $LOG_FILE"
echo "   - Протокол с данными доступа: $PROTOCOL_FILE"
echo "   - Инструкции для клиентов: $CLIENT_INSTRUCTIONS_FILE"
echo ""
echo "🌐 Доступ к веб-интерфейсу: https://$DOMAIN"
echo ""
echo "⚠️  ВАЖНО: Не забудьте настроить OIDC аутентификацию!"
echo "   Замените client_id и client_secret в /opt/pgrok/pgrokd.yml"
echo "   Redirect URI должен быть: https://$DOMAIN/-/oidc/callback"
echo ""
echo "🔄 Для перезапуска сервера: cd /opt/pgrok && docker-compose restart"
echo ""
echo "📖 Полные инструкции для клиентов см. в: $CLIENT_INSTRUCTIONS_FILE"
echo ""
echo "================================================================================="

exit 0