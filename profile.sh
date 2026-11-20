# Each project's own program configuration.  compose.yaml mounts this as
# /etc/profile.d/mevedel-project.sh, which login shells read; mevedel runs
# the model's commands in one (`bash -lc'), all but the read-only ones such
# as cat or ls.  A command started anywhere in /projects/NAME keeps its
# programs' configuration, data, state and cache in /projects/NAME/.xdg, so
# one project's glab login or uv settings never apply in another, and they
# survive the nightly recreate.  Programs that follow the XDG base
# directories create them there; the rest of the home is read-only for the
# model's commands.
case $PWD/ in
  /projects/?*/*)
    xdg=${PWD#/projects/}
    xdg=/projects/${xdg%%/*}/.xdg
    export XDG_CONFIG_HOME="$xdg/config" XDG_DATA_HOME="$xdg/share" \
           XDG_STATE_HOME="$xdg/state" XDG_CACHE_HOME="$xdg/cache"
    unset xdg ;;
esac
