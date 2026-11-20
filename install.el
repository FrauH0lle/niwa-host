;;; install.el --- Image build: ELPA dependencies -*- lexical-binding: t; -*-

;; Dependencies live in /opt/elpa, not ~/.emacs.d, so the state volume
;; mounted over ~/.emacs.d never hides or pins them.  gptel and niwa
;; come from the mounted clones.
(require 'package)
(setq package-user-dir "/opt/elpa"
      package-archives '(("gnu" . "https://elpa.gnu.org/packages/")
                         ("nongnu" . "https://elpa.nongnu.org/nongnu/")
                         ("melpa" . "https://melpa.org/packages/")))
(package-initialize)
(package-refresh-contents)
(dolist (pkg '(compat acp yaml orderless websocket qrencode))
  (unless (package-installed-p pkg)
    (package-install pkg)))
