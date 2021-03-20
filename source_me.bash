export GBRS_DIR="${GBRS_DIR:="${HOME}/.gibberish"}"

GBRS_filesys(){
  export incoming_dir="${GBRS_DIR}/incoming"
  export outgoing_dir="${GBRS_DIR}/outgoing"
  export git_dir="${GBRS_DIR}/.git"
  export iofile="io.txt"
  export hook="script.bash"
  export incoming="${GBRS_DIR}/incoming.txt"
  export outgoing="${GBRS_DIR}/outgoing.txt"
  export push_lock="${GBRS_DIR}/push.lock"
  export write_lock="${GBRS_DIR}/write.lock"
  export commit_lock="${GBRS_DIR}/commit.lock"
  export checkout_lock="${GBRS_DIR}/checkout.lock"

  mkdir -p "${GBRS_DIR}"

  touch "${incoming}"
  touch "${push_lock}"
  touch "${commit_lock}"
  touch "${checkout_lock}"
  touch "${write_lock}"
}
export -f GBRS_filesys

GBRS_fetchd(){  
  (
  cd "${incoming_dir}"

  checkout(){
    local commit
    while true;do
      for commit in "$(git rev-list HEAD..FETCH_HEAD)"; do
        git reset --hard --quiet "${commit}"
        mv -f "./${iofile}" "${incoming}"
        [[ -f "./${hook}" ]] && bash "./${hook}"
      done
    done;}

  fetch(){
    while true;do
      git fetch --quiet origin "${fetch_branch}" && \
      flock -x "${checkout_lock}" checkout &
    done;}

  fetch &
  )
}
export -f GBRS_fetchd

GBRS_commit(){
  (
  cd "${outgoing_dir}"
  flock -x "${write_lock}" mv -f "${outgoing}" "./${iofile}"
  git add --all
  git commit --quiet --no-verify --allow-empty-message -m '' 2>/dev/null
  )
}
export -f GBRS_commit

GBRS_write(){
# Append to path=$outgoing even if it is moved/unlinked anytime
  while IFS= read -r; do
    flock -x "${write_lock}" echo "${REPLY}" >> "${outgoing}"
    flock -x "${commit_lock}" GBRS_commit &
  done
}
export -f GBRS_write

GBRS_read(){ tail -n+1 -F "${incoming}" 2>/dev/null;}
export -f GBRS_read

gbrsd(){
  GBRS_filesys
  export fetch_branch="server"
  export push_branch="client"

  GBRS_fetchd
  
  bash -i < <(GBRS_read) &> >(GBRS_write)
}
export -f gbrsd

gbrs(){
  GBRS_filesys
  export fetch_branch="client"
  export push_branch="server"

  GBRS_fetchd &
  GBRS_read &

  while read -re; do
    (tput cuu1; tput el1; tput el)>/dev/tty
    echo "${REPLY}"
  done | GBRS_write
}
