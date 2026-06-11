if [[ -n "${TABTERM_BASH_INTEGRATION_LOADED:-}" ]]; then
  return 0
fi

declare -g TABTERM_BASH_INTEGRATION_LOADED=1
declare -g TABTERM_SHELL_COMMAND_ACTIVE=0
declare -g TABTERM_BASH_INTERNAL=0

_tabterm_emit_osc7() {
  printf '\033]7;file://%s%s\033\\' "${HOSTNAME:-${HOST:-}}" "$PWD"
}

_tabterm_set_title() {
  printf '\033]2;%s\033\\' "$1"
}

_tabterm_command_label() {
  local input="$1"
  local shell_name="${SHELL##*/}"
  local -a words=()
  local word
  local index=0
  local result=""
  local first=1

  read -r -a words <<< "$input"
  [[ -n "$shell_name" ]] || shell_name="bash"

  while (( index < ${#words[@]} )); do
    word="${words[index]}"

    if [[ "$word" == *=* && "$word" != */* ]]; then
      (( index++ ))
      continue
    fi

    case "$word" in
      command|builtin|nohup|time)
        (( index++ ))
        continue
        ;;
      env)
        (( index++ ))
        while (( index < ${#words[@]} )); do
          word="${words[index]}"
          if [[ "$word" == -* || ( "$word" == *=* && "$word" != */* ) ]]; then
            (( index++ ))
            continue
          fi
          break
        done
        continue
        ;;
      sudo|doas|nice)
        (( index++ ))
        while (( index < ${#words[@]} )); do
          word="${words[index]}"
          if [[ "$word" == -* || ( "$word" == *=* && "$word" != */* ) ]]; then
            (( index++ ))
            continue
          fi
          break
        done
        continue
        ;;
    esac

    break
  done

  while (( index < ${#words[@]} )); do
    word="${words[index]}"
    if (( first )) && [[ "$word" == */* ]]; then
      word="${word##*/}"
    fi

    if [[ -n "$result" ]]; then
      result="$result $word"
    else
      result="$word"
    fi

    first=0
    (( index++ ))
  done

  if [[ -n "$result" ]]; then
    printf '%s\n' "$result"
    return
  fi

  printf '%s\n' "$shell_name"
}

_tabterm_prompt_command() {
  local exit_code=$?
  local shell_name="${SHELL##*/}"
  TABTERM_BASH_INTERNAL=1
  [[ -n "$shell_name" ]] || shell_name="bash"

  if (( TABTERM_SHELL_COMMAND_ACTIVE )); then
    printf '\033]133;D;%s\033\\' "$exit_code"
    TABTERM_SHELL_COMMAND_ACTIVE=0
  fi

  _tabterm_set_title "$shell_name"
  printf '\033]133;A\033\\'
  _tabterm_emit_osc7
  return "$exit_code"
}

_tabterm_prompt_ready() {
  local exit_code=$?
  TABTERM_BASH_INTERNAL=0
  return "$exit_code"
}

_tabterm_preexec() {
  local command="$1"

  if (( TABTERM_BASH_INTERNAL || TABTERM_SHELL_COMMAND_ACTIVE )); then
    return
  fi

  case "$command" in
    _tabterm_*|PROMPT_COMMAND=*|trap\ *)
      return
      ;;
  esac

  TABTERM_SHELL_COMMAND_ACTIVE=1
  _tabterm_set_title "$(_tabterm_command_label "$command")"
  printf '\033]133;B\033\\'
  printf '\033]133;C\033\\'
}

__tabterm_prompt_decl="$(declare -p PROMPT_COMMAND 2>/dev/null || true)"
if [[ "$__tabterm_prompt_decl" == declare\ -a* || "$__tabterm_prompt_decl" == declare\ -ax* ]]; then
  PROMPT_COMMAND=(_tabterm_prompt_command "${PROMPT_COMMAND[@]}")
  PROMPT_COMMAND+=("_tabterm_prompt_ready")
elif [[ -n "${PROMPT_COMMAND:-}" ]]; then
  PROMPT_COMMAND="_tabterm_prompt_command; ${PROMPT_COMMAND}; _tabterm_prompt_ready"
else
  PROMPT_COMMAND="_tabterm_prompt_command; _tabterm_prompt_ready"
fi
unset __tabterm_prompt_decl

trap '_tabterm_preexec "$BASH_COMMAND"' DEBUG
