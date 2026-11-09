#!/usr/bin/env bash
# PreToolUse hook for the issue-triage subagent (wired in its frontmatter).
# Enforces the agent's read-only contract: blocks any Bash command that could
# change the cluster, the repo or GitHub, write files, or print secrets, and
# blocks Read on secret files. Exit 2 blocks the call; stderr goes to the agent.
#
# Cluster CLIs (kubectl, helm, helmfile, talosctl, gh, git) are allowlisted by
# subcommand, so anything not listed is refused rather than assumed safe.
set -uo pipefail

INPUT=$(cat)
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')

SECRET_PATH_PATTERN='(^|/)(secrets?\.ya?ml|terraform\.tfvars|\.env|keys\.txt)$|kubeconfig|\.kube/config|talosconfig|talos/configs/|\.tfstate|\.sops\.'
SECRET_RESOURCE_PATTERN='(^|,)secrets?(/|,|$)'
TALOS_SECRET_RESOURCE_PATTERN='^(machineconfigs?|mcs?|.*secrets?)(/|$)'

KUBECTL_VALUE_FLAGS="-n --namespace --context --kubeconfig --cluster --user -s --server --as --token -l --selector -o --output -c --container --field-selector --request-timeout"
HELM_VALUE_FLAGS="-n --namespace --kube-context --kubeconfig"
HELMFILE_VALUE_FLAGS="-f --file -e --environment -l --selector --kube-context -n --namespace --state-values-set --state-values-file"
TALOSCTL_VALUE_FLAGS="-n --nodes -e --endpoints --talosconfig --context"
GH_VALUE_FLAGS="-R --repo"
GIT_VALUE_FLAGS="-C -c --git-dir --work-tree"

block() {
  echo "Blocked by issue-triage read-only hook: $1. Do not work around this; list it in the handoff as a proposed step for the user to approve." >&2
  exit 2
}

if [ "$TOOL_NAME" = "Read" ]; then
  FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')
  if [[ $FILE_PATH =~ $SECRET_PATH_PATTERN ]]; then
    block "reading secret file $FILE_PATH"
  fi
  exit 0
fi

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$COMMAND" ] && exit 0

# Redirects to files. Quoted strings are dropped first so jq/awk filters such
# as '.restartCount > 0' are not mistaken for redirects.
UNQUOTED=$(printf '%s' "$COMMAND" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")
while IFS= read -r TARGET; do
  [ -z "$TARGET" ] && continue
  case "$TARGET" in
    /dev/null|/dev/stdout|/dev/stderr) ;;
    *) block "redirecting output to a file ($TARGET)" ;;
  esac
done < <(printf '%s' "$UNQUOTED" | grep -oE '>>?[[:space:]]*[^[:space:]&|;)>]+' | sed -E 's/^>>?[[:space:]]*//')

# Sets WORD/WORD_INDEX to the first non-flag token at or after index $1,
# skipping the value of any flag listed in $2.
next_word() {
  local INDEX=$1
  while [ "$INDEX" -lt "$TOKEN_COUNT" ]; do
    local TOKEN=${TOKENS[$INDEX]}
    case "$TOKEN" in
      -*=*) INDEX=$((INDEX + 1)) ;;
      -*)
        if [[ " $2 " == *" $TOKEN "* ]]; then INDEX=$((INDEX + 2)); else INDEX=$((INDEX + 1)); fi
        ;;
      *) WORD=$TOKEN; WORD_INDEX=$INDEX; return 0 ;;
    esac
  done
  WORD=""
  WORD_INDEX=$TOKEN_COUNT
  return 1
}

# True if any token from index $1 onward equals one of the words in $2.
has_token() {
  local INDEX
  for ((INDEX = $1; INDEX < TOKEN_COUNT; INDEX++)); do
    [[ " $2 " == *" ${TOKENS[$INDEX]} "* ]] && return 0
  done
  return 1
}

# Echoes the value of -o/--output from index $1 onward (empty if none).
output_format() {
  local INDEX
  for ((INDEX = $1; INDEX < TOKEN_COUNT; INDEX++)); do
    case "${TOKENS[$INDEX]}" in
      -o|--output) echo "${TOKENS[$((INDEX + 1))]:-}"; return ;;
      --output=*) echo "${TOKENS[$INDEX]#--output=}"; return ;;
      -o*) echo "${TOKENS[$INDEX]#-o}"; return ;;
    esac
  done
}

check_kubectl() {
  next_word $(($1 + 1)) "$KUBECTL_VALUE_FLAGS"
  local VERB=$WORD VERB_INDEX=$WORD_INDEX INDEX
  case "$VERB" in
    ""|describe|logs|top|events|explain|api-resources|api-versions|version|cluster-info|exec) ;;
    get)
      for ((INDEX = VERB_INDEX + 1; INDEX < TOKEN_COUNT; INDEX++)); do
        local TOKEN=${TOKENS[$INDEX]}
        [[ $TOKEN == /*secrets* ]] && block "reading Secrets through kubectl get --raw"
        if [[ $TOKEN =~ $SECRET_RESOURCE_PATTERN ]]; then
          case "$(output_format "$VERB_INDEX")" in
            ""|name|wide) ;;
            *) block "printing Secret data (use 'kubectl describe secret' to see key names only)" ;;
          esac
        fi
      done
      ;;
    auth)
      next_word $((VERB_INDEX + 1)) "$KUBECTL_VALUE_FLAGS"
      case "$WORD" in can-i|whoami) ;; *) block "kubectl auth $WORD" ;; esac
      ;;
    rollout)
      next_word $((VERB_INDEX + 1)) "$KUBECTL_VALUE_FLAGS"
      case "$WORD" in status|history) ;; *) block "kubectl rollout $WORD" ;; esac
      ;;
    config)
      next_word $((VERB_INDEX + 1)) "$KUBECTL_VALUE_FLAGS"
      case "$WORD" in current-context|get-contexts|get-clusters|view) ;; *) block "kubectl config $WORD" ;; esac
      has_token "$VERB_INDEX" "--raw --flatten" && block "printing kubeconfig credentials"
      ;;
    *) block "kubectl $VERB" ;;
  esac
}

check_helm() {
  next_word $(($1 + 1)) "$HELM_VALUE_FLAGS"
  local VERB=$WORD VERB_INDEX=$WORD_INDEX
  case "$VERB" in
    ""|list|ls|status|history|get|show|search|template|lint|version|env|diff) ;;
    repo|dependency|plugin)
      next_word $((VERB_INDEX + 1)) "$HELM_VALUE_FLAGS"
      case "$WORD" in list|ls|update) ;; *) block "helm $VERB $WORD" ;; esac
      ;;
    *) block "helm $VERB" ;;
  esac
}

check_helmfile() {
  next_word $(($1 + 1)) "$HELMFILE_VALUE_FLAGS"
  case "$WORD" in
    ""|diff|template|lint|list|build|status|version) ;;
    *) block "helmfile $WORD" ;;
  esac
}

check_talosctl() {
  next_word $(($1 + 1)) "$TALOSCTL_VALUE_FLAGS"
  local VERB=$WORD VERB_INDEX=$WORD_INDEX
  case "$VERB" in
    ""|dmesg|logs|services|service|version|health|disks|usage|list|ls|memory|processes|ps|stats|containers|events|netstat|mounts|time) ;;
    get)
      next_word $((VERB_INDEX + 1)) "$TALOSCTL_VALUE_FLAGS"
      local RESOURCE
      RESOURCE=$(printf '%s' "$WORD" | tr '[:upper:]' '[:lower:]')
      [[ $RESOURCE =~ $TALOS_SECRET_RESOURCE_PATTERN ]] && block "talosctl get $WORD (contains cluster CA and keys)"
      ;;
    *) block "talosctl $VERB" ;;
  esac
}

check_gh() {
  next_word $(($1 + 1)) "$GH_VALUE_FLAGS"
  local GROUP=$WORD GROUP_INDEX=$WORD_INDEX INDEX
  case "$GROUP" in
    ""|search|status) ;;
    auth)
      next_word $((GROUP_INDEX + 1)) "$GH_VALUE_FLAGS"
      [ "$WORD" = status ] || block "gh auth $WORD"
      ;;
    api)
      for ((INDEX = GROUP_INDEX + 1; INDEX < TOKEN_COUNT; INDEX++)); do
        local TOKEN=${TOKENS[$INDEX]} METHOD=""
        case "$TOKEN" in
          -X|--method) METHOD=${TOKENS[$((INDEX + 1))]:-} ;;
          --method=*) METHOD=${TOKEN#--method=} ;;
          -X*) METHOD=${TOKEN#-X} ;;
          -f|-F|--field|--raw-field|--input|-f*|-F*|--field=*|--raw-field=*|--input=*) block "gh api with request fields" ;;
        esac
        METHOD=$(printf '%s' "$METHOD" | tr '[:lower:]' '[:upper:]')
        case "$METHOD" in ""|GET) ;; *) block "gh api $METHOD" ;; esac
      done
      ;;
    issue|pr|run|release|label|repo|workflow|cache|gist|project|secret|variable|ruleset)
      next_word $((GROUP_INDEX + 1)) "$GH_VALUE_FLAGS"
      case "$WORD" in view|list|status|diff|checks) ;; *) block "gh $GROUP $WORD" ;; esac
      ;;
    *) block "gh $GROUP" ;;
  esac
}

check_git() {
  next_word $(($1 + 1)) "$GIT_VALUE_FLAGS"
  local VERB=$WORD VERB_INDEX=$WORD_INDEX INDEX
  case "$VERB" in
    ""|log|diff|show|blame|status|grep|ls-files|ls-tree|rev-parse|rev-list|cat-file|fetch|describe|shortlog) ;;
    remote)
      next_word $((VERB_INDEX + 1)) ""
      case "$WORD" in ""|show|get-url) ;; *) block "git remote $WORD" ;; esac
      ;;
    worktree)
      next_word $((VERB_INDEX + 1)) ""
      [ "$WORD" = list ] || block "git worktree $WORD"
      ;;
    config)
      has_token "$VERB_INDEX" "--get --get-all --get-regexp --list -l" || block "git config without --get/--list"
      ;;
    branch)
      has_token "$VERB_INDEX" "-d -D -m -M -c -C -f -u --delete --move --copy --force --set-upstream-to --unset-upstream --edit-description" && block "git branch modification"
      for ((INDEX = VERB_INDEX + 1; INDEX < TOKEN_COUNT; INDEX++)); do
        case "${TOKENS[$INDEX]}" in
          --contains|--no-contains|--merged|--no-merged|--points-at|--list|--format|--sort) INDEX=$((INDEX + 1)) ;;
          -*) ;;
          *) block "git branch creation" ;;
        esac
      done
      ;;
    *) block "git $VERB" ;;
  esac
}

check_curl() {
  local INDEX
  for ((INDEX = $1 + 1; INDEX < TOKEN_COUNT; INDEX++)); do
    local TOKEN=${TOKENS[$INDEX]} METHOD=""
    case "$TOKEN" in
      -X|--request) METHOD=${TOKENS[$((INDEX + 1))]:-} ;;
      --request=*) METHOD=${TOKEN#--request=} ;;
      -X*) METHOD=${TOKEN#-X} ;;
      -d|-d*|--data*|--json*|-F|-F*|--form*|-T|-T*|--upload-file*) block "curl request with a body" ;;
      -o|-o*|-O|--output*|--remote-name*) block "curl writing to a file" ;;
    esac
    METHOD=$(printf '%s' "$METHOD" | tr '[:lower:]' '[:upper:]')
    case "$METHOD" in ""|GET|HEAD) ;; *) block "curl $METHOD" ;; esac
  done
}

check_wget() {
  local SEGMENT_TEXT=" ${TOKENS[*]:$1} "
  case "$SEGMENT_TEXT" in
    *" --post-data"*|*" --post-file"*|*" --method"*|*" --body-"*) block "wget with a request body or method" ;;
  esac
  case "$SEGMENT_TEXT" in
    *" -O- "*|*" -qO- "*|*" -O - "*|*" --output-document=- "*|*" --spider "*) ;;
    *) block "wget writing to a file (use -qO-)" ;;
  esac
}

check_reader() {
  local INDEX
  for ((INDEX = $1 + 1; INDEX < TOKEN_COUNT; INDEX++)); do
    [[ ${TOKENS[$INDEX]} =~ $SECRET_PATH_PATTERN ]] && block "reading secret file ${TOKENS[$INDEX]}"
  done
}

check_segment() {
  read -ra TOKENS <<< "$1"
  TOKEN_COUNT=${#TOKENS[@]}
  local COMMAND_POSITION=1 INDEX
  for ((INDEX = 0; INDEX < TOKEN_COUNT; INDEX++)); do
    local TOKEN=${TOKENS[$INDEX]}
    # After '--' (kubectl exec) or '-c' (sh -c) a new command starts.
    if [ "$TOKEN" = "--" ] || [ "$TOKEN" = "-c" ]; then
      COMMAND_POSITION=1
      continue
    fi
    [ "$COMMAND_POSITION" -eq 1 ] || continue
    local NAME=${TOKEN##*/}
    case "$NAME" in
      *=*|-*|[0-9]*|sudo|xargs|nohup|nice|time|watch|timeout|exec|command|builtin|then|do|else|'!') continue ;;
      env|printenv)
        if [ "$NAME" = printenv ] || [ $((INDEX + 1)) -ge "$TOKEN_COUNT" ]; then
          printf '%s' "$COMMAND" | grep -qE 'cut -d ?=? ?-f ?1|cut -f ?1 -d ?=' \
            || block "listing environment values (pipe to 'cut -d= -f1' for names only)"
        fi
        continue
        ;;
      kubectl) check_kubectl "$INDEX" ;;
      helm) check_helm "$INDEX" ;;
      helmfile) check_helmfile "$INDEX" ;;
      talosctl) check_talosctl "$INDEX" ;;
      gh) check_gh "$INDEX" ;;
      git) check_git "$INDEX" ;;
      curl) check_curl "$INDEX" ;;
      wget) check_wget "$INDEX" ;;
      cat|head|tail|less|more|bat|grep|egrep|rg|awk|jq|yq|base64|strings|xxd|od) check_reader "$INDEX" ;;
      sed)
        has_token "$INDEX" "-i --in-place" && block "sed -i"
        for ((J = INDEX + 1; J < TOKEN_COUNT; J++)); do [[ ${TOKENS[$J]} == -i* ]] && block "sed -i"; done
        check_reader "$INDEX"
        ;;
      rm|rmdir|mv|cp|tee|touch|mkdir|chmod|chown|ln|dd|truncate|install|kill|pkill|killall|shutdown|reboot|eval|source|.|python|python3|ruby|node|perl|sops|age|terraform|az|ssh|scp|rsync|docker|kubectl-*)
        block "'$NAME' is not allowed"
        ;;
    esac
    COMMAND_POSITION=0
  done
}

# Split on shell separators (; | & ( ) ` { } and newlines) after removing
# quotes, so commands inside sh -c '...' and $(...) are checked too.
while IFS= read -r SEGMENT; do
  check_segment "$SEGMENT"
done < <(printf '%s\n' "$COMMAND" | tr -d "\"'\\\\" | tr ';|&()`{}' '\n')

exit 0
