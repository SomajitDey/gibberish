export GIBBERISH_DIR="${GIBBERISH_DIR:="${HOME}/.gibberish"}"

GIBBERISH_filesys(){
  export incoming_dir="${GIBBERISH_DIR}/incoming"
  export outgoing_dir="${GIBBERISH_DIR}/outgoing"
  export git_dir="${GIBBERISH_DIR}/.git"
  export iofile="io.txt"
  export hook="script.bash"
  export incoming="${GIBBERISH_DIR}/incoming.txt"
  export outgoing="${GIBBERISH_DIR}/outgoing.txt"
  export push_lock="${GIBBERISH_DIR}/push.lock"
  export write_lock="${GIBBERISH_DIR}/write.lock"
  export commit_lock="${GIBBERISH_DIR}/commit.lock"
  export checkout_lock="${GIBBERISH_DIR}/checkout.lock"

  mkdir -p "${GIBBERISH_DIR}"

  touch "${incoming}"
  touch "${push_lock}"
  touch "${commit_lock}"
  touch "${checkout_lock}"
  touch "${write_lock}"
}
export -f GIBBERISH_filesys

GIBBERISH_fetchd(){  
  (
  cd "${incoming_dir}"

  checkout(){
    local commit
    for commit in $(git rev-list last_read.."${fetch_branch}"); do
      git restore --quiet --source="${commit}" .
      mv -f "./${iofile}" "${incoming}" &>/dev/null
      [[ -f "./${hook}" ]] && bash "./${hook}"
    done
    git tag -d last_read; git tag last_read "${commit}"; }
   export -f checkout
  
  fetch(){
    while true;do
      git pull --ff-only --no-verify --quiet origin "${fetch_branch}" || continue
      flock -x "${checkout_lock}" -c checkout &
    done;}

  fetch &
  )
}
export -f GIBBERISH_fetchd

GIBBERISH_commit(){
  (
  cd "${outgoing_dir}"
  flock -x "${write_lock}" mv -f "${outgoing}" "./${iofile}" &>/dev/null
  git add --all
  git commit --no-verify --no-gpg-sign -m ':)' &>/dev/null
  )
}
export -f GIBBERISH_commit

GIBBERISH_write(){
# Append to path=$outgoing even if it is moved/unlinked anytime
  while IFS= read -r; do
    flock -x "${write_lock}" echo "${REPLY}" >> "${outgoing}"
    flock -x "${commit_lock}" -c GIBBERISH_commit &
  done
}
export -f GIBBERISH_write

GIBBERISH_read(){ tail -n+1 -F "${incoming}" 2>/dev/null;}
export -f GIBBERISH_read

gibberish-server(){
  GIBBERISH_filesys
  export fetch_branch="server"
  export push_branch="client"

  GIBBERISH_fetchd
  
  bash -i < <(GIBBERISH_read) &> >(GIBBERISH_write)
}
export -f gibberish-server

gibberish(){
  GIBBERISH_filesys
  export fetch_branch="client"
  export push_branch="server"

  GIBBERISH_fetchd
  (GIBBERISH_read &)

  while read -re; do
    (tput cuu1; tput el1; tput el)>/dev/tty
    echo "${REPLY}"
  done | GIBBERISH_write
}
export -f gibberish
