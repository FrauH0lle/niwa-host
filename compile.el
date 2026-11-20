;;; compile.el --- Byte-compile the mounted sources when they changed -*- lexical-binding: t; -*-

;; niwa finds its prompts, agents and editor bundle next to its own
;; files, so bytecode is written beside the sources.  Any change recompiles
;; everything from that repository on, gptel before niwa: inlined struct
;; accessors and macros make a partial recompile unsafe.

(require 'package)
(setq package-user-dir "/opt/elpa"
      byte-compile-warnings nil)
(package-initialize)

;; `byte-compile-file' reports failure by its value; make it stop the update.
(require 'bytecomp)
(advice-add 'byte-compile-file :around
            (lambda (compile file &rest args)
              (or (apply compile file args)
                  (error "Compilation failed: %s" file))))

(defconst host--repos '("/src/gptel" "/src/niwa"))

(defun host--sources (dir)
  "Return DIR's top-level Elisp sources."
  (seq-remove (lambda (file)
                (string-match-p "-\\(?:pkg\\|autoloads\\)\\.el\\'" file))
              (directory-files dir t "\\`[^.#].*\\.el\\'")))

(dolist (dir host--repos)
  (add-to-list 'load-path dir t))

(let (stale)
  (dolist (dir host--repos)
    ;; Bytecode whose source is gone would still satisfy `require'.
    (dolist (elc (directory-files dir t "\\.elc\\'"))
      (unless (file-exists-p (file-name-with-extension elc "el"))
        (delete-file elc)))
    (when (or stale
              (seq-some (lambda (el)
                          (file-newer-than-file-p el (concat el "c")))
                        (host--sources dir)))
      (setq stale t)
      (message "Compiling %s" dir)
      ;; Old bytecode would otherwise be what `require' loads while its
      ;; dependents compile, baking stale macros into them.
      (dolist (elc (directory-files dir t "\\.elc\\'"))
        (delete-file elc))
      (dolist (el (host--sources dir))
        (byte-compile-file el)))))
