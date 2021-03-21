export GIBBERISH_DIR="${GIBBERISH_DIR:="${HOME}/.gibberish"}"

GIBBERISH_filesys(){
  export incoming_dir="${GIBBERISH_DIR}/incoming"
  export outgoing_dir="${GIBBERISH_DIR}/outgoing"
  export iofile="io.txt"
  export incoming="${GIBBERISH_DIR}/incoming.fifo"
  export outgoing="${GIBBERISH_DIR}/outgoing.txt"
  export push_lock="${GIBBERISH_DIR}/push.lock"
  export write_lock="${GIBBERISH_DIR}/write.lock"
  export commit_lock="${GIBBERISH_DIR}/commit.lock"
  export checkout_lock="${GIBBERISH_DIR}/checkout.lock"
}
export -f GIBBERISH_filesys

GIBBERISH_fetchd(){  
  (
  cd "${incoming_dir}"

  checkout(){
    local commit
    for commit in $(git rev-list last_read.."${fetch_branch}" 2>/dev/null); do
      # Executable code (hook) can be passed through commit message file. Use-case: ping; file-transfer
      # Code for such special commit: git commit --allow-empty -F script.bash
      # Commit message should be an empty string otherwise
      if [[ -z "$(git log -1 --pretty=%B "${commit}")" ]]; then
        git restore --quiet --source="${commit}" "./${iofile}"
        cat "./${iofile}" > "${incoming}" # TODO: Should be gpg instead of cat; This is blocking
      else  
        bash  <(git log -1 --pretty=%B "${commit}") &> >(GIBBERISH_write) &
      fi
    done
    if [[ -z "${commit}" ]]; then return 1 ; fi
    git tag -d last_read &>/dev/null; git tag last_read "${commit}"; }
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
  git commit --no-verify --no-gpg-sign --allow-empty-message -m '' &>/dev/null
  )
}
export -f GIBBERISH_commit

GIBBERISH_hook_commit(){
# Usage: GIBBERISH_hook_commit -m <command string to be passed to bash>
# Usage: GIBBERISH_hook_commit -F <bash script path>
  (cd "${outgoing_dir}"
  flock -x 200 ; git commit --no-verify --no-gpg-sign --allow-empty $@
  ) 200>"${commit_lock}"
}
export -f GIBBERISH_hook_commit

GIBBERISH_write(){
# Append to path=$outgoing even if it is moved/unlinked anytime
  local line
  while IFS= read -r line; do
    flock -x "${write_lock}" echo "${line}" >> "${outgoing}"
    flock -x "${commit_lock}" -c GIBBERISH_commit &
  done
}
export -f GIBBERISH_write

GIBBERISH_read(){
# We could have used tail -n+1 -F "${incoming}" 2>/dev/null;
# With incoming being a text file instead of fifo
# tail -f however would be polling the file, hence busy wait, which is undesirable
  while cat "${incoming}"; do : ; done # : implies no-op
}
export -f GIBBERISH_read

GIBBERISH_prelaunch(){
  GIBBERISH_filesys

  cd "${incoming_dir}"
  git pull --ff-only --no-verify --quiet origin "${fetch_branch}" || \
    { echo 'Pull failed' >&2 ; return 1;}
  until git tag last_read &>/dev/null; do git tag -d last_read &>/dev/null; done
  cd "${OLDPWD}"
  
  mkfifo "${incoming}" || { echo 'Pipe exists: May be another session running' >&2 ; return 1;}
  touch "${push_lock}"
  touch "${commit_lock}"
  touch "${checkout_lock}"
  touch "${write_lock}"
}
export -f GIBBERISH_prelaunch

gibberish-server(){
  export fetch_branch="server"
  export push_branch="client"
  GIBBERISH_prelaunch

  GIBBERISH_fetchd
  
# If client sends exit or logout, new shell launches 
  while true; do
    bash -i < <(GIBBERISH_read) &> >(GIBBERISH_write)
  done
}
export -f gibberish-server

gibberish(){
  export fetch_branch="client"
  export push_branch="server"
  GIBBERISH_prelaunch

  trap 'rm "${incoming}"; kill -9 -$$' return exit
  
  GIBBERISH_fetchd
  (GIBBERISH_read &) # Sub-shell is invoked so that pid of bg job is not shown in tty

  local cmd
  while read -re cmd ; do
    [[ -z "${cmd}" ]] && continue
    (tput cuu1; tput el1; tput el)>/dev/tty
    echo "${cmd}"
  done | GIBBERISH_write
}
export -f gibberish
