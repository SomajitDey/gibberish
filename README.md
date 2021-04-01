# What is GiBBERISh

**GiBBERISh** stands for ***Git and Bash Based Encrypted Remote Interactive Shell***. It is a *free*, *easy* and *portable* solution to *securely* access your *Linux* computer from another *Linux* box over the internet, when none of the machines has a public IP address. You can also transfer files to and fro the remote host, with end-to-end encryption.

GiBBERISh consists of only a short *Bash* *script*, to be run on both the hosts (viz. *client* and *server*), and an *online* *Git* *repository* owned and controlled by the user, such as a *free* repository at any of [GitHub](https://github.com/), [GitLab](https://gitlab.com/), [Bitbucket](https://bitbucket.org/), [SourceForge](https://sourceforge.net/) etc.

# Why GiBBERISh

The standard way to remote access a Linux computer is Secure Shell (SSH). But, in order to connect to the remote host over internet, it has to have a public IP address -- something most personal and work PCs do not have. You can, however, beat this in the following ways:

1. SSH port forwarding at a server with public IP
2. Virtual Private Network or VPN

If you can afford any of the above, then GiBBERISh is not for you. However, if you are like me, who doesn't want to pay for a port-forwarding or VPN service, you are probably out of luck with SSH. 

However, you can still manage fine with a free remote access app, such as TeamViewer. If you are happily using such Virtual Network Computing (VNC), then too you won't have any use for GiBBERISh. I, however, faced a lot of problems connecting two different versions of Ubuntu using TeamViewer. That probably is my bad, but it seems likely that such intricate apps come with their own portability issues. Besides, they usually depend on a lot of other packages, installing which might be taxing for the inexperienced user. Anyways, I needed a light-weight, portable, easy-to-install and completely free yet reliable platform to access my remote machine securely over the internet. I didn't mind the latency, as long as my main purpose of submitting jobs to the remote host was served. Hence, my DIY solution - GiBBERISh.

# How it works

*An interactive shell is nothing but the user chatting with the operating system (OS), occasionally poking the OS with interrupts or job-control signals*. For GiBBERISh, the user's local machine is the **client**, and the OS in the remote host is the **server**. Correspondence between the two is managed by an automated *Git* workflow.

*[Git](https://git-scm.com/book/en/v2)*, if you don't know about it already, is a widely-used, fast, lightweight, distributed version-control system or content-tracker. Because it is distributed, widely available, and easy to use, you can use it to synchronize two machines quite easily. If you *push commits* (i.e. make some changes) to a Git *repository* (i.e. a directory with *history*) in one machine, you can synchronize or update its *clone* in another machine simply by *fetching* those new commits from the former repository  (called *upstream* in Git-speak).

Similar to SSH, Git can connect two machines over the internet for push/fetch only if at least one of them has a public IP address. As opposed to the paid SSH port forwarding services, however, one can have a free, if not private, online Git repository with a public link hosted in any of the popular Git-servers, such as [GitHub](https://github.com/), [GitLab](https://gitlab.com/), [Bitbucket](https://bitbucket.org/) or [SourceForge](https://sourceforge.net/). Although anyone can view (and fetch) the contents of your online repository, you remain in control of who can make changes to your repository. This is because all push access is protected by your password or an access-token generated by you.

#### How GiBBERISh connects two hosts (client and server) over the internet without any of them having a public IP address 

Whenever the user enters a command at client, the GiBBERISh script encrypts it with your Git credentials  using a state-of-the-art, yet free, cryptography service called GNU Privacy Guard (GPG). It then commits this encrypted text to the user's local repository and pushes the same to the user's upstream repository (say, at GitHub). Server's script then fetches this commit from upstream, decrypts and pipes the user's command to an interactive Bash. The output emitted by Bash is again encrypted, committed and pushed to GitHub, which the client fetches, decrypts and shows to the user. ( For an original implementation of a similar Git-based chat, see https://github.com/ephigabay/GIC ).

**Note**: Because only encrypted text goes to GitHub, the public cannot see what commands the user is running, or their outputs.

# Drawback:

Because of the dependence on an online Git repository, the time between entering a command and getting its output back is not insignificant. From multiple measurements, I found the latency varies between 8 to 12 seconds.
# Features:

1. Doesn't require a public IP address. Both machines can be behind multiple NATs.
2. Doesn't care about firewalls and blocked ports.
3. Secure (everything public is encrypted with your password / access-token).
4. Interactive.
5. Secure (GPG-encrypted) file transfer from client to server and vice-versa.
6. Easy and fast switching between local and remote environments without interrupting the remote session in any way. See *brb* in the *Keywords* section below.
7. Relays user's keyboard-generated signals, such as Ctrl-c; Ctrl-z to server.
8. Monitorability and overrides: If you grant someone else access to your local machine, for remote diagnostics for example, you can see all the commands she is executing from your terminal. You can also override those executions with Ctrl-c, Ctrl-z etc., if necessary.
9. Forever free. Given the popularity of Git in DevOps, freemium services such as GitHub are here to stay and they probably will continue hosting small public repositories for free for years to come. GiBBERISh is careful about keeping the repository size as small as possible. So, the size limit of the free-tier plans should never be an issue.
10. Lightweight: CPU usage is minimal. Polling and busy-waits are avoided wherever possible in favor of event-driven triggers.
11. Hassle-free installation, portability and flexibility: GiBBERISh only runs Git, and some basic Unix commands, all from a short, simple, stupid (KISS) Bash script. Most current Linux distributions ship with Git and Bash both. Hence, GiBBERISh should run readily on those. You also hold the perpetual right to adapt the script to your needs.
12. Everything is under your control. You are free to modify the single Bash script that GiBBERISh runs from. You own and manage the upstream repository. If you are connecting to your work computer from your home machine or vice versa, you control both the machines. You also choose who can access your machine, should you ever be granting someone else remote access for purposes of diagnostics, instructions etc. [**Tip**: Revoke their (push) access-token from your upstream account once they are done].
13. Because Git and Bash are the only main ingredients, GiBBERISh (in its present form or another) maybe run easily on Windows using [Git-Bash](https://gitforwindows.org/). But that won't probably be necessary, given that Windows 10 now ships with a subsystem for Linux ([WSL](https://docs.microsoft.com/en-us/windows/wsl/install-win10)).

# How to install / run

First, create a dedicated repository at any free Git hosting service (e.g. https://github.com/, https://gitlab.com/, https://bitbucket.org/ or https://sourceforge.net/). The repository can be completely empty, i.e. without any commits. **Tip**: Also generate, if possible, a personal access-token (PAT) for your account.

At the Linux machine that you want to use as server, run the *installer* script: 

```bash
./installer
```

Close and reopen the terminal to make the installation take effect.

To start the server, run: 

```bash
gibberish-server
```

At the client machine, install GiBBERISh similarly as above.

To access the remote server, simply run:

```bash
gibberish
```

After 8-12 seconds, you should get the server's command prompt.

# Keywords or built-in commands

GiBBERISh recognizes a few keywords as listed below.

**ping** | **hello** | **hey** | **hi** | To test if the server is still connected. Consider the following situation. You are running a foreground process on the server, which outputs infrequently. Because it is in foreground, you do not have the command prompt and hence cannot execute a short command such as [echo](https://www.gnu.org/software/bash/manual/html_node/Bash-Builtins.html) to see if the server is still responding. Just enter any of these keywords, and the server will send you a 'hello' if it can hear you, without interrupting that foreground process in any way. However, you can also do a simple Ctrl-z to get back the prompt, at the expense of stopping the foreground process. **Note**: If you enter any of these keywords at the command prompt, you are not given a new prompt after the server says hello. If this makes you uncomfortable, just press ENTER and wait for the server to give you another command prompt.

**exit** | **quit** | **logout** | **hup** | **bye** | To end the session and disconnect or hangup. When you do this, the current interactive shell in the server is closed and a new, fresh shell is launched ready for the next session. You therefore, would lose any environment variable you had set or function definitions you had sourced during the last session. Beware that this should also close any process running on the server that the exiting shell sends SIGHUP to, unless the process has a handler installed for HUP. Start processes in background with [nohup](https://man7.org/linux/man-pages/man1/nohup.1.html) if you intend to keep them running even after you logout using these keywords. 

**brb** | Be right back, viz. to quickly switch to your local environment for a short while, without ending or interrupting the remote session. Any foreground process running in the server, keeps running uninterrupted. With this keyword, you simply get back your local command prompt, whenever you need to run commands locally during a remote session. To return to the remote session, just enter 

```bash
gibberish
```

again. You will be shown all the server output since the time you **brb**d, so you miss nothing. **Note**: If you enter *brb* at the command prompt, you are not given a new prompt after you return to the session. If this makes you uncomfortable, just press ENTER and wait for the server to give you another command prompt.

**rc** | Run commands. This is akin to the . or [source](https://www.gnu.org/software/bash/manual/html_node/Bash-Builtins.html) built-in of Bash. Whereas **source** reads commands from a local file and executes them in the current shell, **rc** takes commands from a client-side file and executes them in the server-side shell that the user is currently interacting with. The syntax is: 

```bash
rc <local path to script>
```

All the commands in the given script are passed to upstream in one Git-push. Hence, use of this keyword helps with latency issues.

**take** | **push** | See next section

**bring** | **pull** | See next section

------

If you need to run a command that matches any of the keywords described above, use the **[command](https://www.gnu.org/software/bash/manual/html_node/Bash-Builtins.html)** built-in of Bash.

# File and directory transfer

**Copying file from client to server:**

```bash
take <local path> <remote path> 
# or
push <local path> <remote path>
```

**Copying file from server to client:**

```bash
bring <remote path> <local path>
# or
pull <remote path> <local path>
```

File transfer is atomic, which guarantees you never end up with a corrupt file, even if the transfer operation gets interrupted or terminated prematurely. If the destination file is existing, it will be overwritten after backup. If destination path is a directory, the file would be put inside it. Make sure none of the filenames or paths contains spaces. The paths can be absolute or relative.

To transfer directories or a collection of files, archive them first, with [tar](https://man7.org/linux/man-pages/man1/tar.1.html) for example, and then use the above commands to exchange that single archive file.

**Note**: File transfer is end-to-end encrypted with your Git credentials. To keep your Git repository size small, the files are transferred using free, public file-hosting servers.

# Library, not executable

The Bash script for GiBBERISh, viz. *gibberish_rc.bash*, is a library rather than an executable. On startup, your interactive Bash sources this script. The *installer* puts the corresponding run-command in .bashrc. 

The *installer*, on the other hand, is an executable script. Hence, do a *chmod +x* on it, if necessary.

# Internals (pointers to understand the code)

The client-side and server-side codes are structurally almost the same. This is why a single shell-script suffices for both. There are two types of events:

1) Internal events: User@client or Bash@server creates new data to push

2) External events: Git-fetch brings new data from outside to display or process 

Internal events are mostly waited for, while external ones need to be polled for continuously. Everything else is mostly triggered by these events. For example, upon creation, the data to be pushed is first siloed and an encrypt-commit-push pipeline is triggered.

The Git repository for GiBBERISh has two linear branches, viz. server-branch and client-branch. Server fetches from server-branch, but pushes to client-branch. Client does the converse. Every user-command@client or Bash-output@server, is committed to the proper outgoing branch as a single text file. As new commands or outputs become available, this file is simply revised to hold the same. The Git-worktree, therefore, always contains only a single file, and all the commands/outputs can always be tracked from its revision history. Every time a commit happens, it triggers a post-commit hook that pushes the commit automatically.

Every iteration of Git-fetch triggers a checkout sequence that tracks all the new commits chronologically, restoring the corresponding version of the abovementioned text file for decryption. Upon successful decryption, the checkout function pushes the data down a pipeline to user (@client) or Bash (@server), before moving on to the next commit in the git-revision-list.

Note that if every user-command was passed using that single text file alone, then all the commands would end up in the queue for Bash@server. To relay a user-generated signal (SIGINT, SIGTSTP, SIGQUIT) to a foreground process on demand, however, we need to route [kill](https://man7.org/linux/man-pages/man1/kill.1.html) commands to a second, parallel shell in the server. We, therefore, need a way to commit commands in the repository other than the single text file mentioned before. GiBBERISh exploits Git's commit-message field for this purpose. Only those commits that carry the user-generated control signals, or any other command that is to be executed by the parallel shell only, would have commit-messages which hold the commands themselves. All other commits have empty commit-messages. Whether the commit is meant for the main shell or the parallel, can therefore be ascertained simply by checking whether the commit-message is empty or not. 

Such commit-message commands, meant for the parallel shell, are mostly kill(@server) and file-download(@client) commands. Hence, they do not contain any sensitive data and are consequently not encrypted to save on time. These commands are called **hook**s. Both server and client share this hook-execution architecture. Hooks are the only way server can make client do some work, such as required during file transfer from server to client.

In contrast with SSH, GiBBERISh does not stream every key-stroke made by the user to the server in real-time. Rather, it first lets the user enter the complete command, then reads it, checks for keywords, and only then decides what to do. If the command-line is not a keyword, it is pushed to the server as is for execution. To generate signals at server from particular key-sequences entered at the client, key-binding is done at the user's terminal such that it commits and pushes the appropriate hook to be executed by the parallel shell at server, whenever those keys are pressed by the user.

# Legal

GiBBERISh-- Git and Bash Based Encrypted Remote Interactive Shell

Copyright (C) 2021 Somajit Dey

You are free to modify and distribute the code under GPL-3.0-or-later <https://www.gnu.org/licenses/>

*GiBBERISh comes with ABSOLUTELY NO WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. Use it at your own risk. The developer or copyright holder won't be liable for any damage done by or done using this software.*

