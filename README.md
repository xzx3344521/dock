# docker-cn
国内 Debain 系统一键安装/卸载 Docker

# 使用说明
安装：
```
bash <(curl -sSL https://raw.githubusercontent.com/xzx3344521/dock/refs/heads/main/dock.sh)
```
卸载：
如果需要保留请提前备份 `/var/lib/docker` 目录
```
bash <(curl -sSL https://raw.githubusercontent.com/xzx3344521/dock/refs/heads/main/dock.sh) -u
```
最近配置linux debian12的实验环境配的好痛苦，所以想到写一个脚本来初始化
```
bash <(curl -sSL https://raw.githubusercontent.com/xzx3344521/dock/refs/heads/main/1.sh)
```
