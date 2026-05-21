# vps_install
Скрипты по установки приложений на новые сервера.

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

# Добавить приложения, создать sudo-пользователя, поменять порт SSH, запрещает root-доступ и включает вход только по ключам. 
```
wget https://raw.githubusercontent.com/SergeyMi37/vps_install/master/ubuntu/vps_ubuntu.sh && chmod +x vps_ubuntu.sh && ./vps_ubuntu.sh
sudo wget https://raw.githubusercontent.com/SergeyMi37/vps_install/master/ubuntu/vps_ubuntu_new_user_ssh.sh && sudo chmod +x vps_ubuntu_new_user_ssh.sh && sudo ./vps_ubuntu_new_user_ssh.sh --user msw --pass 123 --key "ssh-ed25519..." --port 6553

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

# Установка хостинга для git forgejo 
sudo ./git-forgejo.sh

# Создание пользователя админом через CLI
forgejo admin user create \
  --username ИМЯ \
  --password ПАРОЛЬ \
  --email EMAIL@ПРИМЕР.ru \
  --admin false  # или true, если нужны права админа

# Удалить пользователя админом через CLI
forgejo admin user delete --username --purge USERNAME

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

# Создание локального NAS и доступ к нему из интернета через frp 
Первый запуск:
bash
sudo ./install_frp.sh \
  -d example.site \
  --setup-caddy \
  --caddy-email admin@example.site \
  --proxy-pass "frp.example.site:7500" \
  --proxy-pass "gitea.example.site:3000" \
  --proxy-pass "jenkins.example.site:8080" \
  --proxy-pass "wordpress.example.site:8081"
Результат: Добавлены все 4 прокси.

Второй запуск (дополнение):
bash
sudo ./install_frp.sh \
  -d example.site \
  --setup-caddy \
  --proxy-pass "nas.example.site:192.168.1.100:5000" \
  --proxy-pass "plex.example.site:192.168.1.100:32400" \
  --proxy-pass "camera.example.site:192.168.1.50:8080"
Результат: Будет 7 прокси (4 старых + 3 новых).

🎯 Команды для управления

Просмотр текущих прокси:
bash
grep -E "^[a-z].*\.{$" /etc/caddy/Caddyfile | sed 's/ {$//'
Удаление конкретного прокси:
bash
sudo nano /etc/caddy/Caddyfile

# Удалите блок нужного домена и выполните:
sudo systemctl reload caddy
Полное обновление (замена всех правил):
bash

# Сначала удалите старый конфиг
sudo rm /etc/caddy/Caddyfile

# Затем запустите скрипт с нужными параметрами
sudo ./install_frp.sh -d example.site --setup-caddy --proxy-pass "new1.site:8080" --proxy-pass "new2.site:9090"
Ручное добавление прокси без скрипта:
bash
sudo tee -a /etc/caddy/Caddyfile << EOF

new-service.example.site {
    reverse_proxy 192.168.1.100:5000
}

EOF
sudo systemctl reload caddy