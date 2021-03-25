# TODO: sleep <delay> to mimic latency in pull & push during testing on localhost 
# TODO: logs, understand bg processes, server should run in bg?
# TODO: Trap and Relay all signals SIGTSTP, SIGHUP etc. to incoming as kill -SIG -$$ 
# TODO: EOF | gpg -c | EOF
# TODO: prune unnecessities, github doesnt support large commits messages. So no commit msg file only string
# TODO: brb, hey, abort
# TODO: take and give remote_path local_path >> homebuild - stream DL, pipe, read -st, tail -F, find --delete, nc; ncat @ sdf.org
# TODO: Decide on git tag

GIBBERISH_filesys(){
  export GIBBERISH_DIR="${HOME}/.gibberish/${GIBBERISH}"
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
        # To show results to localhost, redirect stdout and stderr to fd 3 as: command &>&3
        # Otherwise, the results would be pushed
        bash  <(git log -1 --pretty=%B "${commit}") 3>"${incoming}" &> >(GIBBERISH_write) &
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
  git add  "./${iofile}"
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
# This function dumps the input stream to $outgoing even if the path gets unlinked.
  local timeout="1" # Interval for polling
  local buffer="5000" # Something ridiculously big, such that nothing can write this no. of characters within $timeout seconds
  declare -x line
  while :; do
    IFS= read -r -n "${buffer}" -t "${timeout}" line
    if [[ $? == 0 ]]; then
      # Timed readline success implies input ends with a newline (default delimiter)
      flock "${write_lock}" -c 'echo "${line}" >> "${outgoing}"'
    else
      # Failure means there are still characters to be read. Hence no trailing newline
      [[ -z "${line}" ]] && continue
      flock "${write_lock}" -c 'echo -n "${line}" >> "${outgoing}"'
    fi
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
  [[ "${GIBBERISH}" == "${fetch_branch}" ]] || { echo "Cannot run for GIBBERISH=${GIBBERISH}" >&2 ; exit 1;}
  GIBBERISH_filesys

  cd "${incoming_dir}" || { echo 'Broken installation. Rerun installer' >&2 ; exit 1;}
  git pull --ff-only --no-verify --quiet origin "${fetch_branch}" || \
    { echo 'Pull failed' >&2 ; exit 1;}

# Consider:  if ! git show -s --pretty= last_read 2>/dev/null; then git tag last_read; fi
  until git tag last_read &>/dev/null; do git tag -d last_read &>/dev/null; done
  cd "${OLDPWD}"
  
  mkfifo "${incoming}" || { echo 'Pipe exists: May be another session running' >&2 ; exit 1;}
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
  
  export PS0="$(tput cuu1 ; tput ed)"
# If client sends exit or logout, new shell launches 
  while true; do
    bash -i < <(GIBBERISH_read) |& GIBBERISH_write
  done
}
export -f gibberish-server

gibberish(){
  export fetch_branch="client"
  export push_branch="server"
  GIBBERISH_prelaunch

  (
  trap 'rm "${incoming}"; kill -9 -"${BASHPID}"' exit
  
  GIBBERISH_fetchd
  (GIBBERISH_read &) # Sub-shell is invoked so that pid of bg job is not shown in tty

  echo 'echo "Welcome to GIBBERISH-server"' >> "${outgoing}"
  local cmd
  while read -re cmd ; do
    [[ -z "${cmd}" ]] && continue
    flock -x "${write_lock}" echo "${cmd}" >> "${outgoing}"
    flock -x "${commit_lock}" -c GIBBERISH_commit &
  done
  )
}
export -f gibberish
