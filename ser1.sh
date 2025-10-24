#!/usr/bin/env bash
# install-glider.sh
# Dockerized glider: listen as SS locally and forward to remote SS.
# Example:
#   LISTEN_PASS='156856' REMOTE_IP='202.182.109.53' ./install-glider.sh

set -euo pipefail

# ========= Параметры (можно переопределять через ENV) =========
CONTAINER_NAME="${CONTAINER_NAME:-proxy}"
METHOD="${METHOD:-AEAD_AES_256_GCM}"

LISTEN_PORT="${LISTEN_PORT:-8388}"
LISTEN_PASS="${LISTEN_PASS:-858456}"
# REMOTE: куда форвардить
REMOTE_IP="${REMOTE_IP:-5.188.38.98}"
REMOTE_PORT="${REMOTE_PORT:-8388}"
REMOTE_PASS="${REMOTE_PASS:-$LISTEN_PASS}"   # по умолчанию такой же, как LISTEN_PASS

ENABLE_UFW="${ENABLE_UFW:-1}"                 # 1 = открыть порт в UFW, если установлен

# ========= Утилиты =========
info(){ printf "\n\033[1;36m[INFO]\033[0m %s\n" "$*"; }
ok(){   printf "\033[1;32m[OK]\033[0m %s\n" "$*"; }
err(){  printf "\033[1;31m[ERR]\033[0m %s\n" "$*"; exit 1; }

# ========= Проверки =========
[ -n "$LISTEN_PASS" ] || err "LISTEN_PASS is required (пароль для локального SS)."
[ -n "$REMOTE_IP" ]   || err "REMOTE_IP is required (IP удалённого SS)."

# ========= Установка Docker (если нет) =========
if ! command -v docker >/dev/null 2>&1; then
  info "Устанавливаю Docker"
  apt-get update -y >/dev/null
  apt-get install -y ca-certificates curl gnupg lsb-release >/dev/null
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
  apt-get update -y >/dev/null
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null
  systemctl enable --now docker >/dev/null
  ok "Docker установлен и запущен"
else
  ok "Docker уже установлен"
fi

# ========= Остановка/удаление старого контейнера (если есть) =========
if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
  info "Останавливаю и удаляю существующий контейнер $CONTAINER_NAME"
  docker rm -f "$CONTAINER_NAME" >/dev/null || true
  ok "Старый контейнер удалён"
fi

# ========= Запуск нового контейнера =========
# Используем host-сеть (как в твоём inspect) и автоперезапуск
GLIDER_IMAGE="nadoo/glider:latest"
LISTEN_URI="ss://${METHOD}:${LISTEN_PASS}@:${LISTEN_PORT}"
FORWARD_URI="ss://${METHOD}:${REMOTE_PASS}@${REMOTE_IP}:${REMOTE_PORT}"

info "Тяну образ $GLIDER_IMAGE"
docker pull "$GLIDER_IMAGE" >/dev/null
ok "Образ скачан"

info "Запускаю контейнер $CONTAINER_NAME"
docker run -d --name "$CONTAINER_NAME" \
  --network host \
  --restart unless-stopped \
  "$GLIDER_IMAGE" \
  -verbose \
  -listen "$LISTEN_URI" \
  -forward "$FORWARD_URI" >/dev/null
ok "Контейнер запущен"

# ========= Открыть порт в UFW (если установлен) =========
if command -v ufw >/dev/null 2>&1 && [ "$ENABLE_UFW" = "1" ]; then
  info "Открываю порт $LISTEN_PORT в UFW (TCP/UDP)"
  ufw status | grep -q "${LISTEN_PORT}/tcp" || ufw allow "${LISTEN_PORT}/tcp" >/dev/null || true
  ufw status | grep -q "${LISTEN_PORT}/udp" || ufw allow "${LISTEN_PORT}/udp" >/dev/null || true
  ok "Правила UFW применены"
fi

# ========= Финальные проверки =========
info "Проверка статуса контейнера"
docker ps --filter "name=${CONTAINER_NAME}" --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'

info "Последние логи (20 строк)"
docker logs --tail 20 "$CONTAINER_NAME" || true

info "Прослушиваемые сокеты (порт ${LISTEN_PORT})"
ss -ltnup 2>/dev/null | grep -E ":${LISTEN_PORT}\s" || true
ss -lunup 2>/dev/null | grep -E ":${LISTEN_PORT}\s" || true

ok "Готово. glider слушает SS на :${LISTEN_PORT} и форвардит на ${REMOTE_IP}:${REMOTE_PORT}"
echo "Напоминание: открой порт ${LISTEN_PORT} в фаерволе провайдера (например, Lightsail → Networking)."






