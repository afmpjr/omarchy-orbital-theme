#!/usr/bin/env bash
# omarchy-agent-doctor — Diagnostica o estado do sistema via Omarchy Doctor
# Arquitetura universal e desacoplada:
# 1. Se 'ai-dispatch' estiver presente no PATH (ambiente corporativo), despacha via esteira de IA com failover de cotas.
# 2. Se 'ai-dispatch' não estiver presente (usuário padrão/distribuição aberta), invoca o agente padrão do sistema (omarchy-agent).
set -euo pipefail

is_wait=false
if [[ "${1:-}" == "--wait" || "${1:-}" == "--inline" ]]; then
  is_wait=true
fi

# Se invocado sem TTY interativo (ex: pelo painel gráfico QML), abre via omarchy-launch-tui
if [[ "$is_wait" == false && ! -t 0 ]]; then
  exec omarchy-launch-tui --app-id=org.omarchy.doctor "$0" --wait
fi

# 1. Coletar dados do doctor scan
scan_output=""
if command -v omarchy-doctor >/dev/null 2>&1; then
  scan_output=$(omarchy-doctor scan --json 2>/dev/null || omarchy-doctor scan 2>/dev/null || true)
fi

if [[ -z "$scan_output" && -f "$HOME/.local/state/omarchy-doctor/state.json" ]]; then
  scan_output=$(cat "$HOME/.local/state/omarchy-doctor/state.json" 2>/dev/null || true)
fi

# 2. Se a esteira oficial ai-dispatch estiver presente no sistema (Estratégia Corporativa):
if command -v ai-dispatch >/dev/null 2>&1; then
  BRIEF_DIR="$HOME/ai-memory/jobs"
  mkdir -p "$BRIEF_DIR" 2>/dev/null || BRIEF_DIR="/tmp"
  TIMESTAMP=$(date +%Y%m%d-%H%M%S)
  BRIEF_FILE="$BRIEF_DIR/doctor-diagnosis-$TIMESTAMP.md"

  cat <<EOF > "$BRIEF_FILE"
# Diagnóstico de Saúde da Estação Omarchy — Doctor

## Contexto & Snapshot do Doctor
\`\`\`json
${scan_output:-"Nenhum output direto retornado. Analise os recursos da estação (disco, memória, docker, systemd)."}
\`\`\`

## Missão para Danilo [SRE & Tooling]
1. Analisar os alertas e recursos apontados no scan (ex: uso de disco /, volumes/imagens órfãos do Docker, cache do pacman/usuário, pressão de memória/PSI ou unidades systemd em falha).
2. Explicar com clareza a causa raiz das condições encontradas.
3. Apresentar um plano de ação seguro e objetivo, indicando os comandos recomendados para remediação e saneamento.
EOF

  echo -e "\033[1;36m================================================================================\033[0m"
  echo -e "\033[1;36m[Omarchy Doctor] Diagnóstico com IA via Esteira ai-dispatch\033[0m"
  echo -e "\033[1;36m================================================================================\033[0m"

  set +e
  ai-dispatch --title "[Danilo] Diagnóstico Omarchy Doctor" --brief "$BRIEF_FILE" --wait
  dispatch_rc=$?
  set -e

  echo ""
  if [ $dispatch_rc -eq 0 ]; then
    echo -e "\033[32m● Diagnóstico concluído com sucesso pela esteira de IA.\033[0m"
  else
    echo -e "\033[33m● Execução da esteira finalizada (código $dispatch_rc).\033[0m"
  fi

  if [ -e /dev/tty ]; then
    echo ""
    read -rsn 1 -p "Pressione qualquer tecla para fechar..." _ </dev/tty || true
    echo ""
  elif [ -t 0 ]; then
    echo ""
    read -rsn 1 -p "Pressione qualquer tecla para fechar..." _ || true
    echo ""
  fi
  exit $dispatch_rc
fi

# 3. Fallback Universal e Autônomo (qualquer usuário externo com Omarchy puro):
prompt=$(cat <<PROMPT
A system health inspection was requested via Omarchy Doctor on this workstation.

Current Omarchy Doctor scan details:
${scan_output:-"No direct scan output. Check system health using 'omarchy-doctor scan' or inspecting system resources."}

Please:
1. Analyze this system diagnostic report and identify any bottlenecks, resource exhaustion, or health warnings (such as root disk usage, orphaned Docker resources, pacman/user caches, failed systemd units, or memory/PSI pressure).
2. Explain the root causes clearly and objectively.
3. Recommend specific, safe remediation actions and assist the user in executing safe fixes (e.g. running 'omarchy-doctor fix --dry-run' or approved cleanups).
PROMPT
)

if command -v omarchy-agent >/dev/null 2>&1; then
  exec omarchy-agent --inline --prompt "$prompt"
else
  echo -e "\033[31m[Omarchy Doctor] Nem 'ai-dispatch' nem 'omarchy-agent' foram encontrados no PATH.\033[0m" >&2
  exit 1
fi
