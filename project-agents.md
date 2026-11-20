# Git on this host

This workspace runs on a shared server; people also work on its
repositories from their own machines. The repositories here are ordinary
clones you may change, commit and push; only `refs/`, where present, is
read-only context.

- Before changing a repository or creating a branch, `git pull` it. The
  server syncs only hourly, so it may be behind what someone pushed.
- Make each coherent change on its own branch (e.g. `docs/frontend-stack`),
  never on the default branch. Push the branch and pass on the link for
  opening a pull or merge request. Do not push to a branch someone else is
  working on.
- Before committing, ask whom to commit as, unless the request says so, and
  commit as them, e.g.
  `git -c user.name='Roland Goers' -c user.email=roland.goers@swisstph.ch commit`.
  This host has no identity of its own, so a plain `git commit` fails.
  - Roland Goers <roland.goers@swisstph.ch>
  - Myroslava Volosko <myroslava.volosko@swisstph.ch>
- `git fetch` and `git pull` have network access; `git push` needs it
  requested for the command.
- Install Python packages with uv (`uv add`, `uv sync`, `uv tool install`)
  and Node packages with npm (`npm install`, `npm install -g`); these
  have network access. Put any other binary in `~/tools/bin`: it is on
  `PATH` and survives restarts, but writing there (and downloading) needs
  permissions requested for the command. There is no root here, so for a
  system package (pacman) ask the user to add it to the host's image.
- Programs' configuration and state (e.g. glab's login) live in this
  project's `.xdg/` (`$XDG_CONFIG_HOME` and friends), not in `~/.config`;
  read them there.
- Store project memories in `.agents/memory/`, not `.mevedel/memory/`, so
  they can be shared via git and used by other agent tools.
