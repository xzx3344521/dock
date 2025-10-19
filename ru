#!/bin/bash
file_path="/boot/脚本/1.yaml"
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
      - RELAY=<relay_server[:port]>
      - ENCRYPTED_ONLY=1
      - MUST_LOGIN=y
      - TZ=Asia/Shanghai
      - RUSTDESK_API_RUSTDESK_ID_SERVER=127.0.0.1:21116
      - RUSTDESK_API_RUSTDESK_RELAY_SERVER=127.0.0.1:21117
      - RUSTDESK_API_RUSTDESK_API_SERVER=http://127.0.0.1:21114
      - RUSTDESK_API_KEY_FILE=/data/id_ed25519.pub
      - RUSTDESK_API_JWT_KEY=xxx3344 # jwt key
    volumes:
      - /data/rustdesk/server:/data
      - /data/rustdesk/api:/app/data #将数据库挂载
    networks:
      - rustdesk-net
    restart: unless-stopped


" > "$file_path"
sleep 1
docker compose -p my_rustdesk_project -f /boot/脚本/1.yaml up -d
