#!/usr/bin/env bash
# ==============================================================================
# systemd-inspector.sh — Inspeção e Saneamento Interativo de Unidades Systemd
# ==============================================================================
set -uo pipefail

echo "======================================================================"
echo "               INSPEÇÃO DE UNIDADES SYSTEMD EM FALHA"
echo "======================================================================"
echo ""

echo "--- [1/2] Unidades System (Sistema) em Falha ---"
systemctl --failed --no-pager || true
echo ""

echo "--- [2/2] Unidades User (Usuário) em Falha ---"
systemctl --user --failed --no-pager || true
echo ""

echo "======================================================================"
echo "Opções de Ação:"
echo "  [r] Executar 'reset-failed' (limpa o histórico de falhas no painel)"
echo "  [qualquer outra tecla] Apenas fechar sem alterar nada"
echo "======================================================================"
read -n 1 -r -p "Sua escolha: " key
echo ""

if [[ "$key" == "r" || "$key" == "R" ]]; then
  echo ""
  echo "Limpando unidades em falha do usuário..."
  systemctl --user reset-failed || true
  
  echo "Limpando unidades em falha do sistema (requer senha de sudo)..."
  sudo systemctl reset-failed || true
  
  echo "Atualizando telemetria do omarchy-doctor..."
  omarchy-doctor scan --json >/dev/null 2>&1 || true
  
  echo ""
  echo "Pronto! O estado do systemd foi redefinido e o painel Doctor foi atualizado."
  sleep 1.5
fi
