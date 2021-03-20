export GBRS_DIR="${GBRS_DIR:="${HOME}/.gibberish"}"

GBRS_filesys(){
  export incoming_dir="${GBRS_DIR}/incoming"
  export outgoing_dir="${GBRS_DIR}/outgoing"
  export git_dir="${GBRS_DIR}/.git"
  export iofile="io.txt"
  export hook="script.bash"
  export interface="${GBRS_DIR}/interface.txt"
}
export -f GBRS_filesys

GBRS_listend(){  
(
  cd "${incoming_dir}"
  until git fetch --quiet origin "${fetch_branch}"; do
  done

  fetchd(){
    while true;do
      git fetch --quiet origin "${fetch_branch}"
    done
  }

  checkoutd(){
    local commit
    while true;do
      for commit in "$(git rev-list HEAD..FETCH_HEAD)"; do
        git reset --hard --quiet "${commit}"
        patch "${interface}" <(diff --new-file "${interface}" "./${iofile}")
        [[ -f "./${hook}" ]] && bash "./${hook}"
      done
    done
  }

  fetchd &
  checkoutd &
)
}
export -f GBRS_listend

GBRS_commit(){
  (
    cd "${outgoing_dir}"
    git add --all
    git commit --quiet --no-verify --allow-empty --allow-empty-message -m ''
  )
}
export -f GBRS_commit

gbrsd(){
  GBRS_filesys
  export fetch_branch="server"
  export push_branch="client"

  GBRS_listend &
  
  trap GBRS_commit CHLD
  bash -i < <(tail -F "${interface}" 2>/dev/null) &>>"${outgoing_dir}/${iofile}"
}
export -f gbrsd

gbrs(){
  GBRS_filesys
  export fetch_branch="client"
  export push_branch="server"

  GBRS_listend &
  
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
