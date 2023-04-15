;;; treebund-tests.el --- Bundle related git-worktrees together -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: MIT

;;; Code:

(require 'ert)

(require 'treebund)


;;; Logging:
(setq ert-quiet nil)

(setq treebund-test-logging nil)

(when treebund-test-logging
  (defun treebund--gitlog (type &rest msg)
    "Override the logging method to write to a file instead of buffer."
    (with-temp-buffer
      (goto-char (point-max))
      (cond ((eq 'command type)
             (insert "==> git " (string-join msg " ") ?\n))
            ((eq 'output type)
             (let ((msg (apply #'format msg)))
               (when (length= msg 0)
                 (setq msg " "))
               (insert msg))
             (newline 2)))
      (append-to-file nil nil (expand-file-name "treebund-test-git.log" temporary-file-directory)))))


;;; Environment:
(setq treebund-test--dir (expand-file-name "treebund-tests" temporary-file-directory))
(setq treebund-remote--dir (file-name-concat treebund-test--dir "remote"))

(defun treebund-test--setup-branch (name origin-path &optional num-commits)
  (let ((worktree-path (expand-file-name name treebund-remote--dir)))
    (treebund--git "clone" origin-path worktree-path)
    (treebund--git-with-repo worktree-path
      "checkout" "-b" name)
    (dotimes (i (or num-commits 3))
      (let ((test-file (expand-file-name "some-file" worktree-path)))
        (with-temp-buffer
          (insert i)
          (write-file test-file))
        (treebund--git-with-repo worktree-path
          "add" test-file)
        (treebund--git-with-repo worktree-path
          "commit" "-m" (concat "commit-" (int-to-string i)))))
    (treebund--git-with-repo worktree-path "push" "--set-upstream" "origin" name)
    (delete-directory worktree-path t)))

(defun treebund-test--setup-remote (name branches)
  "Setup simulated remote.
NAME is the name of the remote repository.

BRANCHES is a list of branch names to be created in this
remote. Each branch will have 2 commits added."
  (let ((origin-path (expand-file-name (concat name ".git") treebund-remote--dir)))
    (treebund--git "init" "--bare" origin-path)
    (dolist (branch branches)
      (treebund-test--setup-branch branch origin-path 3))
    (make-directory treebund-bare-dir t)))

(defun treebund-test--setup (remotes)
  "Setup testing environment.
REMOTES is a list of cons cells of remote names to a list of
branch names. For example:

\\='((\"origin-one\" . (\"branch-one\" \"branch-two\")) 
  (\"origin-two\" . (\"branch-one\")))

Each created branch will have 2 commits."
  ; Create temp directory.
  (when (file-directory-p treebund-test--dir)
    (delete-directory treebund-test--dir t))
  (make-directory treebund-test--dir)
  (make-directory treebund-workspace-root)
  (make-directory treebund-remote--dir)

  (dolist (remote remotes)
    (treebund-test--setup-remote (car remote) (cdr remote))))

(defmacro treebund-deftest (name remotes &rest body)
  "Wrapper around `ert-deftest' to ensure correct tmp directories
are used for all tests."
  (declare (indent defun)
           (doc-string 3))
  `(ert-deftest ,name ()
     ,(when (stringp (car body))
        (pop body))
     (let* ((inhibit-message t)
            (treebund-workspace-root (file-name-concat treebund-test--dir "workspaces"))
            (treebund-bare-dir (file-name-concat treebund-workspace-root ".bare"))
            (treebund-project-open-function (lambda (&rest _)))
            (treebund-prefix "test/"))
       (treebund-test--setup ',remotes)
       ,@body)))


;;; Tests:
(treebund-deftest treebund--setup
  (("origin-one" . ())
   ("origin-two" . ("branch-one"))
   ("origin-three" . ("branch-one" "branch-two")))
  "The basic testing environment used for all treebund tests."
  (let ((origin (expand-file-name "origin-one.git" treebund-remote--dir)))
    (should (file-directory-p origin))
    (should-not (treebund--branches origin)))

  (let ((origin (expand-file-name "origin-two.git" treebund-remote--dir)))
    (should (file-directory-p origin))
    (should (length= (treebund--branches origin) 1))
    (should (member "branch-one" (treebund--branches origin))))

  (let ((origin (expand-file-name "origin-three.git" treebund-remote--dir)))
    (should (file-directory-p origin))
    (should (length= (treebund--branches origin) 2))
    (should (member "branch-one" (treebund--branches origin)))
    (should (member "branch-two" (treebund--branches origin)))))

(treebund-deftest treebund--branches
  (("remote" . ("test/branches" "test/branches-two"))
   ("empty-remote" . ()))
  (let* ((workspace-path (expand-file-name "branches" treebund-workspace-root))
         (remote (expand-file-name "remote.git" treebund-remote--dir))
         (bare-path (treebund--clone remote)))

    ; Check bare repository branches
    (should (length= (treebund--branches bare-path) 2))
    (should (member "test/branches" (treebund--branches remote)))
    (should (member "test/branches-two" (treebund--branches remote)))

    ; Check worktree branches
    (let ((project-path (treebund--project-add workspace-path bare-path)))
      (should (length= (treebund--branches project-path) 2))
      (should (member "test/branches" (treebund--branches project-path)))
      (should (member "test/branches-two" (treebund--branches project-path)))))

  ; Ensure nil is returned when no branches exist.
  (let* ((remote (expand-file-name "empty-remote.git" treebund-remote--dir))
         (bare-path (treebund--clone remote)))
    (should (length= (treebund--branches bare-path) 0))))

(treebund-deftest treebund--worktree-bare
  (("remote" . ("test/worktree-bare")))
  (let* ((workspace-path (expand-file-name "worktree-bare" treebund-workspace-root))
         (remote (expand-file-name "remote.git" treebund-remote--dir))
         (bare-path (treebund--clone remote))
         (project-path (treebund--project-add workspace-path bare-path)))
    (should (string= bare-path (treebund--worktree-bare project-path)))))

(treebund-deftest treebund--worktree-remove
  (("remote" . ("test/worktree-remove")))
  (let* ((workspace-path (expand-file-name "worktree-remove" treebund-workspace-root))
         (remote (expand-file-name "remote.git" treebund-remote--dir))
         (bare-path (treebund--clone remote))
         (project-path (treebund--project-add workspace-path bare-path)))
    (treebund--worktree-remove project-path)
    (should-not (file-exists-p project-path))))

(treebund-deftest treebund--worktree-add
  (("remote" . ("test/worktree-add")))
  (let* ((workspace-path (expand-file-name "worktree-add" treebund-workspace-root))
         (remote (expand-file-name "remote.git" treebund-remote--dir))
         (bare-path (treebund--clone remote))
         (project-path (treebund--project-add workspace-path bare-path)))
    (should (file-directory-p project-path))))

(treebund-deftest treebund--branch
  (("remote" . ("test/branch")))
  (let* ((workspace-path (expand-file-name "branch" treebund-workspace-root))
         (remote (expand-file-name "remote.git" treebund-remote--dir))
         (bare-path (treebund--clone remote))
         (project-path (treebund--project-add workspace-path bare-path)))
    (should (string= "test/branch" (treebund--branch project-path)))))

(treebund-deftest treebund--branch-delete
  (("remote" . ("master" "branch-one" "branch-two")))
  (let* ((workspace-path (expand-file-name "branch-delete" treebund-workspace-root))
         (remote (expand-file-name "remote.git" treebund-remote--dir))
         (bare-path (treebund--clone remote))
         (project-path (treebund--project-add workspace-path bare-path)))
    (should (length= (treebund--branches bare-path) 4))
    (treebund--branch-delete bare-path "branch-one")
    (should (length= (treebund--branches bare-path) 3))
    (treebund--branch-delete project-path "branch-two")
    (should (length= (treebund--branches bare-path) 2))))

(treebund-deftest treebund--clone
  (("remote" . ("master" "other-branch")))
  (let* ((workspace-path (expand-file-name "branch-delete" treebund-workspace-root))
         (remote (expand-file-name "remote.git" treebund-remote--dir))
         (bare-path (treebund--clone remote)))
    (should (file-directory-p bare-path))
    (should (length= (treebund--branches bare-path) 2))
    (should (member "master" (treebund--branches bare-path)))
    (should (member "other-branch" (treebund--branches bare-path)))))

(treebund-deftest treebund--worktree-list
  (("remote" . ("master")))
  (let* ((remote (expand-file-name "remote.git" treebund-remote--dir))
         (bare-path (treebund--clone remote)))
    (should (length= (treebund--worktree-list bare-path) 1))
    (should (member "bare" (car (treebund--worktree-list bare-path))))

    (let ((worktree (treebund--project-add
                         (expand-file-name "worktree-list-one" treebund-workspace-root)
                         bare-path)))
      (should (length= (treebund--worktree-list worktree) 2))
      (should-not (member "bare" (cadr (treebund--worktree-list bare-path)))))

    (let ((worktree (treebund--project-add
                         (expand-file-name "worktree-list-two" treebund-workspace-root)
                         bare-path)))
      (should (length= (treebund--worktree-list worktree) 3)))))

(treebund-deftest treebund--rev-count
  (("remote" . ("master" "other-branch")))
  (let* ((remote (expand-file-name "remote.git" treebund-remote--dir))
         (bare-path (treebund--clone remote)))
    (should (= (treebund--rev-count bare-path "other-branch") 3))))

(provide 'treebund-tests)
;;; treebund-tests.el ends here
