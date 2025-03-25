# Colors
USER_COLOR="%F{yellow}"
AT_COLOR="%F{250}"
HOST_COLOR="%F{yellow}"
DIR_COLOR="%F{green}"
GIT_COLOR="%F{blue}"
STAT_COLOR="%F{magenta}"
SSH_COLOR="%F{blue}"
CMD_COLOR="%F{green}"
RESET="%f"
reset=$'\e[0m'

# Detect SSH
if [[ -n "$SSH_CONNECTION" ]]; then
  SSH_PREFIX="%{$SSH_COLOR%}SSH%{$RESET%} "
else
  SSH_PREFIX=""
fi

HL_BASE_STYLE=""
HL_LAYOUT_STYLE=""
HL_GIT_COUNT_MODE='off'
HL_GIT_SEP_SYMBOL=''

# Order of statuses
declare -a HL_GIT_STATUS_ORDER=(
  STAGED CHANGED UNTRACKED BEHIND AHEAD DIVERGED STASHED CONFLICTS CLEAN
)

# Symbol for each status
declare -A HL_GIT_STATUS_SYMBOLS=(
  STAGED    '+'
  CHANGED   '!'
  UNTRACKED '?'
  BEHIND    '↓'
  AHEAD     '↑'
  DIVERGED  '↕'
  STASHED   '*'
  CONFLICTS '✘' # consider "%{$red%}✘"
  CLEAN     '' # consider '✓' or "%{$green%}✔"
)

headline-git() {
  # TODO is this necessary?
  GIT_OPTIONAL_LOCKS=0 command git "$@"
}

headline-git-branch() {
  local ref
  ref=$(headline-git symbolic-ref --quiet HEAD 2> /dev/null)
  local err=$?
  if [[ $err == 0 ]]; then
    echo ${ref#refs/heads/} # remove "refs/heads/" to get branch
  else # not on a branch
    [[ $err == 128 ]] && return  # not a git repo
    ref=$(headline-git rev-parse --short HEAD 2> /dev/null) || return
    echo ":${ref}" # hash prefixed to distingush from branch
  fi
}

# Get the quantity of each git status
headline-git-status-counts() {
  local -A counts=(
    'STAGED' 0 # staged changes
    'CHANGED' 0 # unstaged changes
    'UNTRACKED' 0 # untracked files
    'BEHIND' 0 # commits behind
    'AHEAD' 0 # commits ahead
    'DIVERGED' 0 # commits diverged
    'STASHED' 0 # stashed files
    'CONFLICTS' 0 # conflicted files
    'CLEAN' 1 # clean branch 1=true 0=false
  )

  # Retrieve status
  local raw lines
  raw="$(headline-git status --porcelain -b 2> /dev/null)"
  if [[ $? == 128 ]]; then
    return 1 # catastrophic failure, abort
  fi
  lines=(${(@f)raw})

  # Process tracking line
  if [[ ${lines[1]} =~ '^## [^ ]+ \[(.*)\]' ]]; then
    local items=("${(@s/,/)match}")
    for item in $items; do
      if [[ $item =~ '(behind|ahead|diverged) ([0-9]+)?' ]]; then
        case $match[1] in
          'behind') counts[BEHIND]=$match[2];;
          'ahead') counts[AHEAD]=$match[2];;
          'diverged') counts[DIVERGED]=$match[2];;
        esac
      fi
    done
  fi

  # Process status lines
  for line in $lines; do
    if [[ $line =~ '^##|^!!' ]]; then
      continue
    elif [[ $line =~ '^U[ADU]|^[AD]U|^AA|^DD' ]]; then
      counts[CONFLICTS]=$(( ${counts[CONFLICTS]} + 1 ))
    elif [[ $line =~ '^\?\?' ]]; then
      counts[UNTRACKED]=$(( ${counts[UNTRACKED]} + 1 ))
    elif [[ $line =~ '^[MTADRC] ' ]]; then
      counts[STAGED]=$(( ${counts[STAGED]} + 1 ))
    elif [[ $line =~ '^[MTARC][MTD]' ]]; then
      counts[STAGED]=$(( ${counts[STAGED]} + 1 ))
      counts[CHANGED]=$(( ${counts[CHANGED]} + 1 ))
    elif [[ $line =~ '^ [MTADRC]' ]]; then
      counts[CHANGED]=$(( ${counts[CHANGED]} + 1 ))
    fi
  done

  # Check for stashes
  if $(headline-git rev-parse --verify refs/stash &> /dev/null); then
    counts[STASHED]=$(headline-git rev-list --walk-reflogs --count refs/stash 2> /dev/null)
  fi

  # Update clean flag
  for key val in ${(@kv)counts}; do
    [[ $key == 'CLEAN' ]] && continue
    (( $val > 0 )) && counts[CLEAN]=0
  done

  echo ${(@kv)counts} # key1 val1 key2 val2 ...
}

# Get git status
headline-git-status() {
  local parts=( ${(ps:$HL_TEMPLATE_TOKEN:)HL_CONTENT_TEMPLATE[STATUS]} ) # split on template token
  local style=${${parts[1]##*%\{}%%%\}*} # regex for "%{...%}"
  local -A counts=( $(headline-git-status-counts) )
  (( ${#counts} == 0 )) && return # not a git repo
  local result=''
  for key in $HL_GIT_STATUS_ORDER; do
    if (( ${counts[$key]} > 0 )); then
      if (( ${#HL_GIT_SEP_SYMBOL} != 0 && ${#result} != 0 )); then
        result+="%{$reset%}$HL_BASE_STYLE$HL_LAYOUT_STYLE$HL_GIT_SEP_SYMBOL%{$reset%}$HL_BASE_STYLE%{$style%}"
      fi
      if [[ $key != 'CLEAN' && $HL_GIT_COUNT_MODE == 'on' || ( $HL_GIT_COUNT_MODE == 'auto' && ${counts[$key]} != 1 ) ]]; then
        result+="${counts[$key]}${HL_GIT_STATUS_SYMBOLS[$key]}"
      else
        result+="${HL_GIT_STATUS_SYMBOLS[$key]}"
      fi
    fi
  done
  echo $result
}

function get_space {
    local str=$1$2
    local zero='%([BSUbfksu]|([FB]|){*})'
    local len=${#${(S%%)str//$~zero/}}
    local size=$(( $COLUMNS - $len - 1 ))
    local space=""
    while [[ $size -gt 0 ]]; do
        space="$space "
        let size=$size-1
    done
    echo $space
}

function get_prompt_header {
    local left_prompt="\
%B${SSH_PREFIX}\
%{$USER_COLOR%}%n%{$RESET%}\
%{$AT_COLOR%}@%b%{$RESET%}\
%{$HOST_COLOR%}%m%{$RESET%} %B%{$DIR_COLOR%}%~%{$RESET%} "
    local right_prompt="%{$GIT_COLOR%}$(headline-git-branch)%{$RESET%}\
    %{$STAT_COLOR%}$(headline-git-status)%{$RESET%} "
    echo "$left_prompt$(get_space $left_prompt $right_prompt)$right_prompt"
}

PROMPT='
$(get_prompt_header)
%{$CMD_COLOR%}-> %{$RESET%}'
RPROMPT='%F{239}$(git_prompt_short_sha)%f '
