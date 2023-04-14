source-dir := "~/.cache/treebund/test/"
emacs-repo := "https://git.savannah.gnu.org/git/emacs.git"
emacs-versions := "27.1 28.1"

# ${emacs} -L ./ -l ./tests/test-*.el --eval="(ert-run-tests-batch-and-exit)"

test:
	cask emacs -Q --batch -L ./ -l treebund-tests.el --eval="(ert-run-tests-batch-and-exit)"

clone:
	git clone --bare {{ emacs-repo }} {{ source-dir }}/emacs.git
	git worktree add {{ source-dir }} -b emacs-27
	git worktree add {{ source-dir }} -b emacs-28
	git worktree add {{ source-dir }} -b emacs-29
