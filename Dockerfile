# Headless niwa host image: Emacs and dependencies only.  niwa and
# gptel are git clones under src/, compiled by ./update and mounted
# read-only at /src,
# so updating them needs ./update, not a rebuild.  `./update --rebuild'
# rebuilds when Emacs or the ELPA dependencies change; ./update rebuilds by
# itself when EXTRA_PACKAGES in .env changes.
FROM docker.io/library/archlinux:latest

# niwa's requirements (README): Python for the Claude MCP bridge, npm
# for its managed ACP adapter, Bubblewrap for Bash confinement, Poppler and
# ImageMagick for reading PDFs and images, diff for settling a turn's edits
# (the base image has none).  OpenSSH for git over ssh.  uv for the
# projects' Python environments.  base-devel (gcc, make, patch, which) and
# unzip for the model's own commands, e.g. Python and npm packages that
# compile native code on install; its sudo grants niwa nothing.
RUN pacman -Syu --noconfirm --needed emacs-nox git openssh ripgrep nodejs npm \
      bash ca-certificates curl util-linux diffutils python uv bubblewrap \
      poppler imagemagick base-devel unzip \
 && pacman -Scc --noconfirm

# Your uid (HOST_UID in .env), so the projects and src/ stay yours.  The
# state and tools directories and the parent of the git configuration's
# mount exist up front: the runtime would otherwise create them owned by
# root.
ARG HOST_UID=1000
RUN useradd -m -u "$HOST_UID" -s /bin/bash niwa \
 && install -d -o niwa -g niwa /home/niwa/.emacs.d /home/niwa/.config \
      /home/niwa/tools

COPY install.el /opt/install.el
RUN emacs --batch -l /opt/install.el && chown -R niwa:niwa /opt/elpa

COPY compile.el entrypoint.sh /opt/

# Further Arch packages the projects need (EXTRA_PACKAGES in .env).  The
# model cannot install system packages itself; the label tells ./update
# which list this image was built with.
ARG EXTRA_PACKAGES=
LABEL niwa-host.extra-packages="$EXTRA_PACKAGES"
RUN [ -z "$EXTRA_PACKAGES" ] \
 || { pacman -Syu --noconfirm --needed $EXTRA_PACKAGES && pacman -Scc --noconfirm; }

USER niwa
# The native Claude Code CLI; niwa keeps it updated from here.  Its
# login lives on the state volume (CLAUDE_CONFIG_DIR in compose.yaml).
RUN curl -fsSL https://claude.ai/install.sh | bash
# What the model installs outside a project (uv's Pythons and tools,
# `npm install -g') goes to the tools volume, which only its install
# commands may write (init.el), so it survives the nightly recreate.  The
# caches go to /tmp, which all its commands may write; the rest of the home
# is read-only for them.
ENV PATH=/home/niwa/tools/bin:/home/niwa/tools/npm/bin:/home/niwa/.local/bin:$PATH \
    UV_PYTHON_INSTALL_DIR=/home/niwa/tools/python \
    UV_PYTHON_BIN_DIR=/home/niwa/tools/bin \
    UV_TOOL_DIR=/home/niwa/tools/uv \
    UV_TOOL_BIN_DIR=/home/niwa/tools/bin \
    UV_CACHE_DIR=/tmp/uv-cache \
    UV_LINK_MODE=copy \
    NPM_CONFIG_PREFIX=/home/niwa/tools/npm \
    NPM_CONFIG_CACHE=/tmp/npm-cache
WORKDIR /projects
ENTRYPOINT ["/opt/entrypoint.sh"]
# The kit files this image was built from, so ./update notices changes.
ARG KIT=
LABEL niwa-host.kit="$KIT"
