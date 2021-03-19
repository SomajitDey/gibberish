export GBRS_dir="${HOME}/.GiBaReSh"

GBRS_filesys(){
  export GBRS_client_dir="${GBRS_dir}/client"
  export GBRS_server_dir="${GBRS_dir}/server"
  export GBRS_GIT_DIR="${GBRS_dir}/.git"
  export GBRS_GIT_INDEX_FILE=".index"
  export GBRS_iofile="io.txt"
  export GBRS_hook="post-checkout" # Actual hook is a symbolic link to this
  export GBRS_interface="${GBRS_dir}/interface.txt"
}
export -f GBRS_filesys

GBRS_fetchd(){
  export GIT_DIR="${GBRS_GIT_DIR}"
  local branch="${1}"
  while true;do
    git fetch --quiet --negotiation-tip=FETCH_HEAD origin "${branch}"
  done
}
export -f GBRS_fetchd

GBRS_checkoutd(){
  local loop="true"
  trap 'loop="false"' TERM
  export GIT_WORK_TREE="${GBRS_dir}/${1}"; export GIT_DIR="${GBRS_GIT_DIR}"
  export GIT_INDEX_FILE="${GBRS_GIT_INDEX_FILE}"
  ln -s "${GIT_WORK_TREE}/${GBRS_hook}" "${GIT_DIR}/hooks/post-checkout"
  
  local commit
  while [[ "${loop}"=="true" ]] ; do
    for commit in "$(git rev-list HEAD..FETCH_HEAD)"; do
      git checkout --quiet "${commit}" # Rest is done by post-checkout hook
      patch "${GBRS_interface}" \
        <(diff --force --new-file "${GBRS_interface}" "${GIT_WORK_TREE}/${GBRS_iofile}")
    done
  done
}
export -f GBRS_checkoutd

GBRS_commit(){
  export GIT_WORK_TREE="${GBRS_dir}/${1}"; export GIT_DIR="${GBRS_GIT_DIR}"  
  git add --all; git commit -m ':-)'
}
export -f GBRS_commit

gbrsd(){
  GBRS_filesys
  GBRS_fetchd "server" & local fetchd_pid="$!"
  GBRS_checkoutd "server" & local checkoutd_pid="$!"
  trap 'kill "${fetchd_pid}" "${checkoutd_pid}"; return' TERM
  
  trap 'GBRS_commit "client"' CHLD
  bash -i < <(tail -F "${GBRS_interface}" 2>/dev/null) \
    &>>"${GBRS_client_dir}/${GBRS_iofile}"
}
export -f gbrsd

gbrs(){
  GBRS_filesys
  GBRS_fetchd "client" & local fetchd_pid="$!"
  GBRS_checkoutd "client" & local checkoutd_pid="$!"
  trap 'kill "${fetchd_pid}" "${checkoutd_pid}"' return
  
  tail -F "${GBRS_interface}" 2>/dev/null &

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
      GBRS_commit "server"
    done
  )>>"${GBRS_server_dir}/${GBRS_iofile}"
  
}
