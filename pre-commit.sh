#!/bin/sh
#
# This pre-commit hook wrapper stashes away your untracked and unstaged files.
#
# Like all Git operations, stashing only honors file permissions 644 and 755.
# Commit is aborted in cases where stashing would fail: if no initial commit
# has yet been made, if there are unresolved conflicts to begin with, or if
# a file that is staged for deletion or renaming has somehow been recreated.

branch_pattern=$(git config hooks.branch) || branch_pattern="^master$"
[[ $(git branch --show-current) =~ ${branch_pattern:-^master$} ]] || exit 0

staged_files=$(git diff --cached --name-status)
[ -z "$staged_files" ] && exit 0

git ls-tree HEAD > /dev/null 2>&1 || {
  printf "Aborting because pre-commit relies on stash which fails before initial commit.\nBypass with: \"git commit --no-verify\"\n"
  exit 1
}

[[ $staged_files =~ ^"U"[[:space:]] ]] && {
  echo "Aborting until the following files contain no merge conflicts:"
  git diff --cached --name-only --diff-filter=U
  exit 1
}

[[ $staged_files =~ ^[DR] ]] && {
  while IFS= read -r file; do
    [ ! -z "$file" ] &&
    [[ $staged_files =~ ^[DR][[:digit:]]*[[:space:]]"$file"([[:space:]]|$) ]] &&
    unstashable_files="${unstashable_files}${file}\n"
  done <<< "$(git ls-files --others --exclude-standard)"
  [ -z "$unstashable_files" ] || {
    printf "Aborting because file(s) staged for deletion/renaming still exist, making them\nunrestorable from stash. To continue, unstage or delete following file(s):\n$unstashable_files"
    exit 1
  }
}

deleted_files=$(git diff --name-only --diff-filter=D)

# prepare for stashing (eg. by shutting down anything that relies on the files)
prestash=$(git config hooks.prestash)
[ -z "$prestash" ] || {
  cmd=($prestash)
  "${cmd[@]}"
  staged_files=$(git diff --cached --name-status)
}

# stash away untracked and unstaged files
git stash push --all --keep-index > /dev/null || exit 1

precommit=$(git config hooks.precommit)
[ -z "$precommit" ] || {
  cmd=("$precommit" "$staged_files")
  "${cmd[@]}"
}
errors=$?

# wipe clean the index file and the working tree, and restore them from stash
git reset --hard > /dev/null
git stash pop --index > /dev/null || exit 1

# reconstruct possible file deletions
while IFS= read -r file; do
  [[ $staged_files =~ ^[AMR].*[[:space:]]"$file"$ ]] && rm -f "$file"
done <<< "$deleted_files"

[ $errors -ne 0 ] && { echo "Aborting commit as invalid: see above"; exit 1; }
exit 0

# https://codeinthehole.com/tips/tips-for-using-a-git-pre-commit-hook/
# https://codingkilledthecat.wordpress.com/2012/04/27/git-stash-pop-considered-harmful/
# https://stackoverflow.com/questions/43770520/how-to-specify-default-merge-strategy-on-git-stash-pop
# https://stackoverflow.com/questions/2412450/git-pre-commit-hook-changed-added-files
# https://medium.com/sweetmeat/remove-unwanted-unstaged-changes-in-tracked-files-from-a-git-repository-d41c4f64a251
# https://stackoverflow.com/questions/1105253/how-would-i-extract-a-single-file-or-changes-to-a-file-from-a-git-stash
# https://unix.stackexchange.com/questions/410710/splitting-a-line-into-array-in-bash-with-tab-as-delimiter
# https://stackoverflow.com/questions/3801321/git-list-only-untracked-files-also-custom-commands
# https://www.regular-expressions.info/posixbrackets.html
# https://softwareengineering.stackexchange.com/questions/260778/is-it-a-good-practice-to-run-unit-tests-in-version-control-hooks?rq=1
