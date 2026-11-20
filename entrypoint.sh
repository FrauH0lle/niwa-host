#!/bin/sh
# Compile the mounted sources, one container at a time, then run the daemon.
set -eu
flock /src/.compile.lock emacs --batch -l /opt/compile.el
exec emacs --fg-daemon=mevedel
