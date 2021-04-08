# This is the library for GiBBERISH - Git and Bash Based Encrypted Remote Interactive Shell
# Author: Somajit Dey 2021 <dey.somajit@gmail.com>
# Online repository: https://github.com/SomajitDey/gibberish
# Bug reports: Raise an issue at the repository or email the author directly
# Copyright (C) 2021 Somajit Dey
# License: GPL-3.0-or-later <https://github.com/SomajitDey/gibberish>
# Disclaimer: This software comes with ABSOLUTELY NO WARRANTY; use at your own risk.

GIBBERISH_filesys(){
  # Brief: Export important file definitions with global scope. Files that are used locally
  # within a single function only are not to be listed here.
  
  export GIBBERISH_DIR="${HOME}/.gibberish/${GIBBERISH}"
  export incoming_dir="${GIBBERISH_DIR}/incoming"
  export outgoing_dir="${GIBBERISH_DIR}/outgoing"
  export iofile="io.txt"
  export incoming="${GIBBERISH_DIR}/incoming.fifo"
  export outgoing="${GIBBERISH_DIR}/outgoing.txt"
  export write_lock="${GIBBERISH_DIR}/write.lock"
  export commit_lock="${GIBBERISH_DIR}/commit.lock"
  export fetch_pid_file="${GIBBERISH_DIR}/fetch.pid" # Holds pid of GIBBERISH_fetch_loop
  export bashpidfile="${GIBBERISH_DIR}/bashpid" # Holds pid of user's current interactive bash in server
  export brbtag="${GIBBERISH_DIR}/brb.tmp"
  export patfile="${GIBBERISH_DIR}/access_token" # Holds passphrase/access-token of cloud repo
  export snapshot="${GIBBERISH_DIR}/pre-gpg-encryption.tmp"
  export file_transfer_url="${GIBBERISH_DIR}/file_transfer_url.tmp"
  export prelaunch_pwd="${PWD}"
  export prelaunch_oldpwd="${OLDPWD}"
  export promptfile_abs="${GIBBERISH_DIR}/prompt.tmp" # Abs path
  export promptfile_rel="prompt.txt" # Relative path
  export push_error_log="${GIBBERISH_DIR}/push_error.log"
  export pull_error_log="${GIBBERISH_DIR}/pull_error.log"
  export fetch_error_log="${GIBBERISH_DIR}/fetch_error.log"
}; export -f GIBBERISH_filesys

GIBBERISH_fetchd(){  
  # Brief: Daemon to fetch commits; Reads and relays user input to interactive shell in server;
  # Reads and conveys server output to user in client. Any GPG decryption is done here.
 
  GIBBERISH_checkout(){
    # Brief: Read and relay user input. Decrypt as necessary. Execute hooks.

    cd "${incoming_dir}"; local last_read_tag="${GIBBERISH_DIR}/last_read.tmp"

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
        # git restore --quiet --source="${commit}" --worktree -- . # Use this for recent Git versions only
        git checkout --quiet "${commit}" -- . # Not same as git-restore above, this changes the index too
        if [[ -e "${patfile}" ]]; then
          gpg --batch --quiet --passphrase-file "${patfile}" --decrypt "./${iofile}" > "${incoming}" 2>/dev/null \
            || echo 'GIBBERISH: Decryption failed. Perhaps client and server are not using the same passphrase/access-token'
        else
          cat "./${iofile}" > "${incoming}"
        fi
      else
        # Execute code supplied as commit message. This commit won't contain any other code
        # All hooks (such as client-side file download) must remember that here PWD is ${incoming_dir}
        ( eval "${commit_msg}" ) # Sub-shell isolates hook execution environment, so that the current one remains unaffected
      fi
      # Atomic tag update, such that there is always a last_read tag 
      echo "${commit}" > "${last_read_tag}"
      mv -f "${last_read_tag}" ".git/refs/tags/last_read"
    done
  }; export -f GIBBERISH_checkout
  
  GIBBERISH_fetch_loop(){
    # Brief: Iterative fetching from remote (origin). Update branch head and index.
    # When fetch must fail, e.g. due to some connectivity issue or if git crashes, it fails loudly and quits
    # Because fetch is the beating heart of GiBBERISh, most other loops check if fetch is alive before iterating
    
    cd "${incoming_dir}"

    local loop=true; trap 'loop=false' INT TERM QUIT HUP
    while ${loop};do
#      git fetch --quiet origin "${fetch_branch}" || loop=false # Using 'break' would cause any pending checkout to be skipped
      if ! (date;timeout 5 git fetch --quiet origin "${fetch_branch}") &>>"${fetch_error_log}"; then
        [[ -v warning ]] || local warning="$(echo 'Check network connection...To exit, use command: brb' >/dev/tty)"
        continue
      else
        [[ -v warning ]] && unset warning && echo 'Connection is back :-)'
        echo -n >"${fetch_error_log}"
      fi

      # git-reset instead of git-merge or git-pull. This is because git-reset --soft doesn't touch worktree
      # but updates the branch head only. Hence doesn't conflict with a
      # checked-out worktree and index where git-merge would complain while trying to overwrite.
      # Note: we can use git-reset instead of merge only because our branch history is linear (--ff-only)
      git reset --soft --quiet FETCH_HEAD # Or, replace FETCH_HEAD with "origin/${fetch_branch}"

      # Fetching is iterative - hence it can trigger checkout continuously. Thus, nonblock flock is ok
      flock --nonblock --no-fork "${incoming_dir}" -c GIBBERISH_checkout &
    done
    }; export -f GIBBERISH_fetch_loop

  GIBBERISH_fetch_loop & # Bg job in sub-shell means we don't have to worry about any 'cd' done therein
  echo ${!} > "${fetch_pid_file}"
}; export -f GIBBERISH_fetchd

GIBBERISH_commit(){
  # Corresponding push is handled by post-commit hook installed with installer
  [[ -e "${outgoing}" ]] || return # Check existence to decide whether to wait for lock at all
  ( flock --exclusive 200; cd "${outgoing_dir}"
  [[ -e "${outgoing}" ]] || exit # Check existence after lock has been acquired
  if [[ -e "${patfile}" ]]; then
    flock --exclusive "${write_lock}" mv -f "${outgoing}" "${snapshot}"
    rm -f "./${iofile}" # Otherwise gpg complains that file exists and fails
    gpg --batch --quiet --armor --output "./${iofile}" --passphrase-file "${patfile}" --symmetric "${snapshot}"
  else
    flock --exclusive "${write_lock}" mv -f "${outgoing}" "./${iofile}"
  fi

  # Commit the current prompt, if any, through $promptfile_rel inside repo. Client-side execution of this line is inconsequential
  mv -f "${promptfile_abs}" "./${promptfile_rel}" 2>/dev/null # || cat /dev/null > "./${promptfile_rel}"

  git add .
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

  # We could have used tail -n +1 -F "${incoming}" --pid=<GIBBERISH_fetch_loop pid> 2>/dev/null
  # with $incoming being a text file rather than fifo. It would however be polling the file, 
  # hence busy wait, which might be undesirable.

  # Because $incoming is a named pipe, cat would die once the process writing to the pipe finishes.
  # Hence the loop, but only as long as GIBBERISH_fetch_loop is on. 
  while pkill -0 --pidfile "${fetch_pid_file}"; do
    cat "${incoming}"
  done
}; export -f GIBBERISH_read

GIBBERISH_prelaunch(){
  # Brief: Initial setups common to both client and server

  echo 'Configuring...' 

  # Check if user is running cmd 'gibberish' for client and 'gibberish-server' for server
  [[ "${GIBBERISH}" == "${fetch_branch}" ]] || { echo "Cannot run for GIBBERISH=${GIBBERISH}" >&2 ; exit 1;}

  GIBBERISH_filesys

  # Sync/update repos:
  cd "${incoming_dir}" || { echo 'Broken installation. Rerun installer' >&2 ; exit 1;}
  # git restore --quiet "./${iofile}" 2>/dev/null # Use for recent Git versions only
  git checkout --quiet "./${iofile}" 2>/dev/null # Same as git-restore above
  git pull --ff-only --no-verify --quiet origin "${fetch_branch}" 2>"${fetch_error_log}" || \
    { echo "Pull failed: ${fetch_branch}. Check network connection." >&2 ; exit 1;}
  [[ -e "${brbtag}" ]] || until git tag last_read &>/dev/null; do git tag -d last_read &>/dev/null; done # Force create tag

  cd "${outgoing_dir}" || { echo 'Broken installation. Rerun installer' >&2 ; exit 1;}
  [[ -e "${brbtag}" ]] || git reset --hard --quiet "origin/${push_branch}" # Clear all unpushed commits from previous session
  git pull --rebase --no-verify --quiet origin "${push_branch}" 2>"${pull_error_log}" || \
    { echo "Pull failed: ${push_branch}. Check network connection." >&2 ; exit 1;}
  git push --quiet --no-verify origin "${push_branch}" 2>"${push_error_log}" || \
    { echo "Push failed: ${push_branch}. Did you change password? If so, reinstall." >&2 ; exit 1;} # Check if PAT is still ok

  rm -f "${incoming}" "${outgoing}"; mkfifo "${incoming}"

  # Launch fetch daemon
  GIBBERISH_fetchd

  # Trap exit from main sub-shell body of gibberish and gibberish-server
  trap 'pkill -TERM --parent "${BASHPID}"; echo -n > "${incoming}"' exit
  # INT makes bash exit fg loops; TERM exits bg loops; echo -n sends EOF to any proc listening to pipe
  return
}; export -f GIBBERISH_prelaunch

gibberish-server(){
  # Config specific initialization
  export fetch_branch="server"
  export push_branch="client"
  export server_tty="$(tty)"
  
  # Sub-shell to make sure everything is well-encapsulated. Functions can exit when aborting without closing tty
  ( flock --nonblock 200 || { echo "Another instance running"; exit;}

  GIBBERISH_prelaunch

  echo "This server needs to run in foreground."
  echo "To exit, simply close the terminal window."
  echo "Command execution in this session is recorded below...Use Ctrl-C etc. to override"
  export OLDPWD="/tmp"; cd "${HOME}" # So that the client is at the home directory on first connection to server 

  local bash_init='
  echo $$ > "${bashpidfile}" # Can also use $BASHPID instead of $$
  . "${HOME}/.bashrc"
  PS1="GiBBERISh-server:\w$ "
  PROMPT_COMMAND="echo -n \"\${PS1@P}\" > ${promptfile_abs}" # Save the current prompt everytime an fg process exits
  PS0="\$(echo -n > ${promptfile_abs}; tput cuu1 2>/dev/null ; tput ed 2>/dev/null)" # After cmd is read and b4 execution begins
  # Empties the promptfile because an fg process is just about to start
  # tputs are to avoid showing the commandline twice to user@client
  '
  
  # If client sends exit or logout, new shell must launch for a fresh new user session. Hence loop follows.
  trap 'kill -KILL $BASHPID' HUP
  while pkill -0 --pidfile "${fetch_pid_file}"; do
    bash --rcfile <(echo "${bash_init}") -i # Interactive bash attached to terminal. Otherwise PS0 & PROMPT_COMMAND would be useless.
    # Also user won't get a PS1 prompt after execution of her/his command finishes or notification when bg jobs exit
  done < <(GIBBERISH_read | tee /dev/tty) |& tee /dev/tty | GIBBERISH_write
  exit ) 200>"${HOME}/.gibberish-server.lock"
}; export -f gibberish-server

gibberish(){
  # Config specific initialization
  export fetch_branch="client"
  export push_branch="server"

  # Sub-shell to make sure everything is well-encapsulated. Functions can exit when aborting without closing tty
  ( flock --nonblock 200 || { echo "Another instance running"; exit;}

  GIBBERISH_prelaunch
  
  # UI (output-end)
  { GIBBERISH_read &} 2>/dev/null # Redirection of stderr is so that pid of bg job is not shown in tty

  if [[ -e "${brbtag}" ]] ; then
    echo 'Welcome back to GIBBERISH-server'
    GIBBERISH_prompt
    rm -f  "${brbtag}"
  else
    echo 'echo "Welcome to GIBBERISH-server"' > "${outgoing}" && GIBBERISH_commit
  fi

  # Trap terminal based signals to relay them to server foreground process
  trap 'GIBBERISH_hook_commit "GIBBERISH_fg_kill HUP"' HUP

  # Trapping SIGINT is of no use as that would cause bash to exit the following input loop
  # Hence, we first prevent Control-C from raising SIGINT; then bind the key-combination to appropriate callback
  local saved_stty_config="$(stty -g)"
  stty intr undef ; bind -x '"\C-C": GIBBERISH_hook_commit "GIBBERISH_fg_kill INT"'
  # Similarly...
  stty susp undef ; bind -x '"\C-Z": GIBBERISH_hook_commit "GIBBERISH_fg_kill TSTP"'
  stty quit undef ; bind -x '"\C-E": GIBBERISH_hook_commit "GIBBERISH_fg_kill QUIT"' # \C-\\ didn't work as \ escaped trailing quote(")
  bind -x '"\C- ": GIBBERISH_hook_commit "GIBBERISH_fg_kill STOP"' # Force pause fg process

  # UI (input-end)
  local cmd
  local histfile="${GIBBERISH_DIR}/history.txt"
  echo "help" > "${histfile}" # This file initialization is necessary for the following history builtin to work
  history -c; history -r "${histfile}" # Clean previous history, then initialize history-list
  cd "${prelaunch_oldpwd}"; cd "${prelaunch_pwd}" # So that user can do ~-/ and ~/ in push/take, pull/bring and rc
  while pkill -0 --pidfile "${fetch_pid_file}" ; do
    read -re -p"$(tput sgr0 2>/dev/null)" cmd # Purpose of the invisible prompt is to stop backspace from erasing server's command prompt

    history -s ${cmd} # Save last-read command to history-list

    set -- ${cmd}; local keyword="$1"; shift; local arg="$@"

    case "${keyword}" in
    help|tutorial)
      echo 'Please look up https://github.com/SomajitDey/gibberish/tree/dev#keywords-or-built-in-commands'
      GIBBERISH_prompt
      ;;
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
      { (sleep 10; echo 'Seems GIBBERISH-server is down'; GIBBERISH_prompt)& local killme="$!";} 2>/dev/null
      GIBBERISH_hook_commit "GIBBERISH_hook_commit 'kill -KILL ${killme}; echo Hello from GIBBERISH-server; GIBBERISH_prompt'"
      ;;
    latency|rtt)
      GIBBERISH_hook_commit "GIBBERISH_hook_commit 'echo \$((EPOCHSECONDS-${EPOCHSECONDS}))s; GIBBERISH_prompt'"
      ;;
    local)
      (eval "${arg:=pwd}"); GIBBERISH_prompt
      ;;
    *)
      if [[ "${keyword}" =~ ^(take|push)$ ]]; then
        eval set -- ${arg} 2>/dev/null
        local file_at_client="${1}"
        local filename="${file_at_client##*/}"
        echo "Uploading ..."
        if GIBBERISH_UL "${file_at_client}"; then
          echo "Upload successful. Now pushing to remote. You'll hear next from GIBBERISH-server."
          cmd="url=$(awk NR==1 "$file_transfer_url"); filename='${filename}'; GIBBERISH_DL ${arg}"
        else
          echo -e \\n"Upload FAILED"; GIBBERISH_prompt
          continue
        fi
      elif [[ "${keyword}" =~ ^(bring|pull)$ ]]; then
        # First generate the absolute path for the destination file, which is local
        # Otherwise, during hook-execution, relative paths would be relative to $incoming_dir
        eval set -- ${arg} 2>/dev/null
        local path_at_client="${2}"
        [[ "${path_at_client}" != /* ]] && path_at_client="${PWD}/${path_at_client}"
        cmd="path_at_client='${path_at_client}'; GIBBERISH_bring ${arg}"
      elif [[ "${keyword}" == rc ]]; then
        eval local script="${arg}" 2>/dev/null
        [[ -f "${script}" ]] || { echo "Script doesn't exist." \
             echo "You can enter next command now or press ENTER to get the server's prompt"; continue;}
        cmd="$(cat "${script}")"
      fi
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
  local SIG="${1}"; echo -n "GIBBERISH client sent ${SIG} "
  # TPGID gives the fg proc group on the tty the process is connected to, or -1 if the process is not connected to a tty
  local fg_pgid="$(ps --tty "${server_tty}" -o tpgid= | awk NR==1)"
  pkill -${SIG} --pgroup ${fg_pgid} # Relay signal to foreground process group of user in server
  # Relay signal to current bash in server that user is interacting with only if HUP
  [[ "${SIG}" == HUP ]] && pkill -"${SIG}" --pidfile "${bashpidfile}" 2>/dev/null
}; export -f GIBBERISH_fg_kill

GIBBERISH_UL(){
  # Brief: Encrypt and upload given payload
  # Below we use transfer.sh for file hosting. If it is down, use any of the following alternatives:
  # 0x0.st , file.io , oshi.at , tcp.st
  # In the worst case scenario when everything is down, we can always push the payload through our Git repo
  local payload="$1"
  ( set -o pipefail # Sub-shell makes sure pipefail is not inherited by anyone else
  gpg --batch --quiet --armor --output - --passphrase-file "${patfile}" --symmetric "${payload}" | \
  curl --silent --show-error --upload-file - https://transfer.sh/payload.asc > "${file_transfer_url}"
  )
}; export -f GIBBERISH_UL

GIBBERISH_DL(){
  # Brief: Download from given url and decrypt to the given local path
  local copyto="${2}"
  while [[ -d "${copyto}" ]]; do copyto="${copyto}/${filename}"; done # Enter subdirectories recursively if needed
  local dlcache="${GIBBERISH_DIR}/dlcache.tmp"; rm -f "${dlcache}"
  ( set -o pipefail # Sub-shell makes sure pipefail is not inherited by anyone else
  curl -s -S "${url}" | gpg --batch -q -o "${dlcache}" --passphrase-file "${patfile}" -d
  )
  if (( $? == 0 )); then
    mv --force --backup='existing' -T "${dlcache}" "${copyto}" && \
    echo -e \\n"File transfer: COMPLETE"
  else
    echo -e \\n"File transfer: FAILED"
  fi
}; export -f GIBBERISH_DL

GIBBERISH_bring(){
  local file_at_server="$1"
  local filename="${file_at_server##*/}"
  if GIBBERISH_UL "${file_at_server}"; then
    GIBBERISH_hook_commit "url=$(awk NR==1 "$file_transfer_url"); filename='${filename}';
    GIBBERISH_DL '${file_at_server}' '${path_at_client}'"
  else
    echo -e \\n"FAILED."
  fi
}; export -f GIBBERISH_bring

GIBBERISH_prompt(){
  # Brief: Show current server prompt if there is no active fg process
  # Meant to be used by client only
  local promptfile="${incoming_dir}/${promptfile_rel}"
  cat "${promptfile}" # Show server prompt
}; export -f GIBBERISH_prompt
