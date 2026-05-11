# vps_install
Скрипты по установки приложений на новые сервера

# Cоздать судо пользователя
```
wget https://raw.githubusercontent.com/SergeyMi37/vps_install/master/ubuntu/vps_ubuntu_newuser.sh && sudo chmod +x vps_ubuntu_newuser.sh && ./vps_ubuntu_newuser.sh -u msw -p P@S5w0rd

su - msw
```
# Клонируем и зайдем в репу
```
git clone https://github.com/SergeyMi37/vps_install && cd vps_install/ubuntu && sudo chmod +x *.sh
```

# Сначало надо установить основные приложения
```
./vps_ubuntu.sh
```

# Создает sudo-пользователя, меняет порт SSH, запрещает root-доступ и включает вход только по ключам. Нужно будет ввести пароль для msw2, YES, бубличный ключ и YES
```
su - msw
cd vps_install/ubuntu
./vps_ubuntu_newssh.sh --user msw2 
```

# Минимальная установка VNC и вводим для него пароль, который используем при подключении
```
./vps_ubuntu_vnc.sh
```

 # Скрипт установки LibreWolf на Ubuntu 22.04 Автоматически определяет лучший способ установки
 ```
./vps_ubuntu_lwolf.sh
 ```

# Установка серверов ID для RustDesk c кастомным SSH портом
sudo ./vps_ubuntu_install_rustdesk.sh -d rustdesk.example.com -e admin@example.com -s 2222

# Установка серверов ID для RustDesk c кастомным SSH портом
sudo apt install ./rustdesk-1.4.6-x86_64.deb

# Установка GitLab на локальном порту
sudo ./vps_ubuntu_install_gitlab.sh

# После успешной установки GitLab будет доступен по указанному IP, а временный пароль root можно посмотреть командой:
sudo cat /etc/gitlab/initial_root_password | grep Password:

# Установка git-forgejo 
sudo ./git-forgejo.sh


# Установка self-hosted серверов для управления паролями 
https://chat.deepseek.com/share/ljmn6jplibceeqkv1k

## Passbolt	Ориентирован на команды. Имеет удобный интерфейс и ролевую модель. Работает на GPG-ключах .	Те, кто ищет точную копию PassBolt (тот же продукт).

## Psono	Полнофункциональный менеджер с открытым исходным кодом, фокус на безопасность и удобство для команд .	Команды, которым нужен визуально современный интерфейс.

## sysPass	Веб-ориентированный менеджер, поддерживающий многопользовательский режим и распределение ролей .	Администраторы, которым нравится работа через веб-интерфейс (как в PassBolt).

## KeeWeb	Кроссплатформенный клиент для баз KeePass. Файл паролей хранится там, где вы укажете (облако, диск), и синхронизируется .Те, кто не хочет поднимать тяжелый сервер и предпочитает просто синхронизировать файл с паролями.


# Установка GitLab на VPS и тунелей самохостируемых аналогов NgRok
https://chat.deepseek.com/share/3jmovy3u2n8vdt4dui

# Аналоги NextCloud для VPS
https://chat.deepseek.com/share/3ccm38csi13cbg8s24

# Создание локального NAS и доступ к нему из интернета через pangolin, frp или SirTunnel
https://chat.deepseek.com/share/9rqlfknrtc2d1untl0

# Open Source Alternatives to Ingrok
https://chat.deepseek.com/share/aookwc9dw6dno2hmnt

https://github.com/bjarneo/stairway
https://github.com/pgrok/pgrok
https://github.com/anderspitman/SirTunnel
https://github.com/anderspitman/awesome-tunneling


