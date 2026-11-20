;;; init.el --- Headless niwa host -*- lexical-binding: t; -*-

;;; Commentary:

;; Runs inside each container as `emacs --fg-daemon=niwa'.  Mirrors the
;; desktop's Codex backend and GPT-6 preset from site-lisp, then opens a
;; lobby for each project in /projects.  Every service shares this file;
;; what differs between them is the projects and the state volume, which
;; holds that service's own Codex login.  Mounted read-only,
;; so edits here need only a restart.

;;; Code:

;; Packages are native-compiled in the background on first load; their
;; warnings are about load order, not about this host.
(setq native-comp-async-report-warnings-errors 'silent)

;; Unattended turns allocate heavily; at the default threshold the GC storms
;; look like niwa being slow.
(setq gc-cons-threshold (* 64 1024 1024)
      gc-cons-percentage 0.2)

(require 'package)
(setq package-user-dir "/opt/elpa"
      ;; ./update compiles /src; never load stale bytecode.
      load-prefer-newer t)
(package-initialize)
(add-to-list 'load-path "/src/gptel")
(add-to-list 'load-path "/src/niwa")


;;
;;; gptel

(require 'gptel)
(require 'gptel-openai-oauth)
(require 'org-id)

(setq gptel-include-tool-results t
      ;; There is no browser here for the localhost callback.
      gptel-openai-oauth-login-method 'device)

(defvar-local +gptel-codex-session-id nil
  "Session identifier sent to the Codex backend.")

(defun +gptel--codex-header (info)
  "Return Codex authentication headers for request INFO."
  (append (gptel--openai-oauth-header info)
          `(("session-id" .
             ,(with-current-buffer (plist-get info :buffer)
                (or +gptel-codex-session-id
                    (setq +gptel-codex-session-id (org-id-uuid))))))))

(setq gptel-model 'gpt-6.1-sol
      gptel-backend
      (gptel-make-openai-oauth "Codex"
        :header #'+gptel--codex-header
        :models '((gpt-6-astra
                   :description "The very best model for coding and agentic tasks"
                   :capabilities (media tool-use json url responses-api)
                   :reasoning-effort (member low medium high xhigh max)
                   :mime-types ("image/jpeg" "image/png" "image/gif" "image/webp")
                   :context-window 258 :input-cost 10 :output-cost 50
                   :cutoff-date "2026-04")
                  (gpt-6.1-sol
                   :description "The best model for coding and agentic tasks"
                   :capabilities (media tool-use json url responses-api)
                   :reasoning-effort (member none low medium high xhigh max)
                   :mime-types ("image/jpeg" "image/png" "image/gif" "image/webp")
                   :context-window 258 :input-cost 2 :output-cost 10
                   :cutoff-date "2026-04")
                  (gpt-6-luna
                   :description "Fastest, cheapest version of GPT-5.6"
                   :capabilities (media tool-use json url responses-api)
                   :reasoning-effort (member none low medium high xhigh max)
                   :mime-types ("image/jpeg" "image/png" "image/gif" "image/webp")
                   :context-window 258 :input-cost 0.1 :output-cost 0.5
                   :cutoff-date "2026-05"))))


;;
;;; niwa

(require 'niwa)
(setq niwa-empty-tag-query-matches-all nil
      niwa-permission-reviewer 'auto
      niwa-permission-mode 'edits
      ;; Sessions are the host's history; never clean them up by age.
      niwa-session-max-age-days nil
      niwa-memory-consolidation-mode 'auto
      niwa-collaboration-relay-url (getenv "NIWA_RELAY_URL")
      niwa-collaboration-relay-host-token
      (let ((token (getenv "NIWA_RELAY_HOST_TOKEN")))
        (and token (not (string-empty-p token)) token)))
(niwa-install)

;; The repositories in /projects are workspaces: the model branches, commits
;; and pulls there, all of which write .git.  niwa keeps .git read-only
;; so that a planted hook or config cannot run when git is used outside the
;; sandbox; here that outside is this container, which whoever holds a full
;; lobby link can already command, and the server's scripts never run git
;; in these repositories (`./project refresh' syncs them in here).
(require 'niwa-permission-rules)
(setq niwa-protected-paths
      (assoc-delete-all "**/.git/**" (copy-tree niwa-protected-paths)))
;; Fetching and pulling need the network, which commands lack by default.
;; Pushing still asks for it, so the reviewer sees what leaves the host.
(dolist (command '("git fetch" "git pull" "git -C * fetch" "git -C * pull"))
  (dolist (pattern (list command (concat command " *")))
    (add-to-list 'niwa-permission-rules
                 `("Bash" :pattern ,pattern :network t :action allow) t)))
;; Installing with uv and npm needs the network too, and may write the
;; tools volume: uv's Pythons and tools and `npm install -g' go there
;; (Dockerfile), outside the projects.  What a package's install scripts do
;; with that network is up to the package; `uv run', `npx' and `npm run'
;; still ask for it.
(dolist (command '("uv sync" "uv lock" "uv add" "uv remove" "uv venv"
                   "uv pip install" "uv pip sync" "uv python install"
                   "uv tool install" "uv tool upgrade"
                   "npm install" "npm i" "npm ci" "npm update"))
  (dolist (pattern (list command (concat command " *")))
    (add-to-list 'niwa-permission-rules
                 `("Bash" :pattern ,pattern :network t
                   :file-system ((:path "/home/niwa/tools" :access write
                                  :recursive t))
                   :action allow)
                 t)))

;; Struct setters must be available when the preset body is expanded.
(require 'gptel-request)
(niwa-define-preset niwa-gpt6
    :description "GPT-6: Sol lead and workers, Astra review, Luna exploration"
    :parents (niwa-implement)
    :backend "Codex"
    :model 'gpt-6.1-sol
    :reasoning-effort 'high
    :model-tiers
    ((fast :provider "Codex:gpt-6-luna" :effort xhigh)
     (balanced :provider "Codex:gpt-6.1-sol" :effort high)
     (strong :provider "Codex:gpt-6-astra" :effort high))
    :model-workloads
    ((planning :tier balanced :effort xhigh)
     (plan-implementation :tier balanced)
     (goal-review :tier balanced :effort xhigh)
     (worker :tier balanced)
     (explorer :tier fast)
     (verifier :tier balanced)
     (reviewer :tier strong)
     (naming :tier fast :effort none)
     (guardian :tier balanced :effort low)
     (buddy :tier balanced :effort medium)
     (journal :tier balanced :effort medium)
     (memory :tier balanced :effort medium)
     (summarization :tier balanced :effort medium)))
(setq niwa-default-chat-preset 'implement)
(setf (alist-get 'implement niwa-action-preset-alist) 'niwa-gpt6)


;;
;;; Lobby

(require 'niwa-collaboration-lobby)

;; Full links, the ones passed to colleagues, get the same skills and
;; commands as owner links; unsafe commands stay refused for both.
(setq niwa-collaboration-guest-skills '((full . t) (owner . t)))

(defun niwa-host-open-lobbies ()
  "Open a lobby for every project directory in /projects.
A directory that is no niwa workspace is reported and skipped, so
one stray directory does not keep the others' lobbies closed."
  (dolist (dir (directory-files "/projects" t "\\`[^.]"))
    (when (file-directory-p dir)
      (condition-case err
          (niwa-collaboration-lobby-start dir)
        (error (message "No lobby for %s: %s"
                        dir (error-message-string err)))))))

(niwa-host-open-lobbies)

(defun niwa-host-busy-p ()
  "Return non-nil while restarting would interrupt niwa work here.
`./update' asks this before restarting the daemon.  Besides running turns,
niwa counts idle sessions with a live command or Monitor and active Goals."
  ;; Older niwa lacks the restart predicate; fall back to running turns.
  (if (fboundp (quote niwa-restart-unsafe-p))
      (niwa-restart-unsafe-p)
    (niwa-busy-p)))

;;; init.el ends here
