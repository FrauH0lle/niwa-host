# Headless mevedel host image: Emacs and dependencies only.  mevedel and
# gptel are git clones under src/, compiled by ./update and mounted
# read-only at /src,
# so updating them needs ./update, not a rebuild.  `./update --rebuild'
# rebuilds when Emacs or the ELPA dependencies change; ./update rebuilds by
# itself when EXTRA_PACKAGES in .env changes.
FROM docker.io/library/archlinux:latest

# mevedel's requirements (README): Python for the Claude MCP bridge, npm
# for its managed ACP adapter, Bubblewrap for Bash confinement, Poppler and
# ImageMagick for reading PDFs and images, diff for settling a turn's edits
# (the base image has none).  OpenSSH for git over ssh.  uv for the
# projects' Python environments.  base-devel (gcc, make, patch, which) and
# unzip for the model's own commands, e.g. Python and npm packages that
# compile native code on install; its sudo grants mevedel nothing.
RUN pacman -Syu --noconfirm --needed emacs-nox git openssh ripgrep nodejs npm \
      bash ca-certificates curl util-linux diffutils python uv bubblewrap \
      poppler imagemagick base-devel unzip \
 && pacman -Scc --noconfirm

# Your uid (HOST_UID in .env), so the projects and src/ stay yours.  The
# state and tools directories and the parent of the git configuration's
# mount exist up front: the runtime would otherwise create them owned by
# root.
ARG HOST_UID=1000
RUN useradd -m -u "$HOST_UID" -s /bin/bash mevedel \
 && install -d -o mevedel -g mevedel /home/mevedel/.emacs.d /home/mevedel/.config \
      /home/mevedel/tools

COPY install.el /opt/install.el
RUN emacs --batch -l /opt/install.el && chown -R mevedel:mevedel /opt/elpa

COPY compile.el entrypoint.sh /opt/

# Further Arch packages the projects need (EXTRA_PACKAGES in .env).  The
# model cannot install system packages itself; the label tells ./update
# which list this image was built with.
ARG EXTRA_PACKAGES=
LABEL mevedel-host.extra-packages="$EXTRA_PACKAGES"
RUN [ -z "$EXTRA_PACKAGES" ] \
 || { pacman -Syu --noconfirm --needed $EXTRA_PACKAGES && pacman -Scc --noconfirm; }

USER mevedel
# The native Claude Code CLI; mevedel keeps it updated from here.  Its
# login lives on the state volume (CLAUDE_CONFIG_DIR in compose.yaml).
RUN curl -fsSL https://claude.ai/install.sh | bash
# What the model installs outside a project (uv's Pythons and tools,
# `npm install -g') goes to the tools volume, which only its install
# commands may write (init.el), so it survives the nightly recreate.  The
# caches go to /tmp, which all its commands may write; the rest of the home
# is read-only for them.
ENV PATH=/home/mevedel/tools/bin:/home/mevedel/tools/npm/bin:/home/mevedel/.local/bin:$PATH \
    UV_PYTHON_INSTALL_DIR=/home/mevedel/tools/python \
    UV_PYTHON_BIN_DIR=/home/mevedel/tools/bin \
    UV_TOOL_DIR=/home/mevedel/tools/uv \
    UV_TOOL_BIN_DIR=/home/mevedel/tools/bin \
    UV_CACHE_DIR=/tmp/uv-cache \
    UV_LINK_MODE=copy \
    NPM_CONFIG_PREFIX=/home/mevedel/tools/npm \
    NPM_CONFIG_CACHE=/tmp/npm-cache
WORKDIR /projects
ENTRYPOINT ["/opt/entrypoint.sh"]
# The kit files this image was built from, so ./update notices changes.
ARG KIT=
LABEL mevedel-host.kit="$KIT"
