# vps_install
Скрипты по установки приложений на новые сервера

# Сначало надо установить основные приложения
```
wget https://raw.githubusercontent.com/SergeyMi37/vps_install/master/ubuntu/vps_ubuntu.sh && chmod +x vps_ubuntu.sh && ./vps_ubuntu.sh
```
или
```
wget -qO /tmp/vps_setup.sh https://raw.githubusercontent.com/SergeyMi37/vps_install/master/ubuntu/vps_ubuntu.sh && chmod +x /tmp/vps_setup.sh && sudo bash /tmp/vps_setup.sh && rm /tmp/vps_setup.sh
```

# Cоздать судо пользователя и добавить его в группу docker
```
wget https://raw.githubusercontent.com/SergeyMi37/vps_install/master/ubuntu/vps_ubuntu_newuser.sh && sudo chmod +x vps_ubuntu_newuser.sh && ./vps_ubuntu_newuser.sh -u userdoc -p P@S5w0rd
```
# Создает sudo-пользователя, меняет порт SSH,  запрещает root-доступ и включает вход только по ключам

```
sudo wget https://raw.githubusercontent.com/SergeyMi37/vps_install/master/ubuntu/vps_ubuntu_newssh.sh && sudo chmod +x vps_ubuntu_newssh.sh && sudo ./vps_ubuntu_newssh.sh --user msw3
```

# Минимальная установка VNC и вводим для него пароль, который используем при подключении
```
wget https://raw.githubusercontent.com/SergeyMi37/vps_install/master/ubuntu/vps_ubuntu_vnc.sh && sudo chmod +x vps_ubuntu_vnc.sh && ./vps_ubuntu_vnc.sh
```

 # Скрипт установки LibreWolf на Ubuntu 22.04 Автоматически определяет лучший способ установки
 ```
 # wget https://raw.githubusercontent.com/SergeyMi37/vps_install/master/ubuntu/vps_ubuntu_lwolf.sh && sudo chmod +x vps_ubuntu_lwolf.sh && ./vps_ubuntu_lwolf.sh
 ```

 # Установка серверов ID для CrossDesk, RustDesk и Aspia
 ## Только CrossDesk
sudo ./install_both.sh --cross-only -d cross.example.com -e admin@example.com

## Только RustDesk
sudo ./install_both.sh --rust-only -r rust.example.com -e admin@example.com

## Оба сервера без SSL (только HTTP)
sudo ./install_both.sh -d cross.example.com -r rust.example.com -e admin@example.com --no-ssl

## Без доменов (только по IP)
sudo ./install_both.sh

## С кастомным SSH портом
sudo ./install_both.sh -d cross.example.com -r rust.example.com -e admin@example.com -s 2222
 
## Установка серверов Aspia
wget https://raw.githubusercontent.com/SergeyMi37/vps_install/master/ubuntu/vps_ubuntu_install_aspia.sh && sudo chmod +x vps_ubuntu_install_aspia.sh && sudo ./vps_ubuntu_install_aspia.sh


# Установка self-hosted серверов для управления паролями 

https://chat.deepseek.com/share/ljmn6jplibceeqkv1k

## Passbolt	Ориентирован на команды. Имеет удобный интерфейс и ролевую модель. Работает на GPG-ключах .	Те, кто ищет точную копию PassBolt (тот же продукт).
## Psono	Полнофункциональный менеджер с открытым исходным кодом, фокус на безопасность и удобство для команд .	Команды, которым нужен визуально современный интерфейс.
## sysPass	Веб-ориентированный менеджер, поддерживающий многопользовательский режим и распределение ролей .	Администраторы, которым нравится работа через веб-интерфейс (как в PassBolt).
## KeeWeb	Кроссплатформенный клиент для баз KeePass. Файл паролей хранится там, где вы укажете (облако, диск), и синхронизируется .	Те, кто не хочет поднимать тяжелый сервер и предпочитает просто синхронизировать файл с паролями.


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


