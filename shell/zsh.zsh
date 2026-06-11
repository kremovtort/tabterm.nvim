if [[ -n "${TABTERM_ZSH_INTEGRATION_LOADED:-}" ]]; then
  return 0
fi

typeset -g TABTERM_ZSH_INTEGRATION_LOADED=1
typeset -g TABTERM_SHELL_COMMAND_ACTIVE=0

autoload -Uz add-zsh-hook

_tabterm_emit_osc7() {
  printf '\033]7;file://%s%s\033\\' "${HOST:-${HOSTNAME:-}}" "$PWD"
}

_tabterm_set_title() {
  printf '\033]2;%s\033\\' "$1"
}

_tabterm_command_label() {
  local input="$1"
  local -a words
  local word
  local index=1
  local shell_name
  local result=""
  local first=1

  words=(${(z)input})
  shell_name=$(basename -- "${SHELL:-zsh}")

  while (( index <= $#words )); do
    word="${words[index]}"

    if [[ "$word" == *=* && "$word" != */* ]]; then
      (( index++ ))
      continue
    fi

    case "$word" in
      command|builtin|noglob|nocorrect|nohup|time)
        (( index++ ))
        continue
        ;;
      env)
        (( index++ ))
        while (( index <= $#words )); do
          word="${words[index]}"
          if [[ "$word" == -* ]]; then
            (( index++ ))
            continue
          fi
          if [[ "$word" == *=* && "$word" != */* ]]; then
            (( index++ ))
            continue
          fi
          break
        done
        continue
        ;;
      sudo|doas|nice)
        (( index++ ))
        while (( index <= $#words )); do
          word="${words[index]}"
          if [[ "$word" == -* ]]; then
            (( index++ ))
            continue
          fi
          if [[ "$word" == *=* && "$word" != */* ]]; then
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

  while (( index <= $#words )); do
    word="${words[index]}"
    if (( first )) && [[ "$word" == */* ]]; then
      word=$(basename -- "$word")
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
    print -r -- "$result"
    return
  fi

  print -r -- "$shell_name"
}

_tabterm_precmd() {
  local exit_code=$?
  local shell_name
  shell_name=$(basename -- "${SHELL:-zsh}")
  if (( TABTERM_SHELL_COMMAND_ACTIVE )); then
    printf '\033]133;D;%s\033\\' "$exit_code"
    TABTERM_SHELL_COMMAND_ACTIVE=0
  fi
  _tabterm_set_title "$shell_name"
  printf '\033]133;A\033\\'
  _tabterm_emit_osc7
}

_tabterm_preexec() {
  TABTERM_SHELL_COMMAND_ACTIVE=1
  _tabterm_set_title "$(_tabterm_command_label "$1")"
  printf '\033]133;B\033\\'
  printf '\033]133;C\033\\'
}

add-zsh-hook -d precmd _tabterm_precmd 2>/dev/null
add-zsh-hook -d preexec _tabterm_preexec 2>/dev/null
add-zsh-hook precmd _tabterm_precmd
add-zsh-hook preexec _tabterm_preexec
