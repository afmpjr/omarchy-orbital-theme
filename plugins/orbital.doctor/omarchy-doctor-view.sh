#!/usr/bin/env bash
# omarchy-doctor-view — Executa a inspeção do doctor e oferece menu interativo de diagnóstico com IA
set -uo pipefail

cmd="${*:-scan --full}"

# 1. Executar o comando solicitado do omarchy-doctor
omarchy-doctor $cmd
exit_code=$?

# Se o usuário cancelou via SIGINT (Ctrl+C), repassa 130
if (( exit_code == 130 )); then
  exit 130
fi

# 2. Detectar idioma para exibição do prompt
lang="${ORBITAL_LANG:-${LC_ALL:-${LC_MESSAGES:-${LANG:-en}}}}"
is_pt=false
if [[ "${lang,,}" =~ ^pt ]]; then
  is_pt=true
fi

# 3. Exibir prompt interativo no tty
if [[ "$is_pt" == true ]]; then
  printf '\n\033[36m● \033[1m[d] Diagnosticar com IA\033[0m | [q/Enter] Fechar... ' >/dev/tty
else
  printf '\n\033[36m● \033[1m[d] Diagnose with AI\033[0m | [q/Enter] Close... ' >/dev/tty
fi

# 4. Ler tecla
read -rsn 1 key </dev/tty || key=""

if [[ "$key" == "d" || "$key" == "D" ]]; then
  if [[ "$is_pt" == true ]]; then
    printf 'd\nIniciando diagnóstico com IA...\n' >/dev/tty
  else
    printf 'd\nLaunching AI diagnosis...\n' >/dev/tty
  fi
  exec omarchy-agent-doctor --inline
fi

echo >/dev/tty
# Retorna 130 para indicar conclusão limpa ao wrapper do terminal flutuante
exit 130
