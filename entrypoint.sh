#!/bin/sh
# Run the daemon.  /src is read-only here; ./update compiles it.
set -eu
exec emacs --fg-daemon=mevedel
