#!/bin/bash
# wget https://raw.githubusercontent.com/SergeyMi37/vps_install/master/ubuntu/vps_ubuntu_vnc.sh && sudo chmod +x vps_ubuntu_vnc.sh && ./vps_ubuntu_vnc.sh

# Минимальная установка VNC
sudo apt update
sudo apt install -y tigervnc-standalone-server tigervnc-common xfce4 xfce4-goodies

# Настройка пароля
echo "Введите пароль для входа в VNC "
vncpasswd

# Создание конфигурации
mkdir -p ~/.vnc
cat > ~/.vnc/xstartup << 'EOF'
#!/bin/bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec startxfce4
EOF

chmod +x ~/.vnc/xstartup

# Запуск сервера
vncserver -kill :1 2>/dev/null
vncserver :1 -geometry 1366x768 -depth 24 -localhost

SERVER_IP=$(ip -4 route get 1 | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
CURRENT_USER=$(whoami)

echo "VNC установлен! Порт: 5901"
echo "Подключение: ssh -L 5901:localhost:5901 -N ${CURRENT_USER}@${SERVER_IP}"