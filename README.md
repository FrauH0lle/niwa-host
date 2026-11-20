# mevedel hosts

Headless Emacs daemons in containers. Each keeps a mevedel lobby open on
a collaboration relay for every one of its projects; a lobby link is a
bookmark that survives restarts and lists, opens and creates sessions.

Two hosts: `private` (only you) and `public` (shareable). A host's container
is the trust boundary: a full or owner link to any of its lobbies lets the
holder run commands inside that container, which sees all of the host's
projects. So the public host never sees the private projects or your private
Codex login. Each host has its own state volume and login.

The scripts use Podman when it is installed and Docker otherwise; set
`CONTAINER=docker` to choose explicitly.

## Deploy to a server

The target is a fresh Ubuntu or Debian machine, VM or LXC container that
you can reach as root over ssh, or as a sudo user via `./deploy
admin@HOST`. On Proxmox, enable **Options > Features > nesting** for the
container; rootless Podman needs it.

Without an ssh key for root there (one given when creating the
container), allow a password login for the first deploy:

```sh
printf 'PermitRootLogin yes\nPasswordAuthentication yes\n' \
  > /etc/ssh/sshd_config.d/10-root-login.conf
systemctl restart ssh
```

`./deploy` installs your ssh key (`ssh-copy-id`), so afterwards delete
that file again and restart ssh; root and `mevedel` then log in with the
key only.

1. Push mevedel; only pushed commits reach the server:

   ```sh
   cd ~/Projekte/mevedel && git push
   ```

2. Update the relay the usual way (`go build` and redeploy, or the
   release binary). The lobby page ships with the relay.

3. From this folder:

   ```sh
   ./deploy 192.0.2.10
   ```

   It copies the folder to `/home/mevedel/mevedel-host` and runs `./setup`
   there as root, which

   - installs Podman and podman-compose, and creates the user `mevedel`
     (with root's ssh keys) that owns the folder and runs the hosts
     rootless;
   - asks once for the relay URL (`wss://mevedel.skadonk.me`) and the host
     token from `~/.emacs.d/site-lisp/config.el`, and writes `.env`;
   - clones mevedel and gptel, builds the image (5-10 minutes) and starts
     both hosts;
   - installs user systemd units that start the hosts on boot and run
     `./update` nightly at 4:00 (it skips nights when a turn is running).

   Run `./deploy` again whenever these files change; the server keeps its
   `.env`, `src/` and `projects/`.

4. Log in to Codex, once per host (`ssh root@192.0.2.10` or
   `ssh mevedel@192.0.2.10`, then `cd /home/mevedel/mevedel-host`):

   ```sh
   ./attach private
   ```

   - in Emacs: `M-x gptel-openai-oauth-login`
   - open the URL it shows on your phone and enter the code
   - `C-x 5 0` leaves Emacs; the daemon keeps running

   Repeat with `./attach public`, using the account colleagues' usage
   should land on.

5. Add projects (see [Projects](#projects)); each prints its lobby link:

   ```sh
   ./project add private notes
   ./project add public website https://github.com/example/website.git
   ```

   Scan the QR code with your phone and bookmark the page. For
   colleagues, open a public lobby, tap **Invite** and pass on the full
   link, never the owner link: an owner link can also create sessions and
   switch to full-auto.

The scripts work as root too: they switch to the folder's owner, since
rootless containers are only visible to the user that runs them. For
plain Podman commands, log in as `mevedel` (`ssh mevedel@...`).

Coming from the earlier Docker setup, `./setup` stops the Docker hosts and
copies the private one's state volume, so its Codex login and sessions
carry over.
Remove Docker once everything runs (`apt purge docker-ce
docker-compose-plugin`, or whichever packages you installed).

## Projects

Each host serves the projects in its projects directory
(`projects/private/`, `projects/public/`; `PRIVATE_PROJECTS` and
`PUBLIC_PROJECTS` in `.env`): one lobby per directory, named after it.
Usually they are git repositories:

```sh
./project                                    # list them
./project add public website https://...git  # clone one, open its lobby
./project add private notes                  # or start an empty one
./lobby-link public website                  # its owner link again
./project remove public website              # set it aside
```

`add` opens the lobby right away and prints its owner link, and puts the
model's git instructions into the project (see below). Cloning a
private repository on the server needs credentials for `mevedel` there,
e.g. a deploy key in `/home/mevedel/.ssh`. `remove` waits until the host
is idle, restarts it and moves the project to `projects/.removed/`;
delete it from there when you are sure; its lobby credentials live in
its `.mevedel/`, so moving it back revives its links. A directory copied
in by hand gets its lobby on the next restart (`./compose restart public`).

Earlier, `projects/private` was itself the project; `./update` moves it to
`projects/private/private`, where its lobby links and sessions keep
working.

### Repositories the model works in

The project itself, when it is a clone, and further repositories cloned
into it are ordinary git repositories: the model pulls, branches, commits
and pushes there, and you pick its work up from the remote on your own
machine.

```sh
./project clone public website git@github.com:example/api.git
./project unclone public website api   # set it aside in projects/.removed
```

`clone` puts the repository into the project as `api/`, where it appears
right away, and adds the git instructions. The project's own repository
lists it as untracked; ignoring it there would hide it from the lobby's
file browser and the model's search.

**Instructions.** `add` and `clone` copy `project-agents.md` into the
project as `AGENTS.local.md`, which mevedel reads after `AGENTS.md`: pull
before changing anything, one branch per change, push it for a pull or
merge request, and ask whom to commit as. List the people who commit
there; an existing `AGENTS.local.md` is left alone. For a project from
before, copy it in by hand:

```sh
cp project-agents.md projects/public/website/AGENTS.local.md
```

Where the project is itself a clone with a remote, `add` and `clone` also
list the file in its `.git/info/exclude`, so it is never committed there;
excluded files do not show in the lobby's file browser.

**Identity and credentials.** Each host has `git/HOST/config`, which the
scripts create once and the container sees read-only as
`~/.config/git/config`. It gives the host no identity of its own
(`user.useConfigOnly`): the model commits as the person it commits for,
who is then author and committer both, and a plain `git commit` fails
rather than recording the host. Push credentials go in the same folder, as
its comments describe; `./deploy` leaves `git/` alone on the server. The
model can read whatever credentials are there, and so can whoever holds a
full or owner link to that host's lobbies, so scope them to the
repositories (deploy keys with write access, branch protection on the
default branch).

**Sync.** `./project refresh` (hourly, `mevedel-host-refs.timer`) fetches
every such repository inside its running host, with its credentials, and
fast-forwards branches that track a remote. The checked-out branch moves
only while its files are unchanged and the host is idle; a branch with
unpushed commits is never touched. In between, the model pulls before it
starts. Git never runs on these repositories outside the container: the
model can change their hooks and config.

**Permissions.** mevedel keeps `.git` read-only for the model's commands
by default; `init.el` lifts that on the hosts, since the container is the
boundary. `git fetch` and `git pull` get network access without asking;
`git push` asks for it, so the reviewer (or you) sees it first.

### Software the model needs

The model has no root in the containers, and they are recreated every
night, so whatever it installed with pacman would vanish anyway.

- **Python and Node packages** it installs itself, with uv and npm:
  `uv sync`, `uv add`, `uv pip install`, `uv python install`, `uv tool
  install`, `npm install`, `npm ci` and the like get network access
  without asking (`init.el`). Project environments land in the project
  (`.venv`, `node_modules`); uv's Pythons and tools and `npm install -g`
  land on the host's tools volume (`~/tools`), which only those commands
  may write and which survives the recreate. `uv run`, `npx` and `npm
  run` still ask for the network. Any other binary goes in `~/tools/bin`,
  first on `PATH`; downloading it there needs network and write access
  requested for that command. The rules hold on both hosts: whoever
  holds a full link to a public lobby can have packages installed too,
  install scripts included.
- **Their configuration and state** is per project. A command started
  in a project keeps what its programs save under the XDG base
  directories (`~/.config`, `~/.local/share`, `~/.local/state`,
  `~/.cache`) in that project's `.xdg/` instead (`profile.sh`), so a
  `glab auth login` in one project is not the login in another, and it
  survives the recreate. `./project add` and `./update` list `/.xdg/` in
  the project's `.git/info/exclude`, so logins there are never committed.
  Edit them in `projects/HOST/NAME/.xdg/` on the server, or let the model
  log in from the project. Programs that ignore XDG and write elsewhere
  in the home fail, since it is read-only for the model's commands; most
  have a variable for their directory, which goes in `profile.sh`. Git
  keeps the host's configuration (`GIT_CONFIG_GLOBAL` in `compose.yaml`).
- **System packages** you add to the image: list them in
  `EXTRA_PACKAGES` in `.env` (Arch package names) and run `./update`,
  which rebuilds the image when the list changed.

`podman volume rm mevedel-host_private-tools` (with the host stopped)
throws away what the model installed there.

### Reference repositories

Where the model should read a repository but never change it, make it a
reference instead. References are clones in `refs/HOST/NAME/`, outside the
projects, and the container sees them read-only at `refs/` inside the
project. A read-only mount holds even in Full Access, which mevedel's own
read-only paths do not:

```sh
./project ref public website git@github.com:example/api.git
```

```sh
./project unref public website api   # drop one
```

`ref` writes the mounts to `compose.refs.yaml` (generated from `refs/`;
the scripts read it next to `compose.yaml`). A project's first reference
changes its host's mounts, so `ref` restarts that host, and refuses while
it runs a turn; later ones appear right away. Dropping the last one
restarts it likewise. `./project refresh` also brings every reference to
its branch tip (discarding anything else, which only you could have put
there) without a restart. Credentials for private references are
`mevedel`'s on the server, as for `add`; the model never sees them.
`remove` deletes the project's references along with its mounts, and
keeps its other clones in the project it sets aside.

To turn a reference into a repository the model works in, drop it and
clone it; its path changes from `refs/api` to `api`, so update any
instructions in the project that mention it:

```sh
./project unref public website api
./project clone public website git@github.com:example/api.git
```

Another host, i.e. another trust boundary with its own Codex login, is
another service in `compose.yaml` like `public`, with its own volume.

### If something goes wrong

- **Lobby page says "Room closed":** check the relay URL and token in
  `.env`, then run `./update --force`.
- **A host is not running:** `./compose ps`, `./compose logs private`.
- **The nightly update:** `systemctl --user status mevedel-host-update`
  and `journalctl --user -u mevedel-host-update` as `mevedel`.
- **The hourly sync:** `journalctl --user -u mevedel-host-refs` as
  `mevedel`; "could not fetch" usually means the host's credentials in
  `git/HOST` do not reach that repository.
- **Session migrations during update:** `./update` fetches the sources and
  builds the image while the hosts still run, stops both hosts cleanly
  before replacing sources, compiles the new code in one one-off container, and
  runs the standalone session migrator for every served project (including
  any old top-level project). It also checks sessions when source revisions
  are unchanged, so every update briefly interrupts the hosts. Already-current
  sessions are not rewritten. Changed sessions retain the migrator's hidden
  `.migration-backup-SESSION-ID-*/session` backups beside the session directories.
  A migration failure prevents both hosts from starting; inspect the reported
  error and backups, resolve it, then rerun `./update`. Do not remove ownership
  locks or recovery records merely to force an update through. `--force` only
  bypasses the busy-turn check, never the migrator's safety checks. Concurrent
  updater invocations are refused by `.update.lock`.
- **`./setup` says Podman does not work:** check the nesting feature
  (and, if the container's storage cannot do overlayfs, the fuse
  feature), restart the container and run `./deploy` again.
- **A project has no lobby:** `./compose logs public | grep "No lobby"`.
- **A session is refused with "needs a decision in Emacs":** open it once
  via `./attach private`. A crash leaves session locks behind;
  `./compose stop` shuts down cleanly and releases them.

The server's private host has its own project copy and its own sessions;
they do not sync with your desktop.

## Running locally

Copy `.env.example` to `.env`, set `HOST_UID` to `id -u` and
`MEVEDEL_RELAY_URL=ws://127.0.0.1:7466`, run `./update`, add projects and
run `~/Projekte/mevedel/relay/relay` alongside. With Docker instead of
Podman, delete the `userns_mode` line from `compose.yaml`. A phone cannot
reach `127.0.0.1`; use the desktop browser.

## Updating

`./update` fetches the branch tips in `.env` and builds the image if needed
while the hosts still run, so a network or build failure changes nothing.
Then it stops the hosts cleanly, brings `src/` to the fetched tips, compiles
it in a one-off container without network, and migrates each host's project
sessions before recreating the hosts. The hosts mount `src/` read-only: the
compile step is its only writer, so neither host can change code the other
loads. It checks migrations even when sources are unchanged; current sessions
are a no-op, but the hosts still briefly stop. Compilation or migration
failures prevent restart. The command refuses while a turn is running or a
running host does not answer; `--force` overrides only that busy check. Only
pushed commits reach the hosts. The image is rebuilt by itself when
`EXTRA_PACKAGES` or the files it is built from change; `./update --rebuild`
forces it, e.g. for new Emacs or ELPA versions. `init.el` changes need only
`./update`.

`/collab lobby rotate` inside a host (via `./attach`) revokes that lobby's
links; other lobbies are unaffected.
