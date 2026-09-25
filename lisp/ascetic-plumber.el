;;; ascetic-plumber.el --- Plan 9 inspired completion routing -*- lexical-binding: t -*-

;; Copyright (C) 2026 Jacopo Costantini

;; Author: Jacopo Costantini <jacopocostantini32@gmail.com>
;; Package-Requires: ((emacs "30.0"))

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Pure router for Emacs completions.
;; Routes candidate streams to stdin of processes or Lisp sinks,
;; decoupling the selection mechanism from the final action.
;;
;; With `ascetic-read' loaded, takes RET in its minibuffer map.

;;; Code:

(defgroup ascetic-plumber nil
  "Plan 9 inspired completion routing."
  :group 'minibuffer)

(defcustom ascetic-plumber-actions
  '((file   . ((">" . ascetic-plumber-action-dired)))
    (buffer . ((">" . ascetic-plumber-action-ibuffer)
               ("!" . ascetic-plumber-action-kill-buffers)))
    (t      . (("<" . ascetic-plumber-action-insert)
               (">" . ascetic-plumber-action-print)
               ("!" . ascetic-plumber-action-shell-async)
               ("|" . ascetic-plumber-action-shell-sync))))
  "Routing table mapping categories and operators to sinks."
  :type '(alist :key-type symbol :value-type alist)
  :group 'ascetic-plumber)

(defcustom ascetic-plumber-operator-export " > "
  "Operator string to export to Lisp UI."
  :type 'string
  :group 'ascetic-plumber)

(defcustom ascetic-plumber-operator-insert " < "
  "Operator string to insert raw text."
  :type 'string
  :group 'ascetic-plumber)

(defcustom ascetic-plumber-operator-bang " ! "
  "Operator string for asynchronous shell pipes."
  :type 'string
  :group 'ascetic-plumber)

(defcustom ascetic-plumber-operator-pipe " | "
  "Operator string for synchronous shell pipes."
  :type 'string
  :group 'ascetic-plumber)

(defun ascetic-plumber-action-insert (_cmd candidates _category)
  "Insert CANDIDATES into the buffer as raw text.
Arguments _CMD and _CATEGORY are ignored."
  (insert (mapconcat #'identity candidates " ")))

(defun ascetic-plumber-action-print (_cmd candidates _category)
  "Dump CANDIDATES into a dedicated stream buffer.
Arguments _CMD and _CATEGORY are ignored."
  (let ((buf (get-buffer-create "*Plumber Stream*")))
    (with-current-buffer buf
      (erase-buffer)
      (insert (mapconcat #'identity candidates "\n")))
    (display-buffer buf)))

(defun ascetic-plumber-action-dired (_cmd candidates _category)
  "Materialize file CANDIDATES into a Dired buffer.
Arguments _CMD and _CATEGORY are ignored."
  (dired (cons default-directory candidates)))

(defun ascetic-plumber-action-ibuffer (_cmd candidates _category)
  "Materialize buffer CANDIDATES into an Ibuffer window.
Arguments _CMD and _CATEGORY are ignored."
  (ibuffer nil "*Plumber Buffers*"
           `((name . ,(concat "\\`" (regexp-opt candidates) "\\'")))))

(defun ascetic-plumber-action-kill-buffers (cmd candidates _category)
  "Kill CANDIDATES buffers if CMD is 'kill'.
Argument _CATEGORY is ignored."
  (if (string= (string-trim cmd) "kill")
      (progn (mapc #'kill-buffer candidates)
             (message "Ascetic Plumber: Killed %d buffers." (length candidates)))
    (user-error "Ascetic Plumber: Unknown buffer command '%s'" cmd)))

(defun ascetic-plumber-action-shell-async (cmd candidates _category)
  "Stream CANDIDATES to CMD via STDIN asynchronously.
Creates a dedicated output buffer.  Argument _CATEGORY is ignored."
  (unless (string-empty-p cmd)
    (let* ((buf (generate-new-buffer "*Plumber Async*"))
           (proc (make-process
                  :name "ascetic-plumber"
                  :buffer buf
                  ;; commit already trimmed CMD
                  :command (list shell-file-name shell-command-switch cmd)
                  :connection-type 'pipe
                  :file-handler t)))
      (process-send-string proc (concat (mapconcat #'identity candidates "\n") "\n"))
      (process-send-eof proc)
      (display-buffer buf))))

(defun ascetic-plumber-action-shell-sync (cmd candidates _category)
  "Stream CANDIDATES to CMD via STDIN synchronously.
Inserts the command output into the current buffer.
Argument _CATEGORY is ignored."
  (unless (string-empty-p cmd)
    (let ((clean-cmd (string-trim cmd))
          (input-data (concat (mapconcat #'identity candidates "\n") "\n"))
          (target-buf (current-buffer)))
      (with-temp-buffer
        (insert input-data)
        (shell-command-on-region (point-min) (point-max) clean-cmd (current-buffer) t)
        (let ((output (buffer-string)))
          (with-current-buffer target-buf
            (insert output)))))))

(defun ascetic-plumber--parse-input (input)
  "Parse INPUT string based on declared operators.
Returns a list of (operator query command).
Matches the rightmost operator to prevent paths with embedded operators
from triggering false positives."
  (let* ((ops (list ascetic-plumber-operator-export
                    ascetic-plumber-operator-insert
                    ascetic-plumber-operator-bang
                    ascetic-plumber-operator-pipe))
         ;; Regex matches: (greedy everything)(operator)(everything to end)
         (lexer-rx (concat "\\(.*\\)\\(" (mapconcat #'regexp-quote ops "\\|") "\\)\\(.*\\)\\'")))
    (if (string-match lexer-rx input)
        (list (match-string 2 input)
              (match-string 1 input)
              (match-string 3 input))
      nil)))

(defun ascetic-plumber--harvest (query)
  "Extract truth from native completion metadata for QUERY.
Returns a list containing the category, base string, and candidates."
  (let* ((metadata (completion-metadata query minibuffer-completion-table minibuffer-completion-predicate))
         (category (completion-metadata-get metadata 'category))
         (raw      (completion-all-completions query minibuffer-completion-table minibuffer-completion-predicate (length query)))
         (tail     (last raw))
         (base-size (if (and tail (numberp (cdr tail))) (cdr tail) 0)))
    (when (and tail (numberp (cdr tail))) (setcdr tail nil))
    (list category
          (substring query 0 (min base-size (length query)))
          (mapcar #'substring-no-properties raw))))

(declare-function ascetic-read-exit "ascetic-read")

(defun ascetic-plumber-commit ()
  "Hijack RET, parse intent, and dispatch to appropriate sinks.
If no operator is matched, soft-fallbacks to native completion exit."
  (interactive)
  (let* ((content (minibuffer-contents-no-properties))
         (plumb   (ascetic-plumber--parse-input content)))
    (if (not plumb)
        (ascetic-read-exit)
      (let* ((operator   (string-trim (nth 0 plumb)))
             (query      (string-trim (nth 1 plumb)))
             (cmd        (string-trim (nth 2 plumb)))
             (harvested  (ascetic-plumber--harvest query))
             (category   (nth 0 harvested))
             (base-str   (nth 1 harvested))
             (candidates (nth 2 harvested))
             (cat-rules  (or (alist-get category ascetic-plumber-actions)
                             (alist-get t ascetic-plumber-actions)))
             (sink-fn    (or (alist-get operator cat-rules nil nil #'string=)
                             (alist-get operator (alist-get t ascetic-plumber-actions) nil nil #'string=)))
             (ctx-dir    (expand-file-name base-str default-directory))
             (target-buf (window-buffer (minibuffer-selected-window))))
        (unless sink-fn
          (user-error "No action mapped for category '%s' and operator '%s'" category operator))
        (unless (eq minibuffer-history-variable t)
          (add-to-history minibuffer-history-variable content))
        ;; Dispatch action asynchronously to break out of the minibuffer jail
        (run-at-time 0 nil
                     (lambda (dir buf fn c cand cat)
                       (condition-case err
                           (let ((default-directory dir))
                             (with-current-buffer buf
                               (funcall fn c cand cat)))
                         (error (message "Ascetic Plumber Error: %s" (error-message-string err)))))
                     ctx-dir target-buf sink-fn cmd candidates category)
        (abort-recursive-edit)))))

;; --- Integration ---

;; The read map is shared: bind once, not per session.
(with-eval-after-load 'ascetic-read
  (keymap-set ascetic-read-map "RET" #'ascetic-plumber-commit))

(provide 'ascetic-plumber)
;;; ascetic-plumber.el ends here
