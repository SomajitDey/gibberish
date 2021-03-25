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
  export write_lock="${GIBBERISH_DIR}/write.lock"
  export commit_lock="${GIBBERISH_DIR}/commit.lock"
  export checkout_lock="${GIBBERISH_DIR}/checkout.lock"
  if [[ "${GIBBERISH}" == "server" ]]; then
    export pidfile="${GIBBERISH_DIR}/pid"
    export ttyfile="${GIBBERISH_DIR}/tty"
  fi
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
        # Update worktree only
        git restore --quiet --source="${commit}" --worktree -- "./${iofile}"
        cat "./${iofile}" > "${incoming}" # TODO: Should be gpg instead of cat; This is blocking
      else
        # To show results to localhost, redirect stdout and stderr to fd 3 as: command &>&3
        # Otherwise, the results would be pushed
        bash  <(git log -1 --pretty=%B "${commit}") 3>"${incoming}" &> >(GIBBERISH_write)
      fi
      git tag -d last_read &>/dev/null && git tag last_read "${commit}"
    done
  }
  export -f checkout
  
  fetch(){
    while true;do
      sleep 1 # This is just to factor in network latency
      git fetch --quiet origin "${fetch_branch}" || continue
      git diff --quiet HEAD FETCH_HEAD && continue
      # git-reset doesn't touch worktree, hence doesn't conflict with ongoing checkout function unlike git-merge
      git reset --mixed --quiet FETCH_HEAD
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
      flock -x "${write_lock}" -c 'echo "${line}" >> "${outgoing}"'
    else
      # Failure means there are still characters to be read. Hence no trailing newline
      [[ -z "${line}" ]] && continue
      flock -x "${write_lock}" -c 'echo -n "${line}" >> "${outgoing}"'
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

# Sync:

  cd "${incoming_dir}" || { echo 'Broken installation. Rerun installer' >&2 ; exit 1;}
  git pull --ff-only --no-verify --quiet origin "${fetch_branch}" || \
    { echo "Pull failed: ${incoming_dir}" >&2 ; exit 1;}
  until git tag last_read &>/dev/null; do git tag -d last_read &>/dev/null; done
  cd ~-

  cd "${outgoing_dir}" || { echo 'Broken installation. Rerun installer' >&2 ; exit 1;}
  git pull --ff-only --no-verify --quiet origin "${push_branch}" || \
    { echo "Pull failed: ${outgoing_dir}" >&2 ; exit 1;}
  cd "${OLDPWD}"

  mkfifo "${incoming}" || { echo 'Pipe exists: May be another session running' >&2 ; exit 1;}
  touch "${commit_lock}"
  touch "${checkout_lock}"
  touch "${write_lock}"
}
export -f GIBBERISH_prelaunch

gibberish-server(){
  echo "To kill me, execute from another terminal: kill -KILL -${BASHPID}"
  export fetch_branch="server"
  export push_branch="client"
  GIBBERISH_filesys

  (
  GIBBERISH_prelaunch

  GIBBERISH_fetchd
  
  export PROMPT_COMMAND='tty=$(tty); echo ${tty//\/dev\//} > $ttyfile; echo $$ > $pidfile'
  export PS0="$(tput cuu1 ; tput ed)"
# If client sends exit or logout, new shell launches 
  cd
  while true; do
    bash -i
  done < <(GIBBERISH_read) |& GIBBERISH_write
  )
  rm "${incoming}"
  echo 'Server killed'
}
export -f gibberish-server

gibberish(){
  export fetch_branch="client"
  export push_branch="server"
  GIBBERISH_filesys

  (
  GIBBERISH_prelaunch

  trap 'rm "${incoming}"; kill -9 "-${BASHPID}"' exit
  
  GIBBERISH_fetchd
  (GIBBERISH_read &) # Sub-shell is invoked so that pid of bg job is not shown in tty

  echo 'echo "Welcome to GIBBERISH-server"' > "${outgoing}"
  flock -x "${commit_lock}" -c GIBBERISH_commit &
  local cmd
  while read -re cmd ; do
    [[ -z "${cmd}" ]] && continue
    flock -x "${write_lock}" echo "${cmd}" >> "${outgoing}"
    flock -x "${commit_lock}" -c GIBBERISH_commit &
  done
  )
}
export -f gibberish
