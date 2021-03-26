# TODO: sleep <delay> to mimic latency in pull & push during testing on localhost 
# TODO: logs, understand bg processes, server should run in bg?
# TODO: Trap and Relay all signals SIGTSTP, SIGHUP etc. to incoming as kill -SIG -$$ 
# TODO: EOF | gpg -c | EOF
# TODO: prune unnecessities, github doesnt support large commits messages. So no commit msg file only string
# TODO: brb, hey, abort
# TODO: take and give remote_path local_path >> homebuild - stream DL, pipe, read -st, tail -F, find --delete, nc; ncat @ sdf.org
# TODO: Decide on git tag

GIBBERISH_filesys(){
  # Brief: Export important file definitions
  
  export GIBBERISH_DIR="${HOME}/.gibberish/${GIBBERISH}"
  export incoming_dir="${GIBBERISH_DIR}/incoming"
  export outgoing_dir="${GIBBERISH_DIR}/outgoing"
  export iofile="io.txt"
  export incoming="${GIBBERISH_DIR}/incoming.fifo"
  export outgoing="${GIBBERISH_DIR}/outgoing.txt"
  export write_lock="${GIBBERISH_DIR}/write.lock"
  export commit_lock="${GIBBERISH_DIR}/commit.lock"
  export checkout_lock="${GIBBERISH_DIR}/checkout.lock"
  export last_read_tag="${GIBBERISH_DIR}/last_read.tmp"
  export fetch_pid_file="${GIBBERISH_DIR}/fetch.pid"
  if [[ "${GIBBERISH}" == "server" ]]; then
    export ppidfile="${GIBBERISH_DIR}/ppid"
    export ttyfile="${GIBBERISH_DIR}/tty"
  fi
}; export -f GIBBERISH_filesys

GIBBERISH_fetchd(){  
  # Brief: Daemon to fetch commits; Reads and relays user input to interactive shell in server;
  # Reads and conveys server output to user in client. Any GPG decryption is done here.
 
  GIBBERISH_checkout(){
    # Brief: Update branch head. Read and relay user input. Decrypt as necessary. Execute hooks.

    cd "${incoming_dir}"

    git diff --quiet last_read FETCH_HEAD && return # No new commit to take care of

    # git-reset instead of git-merge or git-pull. This is because git-reset doesn't touch worktree
    # but updates the branch head and index only (--mixed option). Hence doesn't conflict with a 
    # restored worktree where git-merge would complain while trying to overwrite.
    # Note: we can use git-reset instead of merge only because our branch history is linear (--ff-only)
    git reset --mixed --quiet FETCH_HEAD # Or, replace FETCH_HEAD with "origin/${fetch_branch}"
    # Don't worry that FETCH_HEAD might be rewritten by GIBBERISH_fetch_loop when the above runs.
    # Network time taken by git-fetch makes this a non-issue.
    
    # Read new commits chronologically
    local commit
    for commit in $(git rev-list last_read.."${fetch_branch}"); do
      # Executable code (hook) can be passed through commit message.
      # Use-case: relay interrupt signals raised by user; file transfer in background.
      # Commit message should be an empty string otherwise
      commit_msg="$(git log -1 --pretty=%B "${commit}")"
      if [[ -z "${commit_msg}" ]]; then
        # When commit message is empty, update worktree only
        git restore --quiet --source="${commit}" --worktree -- "./${iofile}"
        
        # Any gpg decryption should be added here. cat is just a proxy for now
        cat "./${iofile}" > "${incoming}"
      else
        # Execute code supplied as commit message. This commit won't contain any other code
        # To show results to localhost, redirect stdout and stderr to fd 3 as: command &>&3
        # Otherwise, the results would be pushed
        eval "${commit_msg}" 3>"${incoming}" &> >(GIBBERISH_write)
      fi
      # Atomic tag update, such that there is always a last_read tag 
      echo "${commit}" > "${last_read_tag}"
      mv -f "${last_read_tag}" ".git/refs/tags/last_read"
    done
  }; export -f GIBBERISH_checkout
  
  GIBBERISH_fetch_loop(){
    # Brief: Iterative fetching from remote (origin)
    
    cd "${incoming_dir}"

    local loop=true; trap 'loop=false' INT TERM QUIT HUP
    while ${loop};do
      sleep 1 # This is just to model network latency. To be removed in release version

      git fetch --quiet origin "${fetch_branch}" || continue

      # Fetching is iterative - hence it can trigger checkout continuously. Thus, nonblock flock is ok
      flock --nonblock --no-fork "${checkout_lock}" -c GIBBERISH_checkout &
    done
    }; export -f GIBBERISH_fetch_loop

  GIBBERISH_fetch_loop & # Bg job in sub-shell means we don't have to worry about any 'cd' done therein
  echo ${!} > "${fetch_pid_file}"
}; export -f GIBBERISH_fetchd

GIBBERISH_commit(){
  # Corresponding push is handled by post-commit hook installed with installer
  # Any gpg encryption (--symmetric) should be added here
  [[ -e "${outgoing}" ]] || return
  ( flock --exclusive 200; cd "${outgoing_dir}"
  flock --exclusive "${write_lock}" mv -f "${outgoing}" "./${iofile}" &>/dev/null
  git add  "./${iofile}"
  git commit --no-verify --no-gpg-sign --allow-empty-message -m '' &>/dev/null
  ) 200>"${commit_lock}"
}; export -f GIBBERISH_commit

GIBBERISH_hook_commit(){
  # Usage: GIBBERISH_hook_commit <command string to be passed to bash>
  local hook="${1}"
  ( flock --exclusive 200; cd "${outgoing_dir}"
  git commit --no-verify --no-gpg-sign --allow-empty -m "${hook}"
  ) 200>"${commit_lock}"
}; export -f GIBBERISH_hook_commit

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
    GIBBERISH_commit &
  done
}; export -f GIBBERISH_write

GIBBERISH_read(){
  # Brief: Copy input stream from $incoming to output. If input pipe closes, reopen pipe.
  # Keep output pipe/fd open always. Behavior akin to 'tail -F', but for pipes.  

  # We could have used tail -q -n=+1 -F "${incoming}" 2>/dev/null with $incoming being a 
  # text file instead of fifo. It would however be polling the file, hence busy wait,
  # which may be undesirable.

  # Because $incoming is a named pipe, cat would die once the process writing to the pipe finishes.
  # Hence the loop, but only as long as GIBBERISH_fetch_loop is on. 
  while pkill -0 --pidfile "${fetch_pid_file}"; do
    cat "${incoming}"
  done
}; export -f GIBBERISH_read

GIBBERISH_prelaunch(){
  # Brief: Initial setups common to both client and server
 
  # Check if user is running cmd 'gibberish' for client and 'gibberish-server' for server
  [[ "${GIBBERISH}" == "${fetch_branch}" ]] || { echo "Cannot run for GIBBERISH=${GIBBERISH}" >&2 ; exit 1;}

  GIBBERISH_filesys

  # Sync/update repos:
  cd "${incoming_dir}" || { echo 'Broken installation. Rerun installer' >&2 ; exit 1;}
  git restore "./${iofile}"
  git pull --ff-only --no-verify --quiet origin "${fetch_branch}" || \
    { echo "Pull failed: ${incoming_dir}" >&2 ; exit 1;}
  until git tag last_read &>/dev/null; do git tag -d last_read &>/dev/null; done # Force create tag
  cd ~-

  cd "${outgoing_dir}" || { echo 'Broken installation. Rerun installer' >&2 ; exit 1;}
  git pull --ff-only --no-verify --quiet origin "${push_branch}" || \
    { echo "Pull failed: ${outgoing_dir}" >&2 ; exit 1;}
  cd "${OLDPWD}"

  [[ -p "${incoming}" ]] && { echo 'Pipe exists: May be another session running' >&2 ; exit 1;}
  mkfifo "${incoming}"

  # Launch fetch daemon
  GIBBERISH_fetchd

  # Trap exit from main sub-shell body of gibberish and gibberish-server
  trap 'rm -f "${incoming}"; pkill -TERM --pidfile "${fetch_pid_file}"' exit
  return
}; export -f GIBBERISH_prelaunch

gibberish-server(){
  # Config specific initialization
  export fetch_branch="server"
  export push_branch="client"
  
  # Sub-shell to make sure everything is well-encapsulated. Functions can exit when aborting without closing tty
  ( GIBBERISH_prelaunch
  
  cd "${HOME}" # So that the client is at the home directory on first connection to server 

  # To relay interrupt signals programmatically, we need to know pid of foreground processes attached to server tty
  # so that we can use pkill --term --parent. Following prompt command saves the tty and pid of current interactive bash
  export PROMPT_COMMAND='tty=$(tty); echo ${tty//\/dev\//} > $ttyfile; echo $$ > $pidfile'

  # PS0 is expanded after the command is read by bash but before execution begins. We exploit it to erase the command-line.
  # Erasure is necessary because the client tty will already have the cmd-line as typed by the user.
  export PS0="$(tput cuu1 ; tput ed)"

  # If client sends exit or logout, new shell must launch for a fresh new user session. Hence loop follows.
  local loop=true ; trap 'loop=false' INT TERM QUIT HUP
  while ${loop} && pkill -0 --pidfile "${fetch_pid_file}"; do
    bash -i # Interactive bash attached to terminal. Otherwise PS0 & PROMPT_COMMAND would be useless.
    # Also user won't get a PS1 prompt after execution of her/his command finishes or notification when bg jobs exit
  done < <(GIBBERISH_read) |& GIBBERISH_write
  exit )
}; export -f gibberish-server

gibberish(){
  # Config specific initialization
  export fetch_branch="client"
  export push_branch="server"

  # Sub-shell to make sure everything is well-encapsulated. Functions can exit when aborting without closing tty
  ( GIBBERISH_prelaunch
  
  # UI (output-end)
  (GIBBERISH_read &) # Sub-shell is invoked so that pid of bg job is not shown in tty

  echo 'Connecting...'
  echo 'echo "Welcome to GIBBERISH-server"' > "${outgoing}"; GIBBERISH_commit
  
  # UI (input-end)
  local cmd
  while read -re cmd ; do
    [[ -z "${cmd}" ]] && continue

    # The following echo is not the bash-builtin; otherwise flock would require -c. This is for demo only. Use builtin echo
    flock -x "${write_lock}" echo "${cmd}" >> "${outgoing}"; GIBBERISH_commit &
  done
  exit )
}; export -f gibberish
