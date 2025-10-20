#!/bin/bash
sudo mkdir -p /data
sudo mkdir -p /boot/脚本
file_path="/boot/脚本/ru.yaml"
echo "# 方便检查的备注
#./apimain reset-admin-pwd <pwd>
networks:
  rustdesk-net:
    external: false
services:
  rustdesk:
    ports:
      - 21114:21114
      - 21115:21115
      - 21116:21116
      - 21116:21116/udp
      - 21117:21117
      - 21118:21118
      - 21119:21119
    image: lejianwen/rustdesk-server-s6:latest
    environment:
      - RELAY=127.0.0.1
      - ENCRYPTED_ONLY=1
      - MUST_LOGIN=n
      - TZ=Asia/Shanghai
      - RUSTDESK_API_RUSTDESK_ID_SERVER=127.0.0.1:21116
      - RUSTDESK_API_RUSTDESK_RELAY_SERVER=127.0.0.1:21117
      - RUSTDESK_API_RUSTDESK_API_SERVER=http://127.0.0.1:21114
      - RUSTDESK_API_KEY_FILE=/data/id_ed25519.pub
      - RUSTDESK_API_JWT_KEY=xxx23344 # jwt key
    volumes:
      - /data/rustdesk/server:/data
      - /data/rustdesk/api:/app/data #将数据库挂载
    networks:
      - rustdesk-net
    restart: unless-stopped

" > "$file_path"
sleep 1
docker compose -p my_rustdesk_project -f /boot/脚本/ru.yaml up -d
while true; do
    if docker ps | grep -q "my_rustdesk_project-rustdesk-1"; then
       
        docker exec -it my_rustdesk_project-rustdesk-1 sh -c './apimain reset-admin-pwd 3459635287'
        sudo stdbuf -oL sudo /sbin/ip -4 addr show scope global | grep -oP 'inet \K[\d.]+' | head -n 1 | sed 's/^/访问地址: /;s/$/:21114/' | tr -d '\r'
        echo -e "\033[32mRustDesk管理员账号: admin\033[0m"
        echo -e "\033[32mRustDesk管理员密码: 3459635287\033[0m"
        break
    else
        sleep 1
    fi
done
