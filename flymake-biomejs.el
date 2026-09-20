;;; flymake-biomejs.el --- Flymake backend for Biome  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Lina Bhaile <emacs-devel@linabee.uk>

;; Author: Lina Bhaile <emacs-devel@linabee.uk>
;; Version: 1.0.0
;; URL: https://github.com/lina-bh/flymake-biomejs
;; Package-Requires: ((emacs "30.1"))
;; Keywords: tools, languages

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Flymake backend for Biome (https://biomejs.dev/), "the toolchain of the web".
;; To set up, add `flymake-biomejs-turn-on' to the appropriate hooks e.g.
;; `js-mode-hook', `typescript-ts-mode-hook', and set `flymake-biomejs-enabled'
;; to t and `flymake-biomejs-program' in the .dir-locals.el file of your
;; project, like so:
;;
;; ((typescript-ts-mode . ((flymake-biomejs-program "npx" "biome")
;;                         (flymake-biomejs-enabled . t))))

;;; Code:

(eval-when-compile
  (require 'cl-lib)
  (require 'subr-x))

(defun flymake-biomejs-program-safe-p (program)
  "Is PROGRAM going to run Biome?"
  (or (equal program '("biome"))
      (and
       (member (car program) '("npx" "pnpx" "bunx" "yarn"))
       (member (car (last program)) '("biome" "@biomejs/biome")))))

(defcustom flymake-biomejs-program '("biome")
  "Biome command.
You can change this to use a command runner; for example, to use npx, set
\(\"npx\" \"biome\")."
  :group 'flymake
  :type '(repeat string)
  :safe #'flymake-biomejs-program-safe-p)

(defcustom flymake-biomejs-enabled nil
  "Whether `flymake-biomejs-turn-on' enables `flymake-biomejs' in this buffer.
This is intended to be used as a directory-local variable, so that you may add
`flymake-biomejs-turn-on' to the default value of `js-mode-hook', etc. and
enable it only in directories in which Biome is the chosen linter."
  :group 'flymake
  :type 'boolean
  :safe 'booleanp
  :local t)

(defvar-local flymake-biomejs--process nil
  "This buffer's Biome process.")

(defun flymake-biomejs--parse-stdout (proc)
  "List of diagnostic plists sorted by line from JSON contents in buffer of PROC."
  (sort (plist-get (with-current-buffer (process-buffer proc)
                     (goto-char (point-min))
                     (json-parse-buffer :object-type 'plist
                                        :array-type 'list))
                   :diagnostics)
        :in-place t
        :key (lambda (diagnostic)
               (thread-first
                 diagnostic
                 (plist-get :location)
                 (plist-get :start)
                 (plist-get :line)))))

(defun flymake-biomejs--parse-diagnostics (buffer proc)
  "List of Flymake diagnostics in BUFFER from stdout of PROC."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (let ((line 1)
            (reports (flymake-biomejs--parse-stdout proc))
            diags)
        (catch 'flymake-biomejs--parse-diagnostics
          (while reports
            (cl-destructuring-bind
                (&key severity message category location &allow-other-keys)
                (pop reports)
              (let* ((start-pos (plist-get location :start))
                     (end-pos (plist-get location :end))
                     (start-line (plist-get start-pos :line))
                     (end-line (plist-get end-pos :line))
                     beg end overrun)
                (setq overrun (forward-line (- start-line line)))
                (cond
                 ;; past the end of the buffer; stop parsing diagnostics.
                 ((> overrun 0) (throw 'flymake-biomejs--parse-diagnostics nil))
                 ;; before the start; drop and continue.
                 ((< overrun 0) (setq line 1))
                 (t
                  ;; FIXME: goto-char may not work as intended with tabs
                  (setq beg (+ (point) (plist-get start-pos :column) -1))
                  (unless (= 0 (forward-line (- (setq line end-line)
                                                start-line)))
                    (throw 'flymake-biomejs--parse-diagnostics nil))
                  (setq end (+ (point) (plist-get end-pos :column) -1))
                  (push (flymake-make-diagnostic
                         buffer beg end
                         (cond
                          ((member severity '("hint" "info")) :note)
                          ((member severity '("error" "fatal")) :error)
                          (t :warning))
                         (list "biome" category message))
                        diags)))))))
        diags))))

(defun flymake-biomejs--make-sentinel (report-fn buffer stderr)
  "Make sentinel for Biome process associated with BUFFER.
Call REPORT-FN with diagnostics, and clean up stdout and STDERR."
  (lambda (proc _event)
    (unwind-protect
        (when (eq 'exit (process-status proc))
          (condition-case e
              ;; swallow case in which the buffer has been killed before Biome
              ;; returns
              (when (buffer-live-p buffer)
                (with-current-buffer buffer
                  (cond
                   ((not (eq proc flymake-biomejs--process))
                    (flymake-log :debug "biomejs %s obsolete" proc))
                   ((buffer-modified-p buffer)
                    ;; Biome does not lint stdin, so the copy on disk must be up
                    ;; to date
                    (funcall report-fn nil :region (cons (point-max)
                                                         (point-max))))
                   (t
                    (funcall report-fn
                             (flymake-biomejs--parse-diagnostics buffer
                                                                 proc))))))
            (t (flymake-log :error "biomejs: %s" e)
               (signal (car e) (cdr e)))))
      (delete-process stderr)
      (kill-buffer (process-buffer proc)))))

(defun flymake-biomejs (report-fn &rest _args)
  "Flymake backend for Biome.  Call Biome and then call REPORT-FN with result."
  (let* ((buffer (current-buffer))
         (filename (buffer-file-name buffer)))
    (if (not (and flymake-biomejs-enabled
                  filename))
        ;; user must revert the buffer if they wish to enable Biome.
        (funcall report-fn :panic
                 :explanation "`flymake-biomejs-enabled' nil in this buffer")
      (when (process-live-p flymake-biomejs--process)
        (kill-process flymake-biomejs--process))
      (if (or (buffer-modified-p buffer)
              (not (verify-visited-file-modtime buffer)))
          ;; Biome has no facility to lint stdin;
          ;; --stdin-file-path=<buffer-file-name> returns the formatted content
          ;; instead.
          (progn
            (setq flymake-biomejs--process nil)
            (funcall report-fn nil :region (cons (point-max)
                                                 (point-max))))
        (let ((stderr (make-pipe-process :name "flymake-biomejs-stderr"
                                         :buffer nil
                                         :noquery t)))
          (setq flymake-biomejs--process
                (make-process
                 :name "flymake-biomejs"
                 :noquery t
                 :connection-type 'pipe
                 :buffer (generate-new-buffer " *flymake-biomejs*" t)
                 :command (append
                           flymake-biomejs-program
                           (list
                            "check"
                            "--reporter=json"
                            filename))
                 :sentinel (flymake-biomejs--make-sentinel report-fn
                                                           buffer
                                                           stderr)
                 :stderr stderr))
          (process-send-eof flymake-biomejs--process))))))

;;;###autoload
(defun flymake-biomejs-turn-on ()
  "Turn on `flymake-biomejs' in this buffer."
  (interactive)
  (add-hook 'flymake-diagnostic-functions #'flymake-biomejs nil t))

(provide 'flymake-biomejs)
;;; flymake-biomejs.el ends here
