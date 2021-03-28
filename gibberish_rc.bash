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
  export fetch_pid_file="${GIBBERISH_DIR}/fetch.pid" # Holds pid of GIBBERISH_fetch_loop
  export bashpidfile="${GIBBERISH_DIR}/bashpid" # Holds pid of user's current interactive bash in server
  export brbtag="${GIBBERISH_DIR}/brb.tmp"
}; export -f GIBBERISH_filesys

GIBBERISH_fetchd(){  
  # Brief: Daemon to fetch commits; Reads and relays user input to interactive shell in server;
  # Reads and conveys server output to user in client. Any GPG decryption is done here.
 
  GIBBERISH_checkout(){
    # Brief: Read and relay user input. Decrypt as necessary. Execute hooks.

    cd "${incoming_dir}"

    # Read new commits chronologically
    local commit
    for commit in $(git rev-list --reverse last_read.."${fetch_branch}"); do
      # Executable code (hook) can be passed through commit message.
      # Use-case: relay interrupt signals raised by user; file transfer in background.
      # Commit message should be an empty string otherwise
      commit_msg="$(git log -1 --pretty=%B "${commit}")"
      [[ -e "${brbtag}" ]] && return
      if [[ -z "${commit_msg}" ]]; then
        # When commit message is empty, update worktree only
        git restore --quiet --source="${commit}" --worktree -- "./${iofile}"
        
        # Any gpg decryption should be added here. cat is just a proxy for now
        cat "./${iofile}" > "${incoming}"
      else
        # Execute code supplied as commit message. This commit won't contain any other code
        eval "${commit_msg}"
      fi
      # Atomic tag update, such that there is always a last_read tag 
      echo "${commit}" > "${last_read_tag}"
      mv -f "${last_read_tag}" ".git/refs/tags/last_read"
    done
  }; export -f GIBBERISH_checkout
  
  GIBBERISH_fetch_loop(){
    # Brief: Iterative fetching from remote (origin). Update branch head and index.
    
    cd "${incoming_dir}"

    local loop=true; trap 'loop=false' INT TERM QUIT HUP
    while ${loop};do
      sleep 1 # This is just to model network latency. To be removed in release version

      git fetch --quiet origin "${fetch_branch}" || loop=false # Using 'break' would cause any pending checkout to be skipped

      # git-reset instead of git-merge or git-pull. This is because git-reset doesn't touch worktree
      # but updates the branch head and index only (--mixed option). Hence doesn't conflict with a 
      # restored worktree where git-merge would complain while trying to overwrite.
      # Note: we can use git-reset instead of merge only because our branch history is linear (--ff-only)
      git reset --mixed --quiet FETCH_HEAD # Or, replace FETCH_HEAD with "origin/${fetch_branch}"

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
  flock --exclusive "${write_lock}" mv -f "${outgoing}" "./${iofile}"
  git add  "./${iofile}"
  git commit --quiet --no-verify --no-gpg-sign --allow-empty --allow-empty-message -m ''
  # Allow empty commit above in case io.txt is same as previous
  ) 200>"${commit_lock}"
}; export -f GIBBERISH_commit

GIBBERISH_hook_commit(){
  # Usage: GIBBERISH_hook_commit <command string to be passed to bash>
  local hook="${1}"
  ( flock --exclusive 200; cd "${outgoing_dir}"
  git commit --quiet --no-verify --no-gpg-sign --allow-empty -m "${hook}"
  ) 200>"${commit_lock}"
}; export -f GIBBERISH_hook_commit

GIBBERISH_write(){
  # This function dumps the input stream to $outgoing even if the path gets unlinked.
  local timeout="0.1" # Interval for polling
  declare -x line
  IFS=
  while pkill -0 --pidfile "${fetch_pid_file}"; do
    read -r -d '' -t "${timeout}" line
    [[ -z "${line}" ]] && continue
    flock -x "${write_lock}" -c 'echo -n "${line}" >> "${outgoing}"'
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
  [[ -e "${brbtag}" ]] || until git tag last_read &>/dev/null; do git tag -d last_read &>/dev/null; done # Force create tag
  cd ~-

  cd "${outgoing_dir}" || { echo 'Broken installation. Rerun installer' >&2 ; exit 1;}
  git pull --ff-only --no-verify --quiet origin "${push_branch}" || \
    { echo "Pull failed: ${outgoing_dir}" >&2 ; exit 1;}
  cd "${OLDPWD}"

  rm -f "${incoming}" "${outgoing}"; mkfifo "${incoming}"

  # Launch fetch daemon
  GIBBERISH_fetchd

  # Trap exit from main sub-shell body of gibberish and gibberish-server
  trap 'pkill -TERM --parent "${BASHPID}"; echo -n > "${incoming}"' exit
  # INT makes bash exit fg loops; TERM exits bg loops; echo -n sends EOF to any proc listening to pipe
  return
}; export -f GIBBERISH_prelaunch

gibberish-server(){
  echo "This server needs to run in foreground."
  echo "To exit, simply close the terminal window."

  # Config specific initialization
  export fetch_branch="server"
  export push_branch="client"
  
  # Sub-shell to make sure everything is well-encapsulated. Functions can exit when aborting without closing tty
  ( flock --nonblock 200 || { echo "Another instance running"; exit;}
  export base_shell_pid="${BASHPID}" # This records the current subshell pid
  GIBBERISH_prelaunch
  
  cd "${HOME}" # So that the client is at the home directory on first connection to server 

  # To relay interrupt signals programmatically, we need to know the foreground processes group id attached to server tty
  # so that we can use pkill -SIG --pgroup. Following prompt command saves the pid of current interactive bash
  export PROMPT_COMMAND='echo $$ > $bashpidfile' # Might replace $$ with $BASHPID

  # PS0 is expanded after the command is read by bash but before execution begins. We exploit it to erase the command-line.
  # Erasure is necessary because the client tty will already have the cmd-line as typed by the user.
  export PS0="$(tput cuu1 ; tput ed)"

  # If client sends exit or logout, new shell must launch for a fresh new user session. Hence loop follows.
  trap 'kill -KILL $BASHPID' HUP
  while pkill -0 --pidfile "${fetch_pid_file}"; do
    bash -i # Interactive bash attached to terminal. Otherwise PS0 & PROMPT_COMMAND would be useless.
    # Also user won't get a PS1 prompt after execution of her/his command finishes or notification when bg jobs exit
  done < <(GIBBERISH_read) |& GIBBERISH_write
  exit ) 200>"${HOME}/.gibberish-server.lock"
}; export -f gibberish-server

gibberish(){
  # Config specific initialization
  export fetch_branch="client"
  export push_branch="server"

  # Sub-shell to make sure everything is well-encapsulated. Functions can exit when aborting without closing tty
  ( flock --nonblock 200 || { echo "Another instance running"; exit;}
  echo 'Connecting...'
  GIBBERISH_prelaunch
  
  # UI (output-end)
  { GIBBERISH_read &} 2>/dev/null # Redirection of stderr is so that pid of bg job is not shown in tty

  [[ -e "${brbtag}" ]] || { echo 'echo "Welcome to GIBBERISH-server"' > "${outgoing}" && GIBBERISH_commit ;}
  rm -f  "${brbtag}"

  # Trap terminal based signals to relay them to server foreground process
  trap 'GIBBERISH_hook_commit "GIBBERISH_fg_kill HUP"' HUP

  # Trapping SIGINT is of no use as that would cause bash to exit the following input loop
  # Hence, we first prevent Control-C from raising SIGINT; then bind the key-combination to appropriate callback
  local saved_stty_config="$(stty -g)"
  stty intr undef ; bind -x '"\C-C": GIBBERISH_hook_commit "GIBBERISH_fg_kill INT"'
  # Similarly...
  stty susp undef ; bind -x '"\C-Z": GIBBERISH_hook_commit "GIBBERISH_fg_kill TSTP"'
  stty quit undef ; bind -x '"\C-E": GIBBERISH_hook_commit "GIBBERISH_fg_kill QUIT"' # \C-\\ could not be bound

  # UI (input-end)
  local cmd
  while pkill -0 --pidfile "${fetch_pid_file}" ; do
    read -re cmd
    case "${cmd}" in
    exit|logout|quit|bye|hup|brb)
      pkill -TERM --pidfile "${fetch_pid_file}" # Close incoming channel (otherwise GIBBERISH_checkout might wait on $incoming)
      stty "${saved_stty_config}" # Bring back original key-binding; we could also use (if needed): stty intr ^C
      if [[ "${cmd}" == brb ]]; then
        touch "${brbtag}"
      else
        echo "Sending SIGHUP to server..."
        GIBBERISH_hook_commit "GIBBERISH_fg_kill HUP"
      fi
      break
      ;;
    ping|hey|hello|hi)
      GIBBERISH_hook_commit "GIBBERISH_hook_commit 'echo Hello from GIBBERISH-server'"
      ;;
    *)
      # The following echo is not the bash-builtin; otherwise flock would require -c. This is for demo only. Use builtin always
      flock -x "${write_lock}" echo "${cmd}" >> "${outgoing}"; GIBBERISH_commit &
      ;;
    esac
  done
  echo "GIBBERISH session ended"
  exit ) 200>"${HOME}/.gibberish-client.lock"
}; export -f gibberish

GIBBERISH_fg_kill(){
  # Brief: Send signal specified as parameter to foreground processes in server.
  local SIG="${1}"
  # TPGID gives the fg proc group on the tty the process is connected to, or -1 if the process is not connected to a tty
  local fg_pgid="$(ps --pid "${base_shell_pid}" -o tpgid=)"
  pkill -"${SIG}" --pgroup "${fg_pgid}" 2>/dev/null # Relay signal to foreground process group of user in server
  # Relay signal to current bash in server that user is interacting with only if HUP
  [[ "${SIG}" == HUP ]] && pkill -"${SIG}" --pidfile "${bashpidfile}" 2>/dev/null
}; export -f GIBBERISH_fg_kill
