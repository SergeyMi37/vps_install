#!/bin/bash
# wget https://raw.githubusercontent.com/SergeyMi37/vps_install/master/ubuntu/vps_ubuntu_install_aspia.sh && sudo chmod +x vps_ubuntu_install_aspia.sh && sudo ./vps_ubuntu_install_aspia.sh

# Скрипт для установки Aspia Router / Relay на Debian/Ubuntu
# Основан на статье Habr: https://habr.com/ru/articles/711122/
# Работоспособность проверена на момент выхода статьи (версия 2.7.0)

set -e  # Остановка при любой ошибке

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- Функции ---
print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Проверка на root
if [[ $EUID -ne 0 ]]; then
   print_error "Этот скрипт должен запускаться от root (sudo)."
   exit 1
fi

# Проверка и установка wget, если необходимо
if ! command -v wget &> /dev/null; then
    print_warn "wget не найден. Устанавливаю..."
    apt update && apt install wget -y
    print_info "wget установлен."
fi

# Функция установки компонента
install_component() {
    local COMP_NAME=$1
    local PKG_NAME=$2
    local VERSION="2.7.0"  # Можно изменить на актуальную с https://github.com/dchapyshev/aspia/releases
    local URL="https://github.com/dchapyshev/aspia/releases/download/v${VERSION}/${PKG_NAME}-${VERSION}-x86_64.deb"
    
    print_info "Установка ${COMP_NAME}..."
    cd /tmp
    rm -f "${PKG_NAME}"*.deb 2>/dev/null
    
    if wget "${URL}"; then
        apt install -y "./${PKG_NAME}-${VERSION}-x86_64.deb"
        print_info "${COMP_NAME} установлен."
    else
        print_error "Не удалось скачать пакет ${COMP_NAME}. Проверьте версию и соединение."
        exit 1
    fi
}

# Главное меню
echo "=== Установка компонентов Aspia (Router / Relay) ==="
echo "Выберите действие:"
echo "1) Установить Aspia Router + сгенерировать конфиг"
echo "2) Установить Aspia Relay + сгенерировать конфиг"
echo "3) Установить оба компонента (Router + Relay) на одном сервере"
echo "0) Выход"
read -p "Введите номер [0-3]: " choice

case $choice in
    1)
        install_component "Aspia Router" "aspia-router"
        print_info "Генерация конфигурационного файла router.json..."
        aspia_router --create-config
        print_info "Файл создан: /etc/aspia/router.json"
        print_warn "Не забудьте отредактировать /etc/aspia/router.json (особенно RelayWhiteList, если будете ставить Relay)."
        echo "Пример правки: sudo nano /etc/aspia/router.json"
        # Включение и запуск
        systemctl enable aspia-router
        service aspia-router start
        print_info "Служба aspia-router включена и запущена."
        print_info "Публичный ключ (понадобится для Relay): /etc/aspia/router.pub"
        ;;
    2)
        install_component "Aspia Relay" "aspia-relay"
        print_info "Генерация конфигурационного файла relay.json..."
        aspia_relay --create-config
        print_info "Файл создан: /etc/aspia/relay.json"
        print_warn "ВАЖНО! Необходимо вручную отредактировать /etc/aspia/relay.json и указать:"
        echo "  - RouterAddress (адрес маршрутизатора, например 127.0.0.1)"
        echo "  - RouterPort (по умолчанию 8070)"
        echo "  - RouterPublicKey (взять из /etc/aspia/router.pub на сервере Router)"
        echo "  - PeerAddress (внешний DNS или IP, который будут видеть клиенты)"
        echo "Пример: sudo nano /etc/aspia/relay.json"
        # Включение и запуск (после настройки)
        systemctl enable aspia-relay
        service aspia-relay start
        print_info "Служба aspia-relay включена и запущена (проверьте конфиг)."
        ;;
    3)
        print_info "Установка Router + Relay на одном сервере."
        install_component "Aspia Router" "aspia-router"
        aspia_router --create-config
        
        install_component "Aspia Relay" "aspia-relay"
        aspia_relay --create-config
        
        print_warn "Теперь настройте оба конфига: "
        echo "1) /etc/aspia/router.json"
        echo "   - В параметр RelayWhiteList добавьте 127.0.0.1"
        echo "2) /etc/aspia/relay.json"
        echo "   - RouterAddress = \"127.0.0.1\""
        echo "   - RouterPort = 8070"
        echo "   - RouterPublicKey = $(cat /etc/aspia/router.pub 2>/dev/null || echo '<скопируйте содержимое /etc/aspia/router.pub>')"
        echo "   - PeerAddress = \"<ВНЕШНИЙ_IP_ИЛИ_DNS_ВАШЕГО_СЕРВЕРА>\""
        echo ""
        
        systemctl enable aspia-router aspia-relay
        service aspia-router start && service aspia-relay start
        
        print_info "Оба компонента установлены. Не забудьте настроить конфиги и открыть порты (8070 - Router, 8080 - Relay по умолчанию) в фаерволе."
        ;;
    0)
        print_info "Выход."
        exit 0
        ;;
    *)
        print_error "Неверный выбор."
        exit 1
        ;;
esac

print_info "=== Работа скрипта завершена ==="
print_warn "Рекомендации после установки:"
echo "- Проверить статус служб: systemctl status aspia-{router,relay}"
echo "- Посмотреть логи: journalctl -u aspia-router -u aspia-relay"
echo "- Для управления через Aspia Console: используйте логин:пароль admin:admin (измените!)."
echo "- Подробная настройка - в статье: https://habr.com/ru/articles/711122/"