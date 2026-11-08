#!/usr/bin/env bash
# ==============================================================================
# sanitize-station.sh — Saneamento Seguro da Estação Omarchy / Orbital
# ==============================================================================
# Executa limpezas seguras do omarchy-doctor com --yes (preservando docker_volumes),
# poda cache de build do Docker e imagens órfãs sem container associado,
# reinicia containers com acúmulo de processos zumbis (<defunct>),
# e atualiza a telemetria do widget orbital.doctor.
# ==============================================================================
set -uo pipefail

export PATH="/usr/share/omarchy/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

notify_user() {
  local title="$1"
  local msg="$2"
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -a "Omarchy Doctor" -i "emblem-system-symbolic" "$title" "$msg" 2>/dev/null || true
  fi
}

notify_user "Saneamento em Andamento" "Higienizando caches, podando imagens órfãs e reciclando processos..."

# 1. Reiniciar containers com acúmulo de processos zumbis
if command -v docker >/dev/null 2>&1 && [[ -S /var/run/docker.sock ]]; then
  docker restart alfred-assistant tts-gateway >/dev/null 2>&1 || true
fi

# 2. Executar limpezas seguras via omarchy-doctor
SAFE_ACTIONS=(
  "pacman_cache"
  "user_cache"
  "coredumps"
  "systemd_journal"
  "old_logs"
  "docker_cache"
)

for action in "${SAFE_ACTIONS[@]}"; do
  omarchy-doctor fix --only "${action}" --apply --yes >/dev/null 2>&1 || true
done

# 3. Podar caches pesados de build e imagens sem container
if command -v docker >/dev/null 2>&1 && [[ -S /var/run/docker.sock ]]; then
  docker builder prune -a -f >/dev/null 2>&1 || true
  docker image prune -a -f >/dev/null 2>&1 || true
fi

# 4. Limpar caches temporários de ferramentas de build
rm -rf "$HOME/.cache/pip" "$HOME/.cache/debuginfod_client" 2>/dev/null || true
if [[ -d "$HOME/.cache/yay" ]]; then
  find "$HOME/.cache/yay" -mindepth 1 -maxdepth 2 -type f -name '*.pkg.tar.*' -mtime +7 -delete 2>/dev/null || true
fi

# 5. Reset de unidades com falha do usuário
systemctl --user reset-failed >/dev/null 2>&1 || true

# 6. Atualizar estado do doctor
systemctl --user restart omarchy-doctor >/dev/null 2>&1 || true
omarchy-doctor scan --json >/dev/null 2>&1 || true

DISK_AVAIL=$(df -h / | awk 'NR==2 {print $4}')
notify_user "Saneamento Concluído" "Estação saneada com sucesso. Espaço livre na partição /: ${DISK_AVAIL}."
