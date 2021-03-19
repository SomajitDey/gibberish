export GBRS_DIR="${GBRS_DIR:="${HOME}/.GiBaReSh"}"

GBRS_filesys(){
  export incoming_dir="${GBRS_DIR}/incoming"
  export outgoing_dir="${GBRS_DIR}/outgoing"
  export GIT_DIR="${GBRS_DIR}/.git"
  export iofile="io.txt"
  export hook="post-checkout" # Actual hook is a symbolic link to this
  export interface="${GBRS_DIR}/interface.txt"
}
export -f GBRS_filesys

GBRS_fetchd(){
  cd "${incoming_dir}"
  while true;do
    git fetch --quiet origin "${fetch_branch}"
  done
}
export -f GBRS_fetchd

GBRS_checkoutd(){
  cd "${incoming_dir}"
  [[ -e "./${hook}" ]] && ln -sf "./${hook}" "${GIT_DIR}/hooks/post-checkout"
  local commit
  while true;do
    for commit in "$(git rev-list HEAD..origin/${fetch_branch})"; do
      git reset --hard --quiet "${commit}" # Rest is done by post-checkout hook
      patch "${interface}" <(diff --new-file "${interface}" "./${iofile}")
    done
  done
}
export -f GBRS_checkoutd

GBRS_commit(){
  (
    cd "${outgoing_dir}"
    git add --all
    git commit --quiet --allow-empty --allow-empty-message -m ''
  )
}
export -f GBRS_commit

gbrsd(){
  GBRS_filesys
  export fetch_branch="client"
  export push_branch="server"

  GBRS_fetchd &
  GBRS_checkoutd &
  
  trap GBRS_commit CHLD
  bash -i < <(tail -F "${interface}" 2>/dev/null) &>>"${outgoing_dir}/${iofile}"
}
export -f gbrsd

gbrs(){
  GBRS_filesys
  export fetch_branch="server"
  export push_branch="client"

  GBRS_fetchd &
  GBRS_checkoutd &
  
  tail -F "${interface}" 2>/dev/null &

  echo_command(){ 
    local command="${1}"
    local erase_length="${#command}"; local i
    for i in "$(seq ${erase_length})"; do
      echo -ne "\b$(tput ech 1)"
    done
    echo "${2:="${command}"}"
  }
  export -f echo_command

  (
    while true; do
      read -e
      echo_command "${REPLY}"
      GBRS_commit
    done
  )>>"${outgoing_dir}/${iofile}"  
}
