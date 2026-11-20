# Sourced by the scripts: run as the folder's owner, read .env and pick
# the container runtime.

self=$(readlink -f "$0")
cd "$(dirname "$self")"

# Rootless containers belong to one user and git refuses another user's
# clones, so root (an ssh or console login) becomes the owner instead.
owner=$(stat -c %U .)
if [ "$(id -un)" != "$owner" ]; then
  if [ "$(id -u)" != 0 ]; then
    echo "run this as $owner" >&2
    exit 1
  fi
  # Root's session variables would point Podman at root's runtime directory.
  exec runuser -u "$owner" -- env -u XDG_RUNTIME_DIR -u DBUS_SESSION_BUS_ADDRESS \
    HOME="$(getent passwd "$owner" | cut -d: -f6)" USER="$owner" LOGNAME="$owner" \
    "$self" "$@"
fi

set -a; . ./.env; set +a
runtime=${CONTAINER:-$(command -v podman >/dev/null && echo podman || echo docker)}

if [ "$runtime" = podman ]; then
  # Without a login session (su, sudo, root above) Podman would look for
  # the containers and the user's systemd somewhere else.
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
  # `podman compose' prefers docker-compose when both are installed, which
  # needs a Podman socket; podman-compose talks to podman directly.
  if command -v podman-compose >/dev/null; then
    export PODMAN_COMPOSE_PROVIDER="${PODMAN_COMPOSE_PROVIDER:-podman-compose}"
    export PODMAN_COMPOSE_WARNING_LOGS=false
  fi
fi

# Every compose call, the scripts' own and the systemd units', sees the
# projects' reference mounts too.
[ -e compose.refs.yaml ] || echo "services: {}" > compose.refs.yaml
export COMPOSE_FILE=compose.yaml:compose.refs.yaml

# The hosts are compose's services.  Each serves a directory of projects,
# <HOST>_PROJECTS in .env.
hosts() { "$runtime" compose config --services; }
projects_dir() { # HOST
  eval "printf %s \"\${$(printf %s "$1" | tr a-z- A-Z_)_PROJECTS:-./projects/$1}\""
}
# The runtime would create a missing mount source or point itself, owned by
# a subordinate uid you cannot delete (and a missing file as a directory),
# so they exist before every start:
# - a project's reference repositories, clones in refs/HOST/NAME, mounted
#   read-only at /projects/NAME/refs by compose.refs.yaml, which ./project
#   writes;
# - each host's git configuration and credentials in git/HOST, mounted
#   read-only at ~/.config/git, so the model cannot change them.
prepare_mounts() {
  sed -n 's|^ *- *\./refs/\([^/:]*\)/\([^/:]*\):.*|\1 \2|p' compose.refs.yaml |
    while read -r host name; do
      mkdir -p "refs/$host/$name" "$(projects_dir "$host")/$name/refs"
    done
  for host in $(hosts); do
    [ ! -e "git/$host/config" ] || continue
    mkdir -p "git/$host"
    sed "s/HOST/$host/g" > "git/$host/config" <<'EOF'
# The HOST host's git configuration, ~/.config/git/config in its container
# (read-only there).  Written once by the scripts; edit it here.
#
[user]
	# No identity of the host's own: the model commits as the person it
	# commits for (git -c user.name=... -c user.email=... commit), so they
	# are author and committer both, and a plain commit fails instead of
	# falling back to mevedel@mevedel-HOST.
	useConfigOnly = true
[pull]
	ff = only
[push]
	autoSetupRemote = true
[fetch]
	prune = true

# Credentials for pushing from the container, readable by the model and
# by whoever holds a full or owner link to the HOST host's lobbies; scope
# them to the repositories it works on.  ~/.ssh is hidden from the model's
# commands, so ssh keys go in this folder with an ssh_config naming one
# per server, e.g.
#   UserKnownHostsFile ~/.config/git/known_hosts
#   IdentitiesOnly yes
#   Host github.com github.com-*
#     HostName github.com
#     IdentityFile ~/.config/git/id_github
#   Host git.scicore.unibas.ch
#     Port 2222
#     IdentityFile ~/.config/git/id_gitlab
# and the servers' host keys:
#   ssh-keyscan github.com > git/HOST/known_hosts
#   ssh-keyscan -p 2222 git.scicore.unibas.ch >> git/HOST/known_hosts
# then uncomment these lines.
#[core]
#	sshCommand = ssh -F ~/.config/git/ssh_config
EOF
  done
}
# Keep PATH out of the project's own repository, if it has one, without
# changing its tracked .gitignore.  Writing the file runs nothing.  Every
# project excludes /.xdg/, its programs' configuration (profile.sh).
exclude() { # DIR PATH
  [ -d "$1/.git" ] || return 0
  mkdir -p "$1/.git/info"
  grep -qxF "$2" "$1/.git/info/exclude" 2>/dev/null ||
    echo "$2" >> "$1/.git/info/exclude"
}
running() { # HOST
  [ "$("$runtime" inspect -f '{{.State.Running}}' "mevedel-$1" 2>/dev/null)" = true ]
}
# A running host whose daemon does not answer counts as busy: silence is no
# evidence that no turn is running.  A stopped host is idle.
busy() { # HOST
  busy_answer=$("$runtime" exec "mevedel-$1" emacsclient -s mevedel \
    -e '(mevedel-host-busy-p)' 2>/dev/null) || { running "$1"; return; }
  [ "$busy_answer" = t ]
}
