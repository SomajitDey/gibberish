export GBRS_DIR="${GBRS_DIR:="${HOME}/.gibberish"}"

GBRS_filesys(){
  export incoming_dir="${GBRS_DIR}/incoming"
  export outgoing_dir="${GBRS_DIR}/outgoing"
  export git_dir="${GBRS_DIR}/.git"
  export iofile="io.txt"
  export hook="script.bash"
  export incoming="${GBRS_DIR}/incoming.txt"
  export outgoing="${GBRS_DIR}/outgoing.txt"
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
        mv -f "./${iofile}" "${incoming}"
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
    mv -f "${outgoing}" "./${iofile}"
    git add --all
    git commit --quiet --no-verify --allow-empty --allow-empty-message -m ''
  )
}
export -f GBRS_commit

GBRS_appendto(){
# Follow and append input to filepath given as parameter
(
  IFS=
  while read -r; do
    echo "${REPLY}" >> "${outgoing}"
    GBRS_commit
  done
)
}
export -f GBRS_appendto

gbrsd(){
  GBRS_filesys
  export fetch_branch="server"
  export push_branch="client"

  GBRS_listend &
  
  bash -i < <(tail -n+1 -F "${incoming}" 2>/dev/null) &> >(GBRS_appendto)
}
export -f gbrsd

gbrs(){
  GBRS_filesys
  export fetch_branch="client"
  export push_branch="server"

  GBRS_listend &
  
  tail -n+1 -F "${incoming}" 2>/dev/null &

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
    while read -re; do
      echo_command "${REPLY}"
    done
  ) | GBRS_appendto  
}
