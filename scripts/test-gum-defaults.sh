#!/usr/bin/env bash
# Stub Gum's prompts with their configured defaults for terminal-driven installer tests.
# Test hooks (all optional, all unset by default):
#   ORBITAL_GUM_EXIT=N   make choose/input exit N (e.g. 130 simulates Esc/cancel).
#   ORBITAL_GUM_PICK=LBL make single-choice return LBL when it is one of the options.
set -euo pipefail

command=$1
shift

if [[ -n ${ORBITAL_GUM_EXIT:-} ]]; then exit "$ORBITAL_GUM_EXIT"; fi
pick=${ORBITAL_GUM_PICK:-}

case $command in
  choose)
    selected=''
    multi=0
    options=()
    while (($#)); do
      case $1 in
        --selected) selected=$2; shift 2 ;;
        --no-limit) multi=1; shift ;;
        --height|--header) shift 2 ;;
        --*) shift ;;
        *) options+=("$1"); shift ;;
      esac
    done
    if (( multi )); then
      [[ -n $selected ]] && tr ',' '\n' <<<"$selected"
      exit 0
    fi
    if [[ -n $pick ]]; then
      for o in "${options[@]}"; do [[ $o == "$pick" ]] && { echo "$pick"; exit 0; }; done
    fi
    if [[ -n $selected ]]; then echo "$selected"; else echo "${options[0]}"; fi
    ;;
  input)
    while (($#)); do
      if [[ $1 == --value ]]; then echo "$2"; exit 0; fi
      shift
    done
    ;;
  style) : ;;
  *) exit 2 ;;
esac
