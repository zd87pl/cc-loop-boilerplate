#!/usr/bin/env bash
# loop/lib/git.sh — git / worktree helpers that enforce branch isolation and
# refuse to touch protected branches (CON-040, CON-041, CON-042).
#
# Expects PROTECTED_BRANCHES (space-separated) in the environment; falls back to
# "main master". Requires common.sh to be sourced first (for info/warn/die).

git_root()           { git rev-parse --show-toplevel 2>/dev/null; }
git_current_branch() { git rev-parse --abbrev-ref HEAD 2>/dev/null; }
git_head_sha()       { git rev-parse HEAD 2>/dev/null; }
git_short_sha()      { git rev-parse --short HEAD 2>/dev/null; }
git_is_clean()       { [ -z "$(git status --porcelain 2>/dev/null)" ]; }

git_is_protected() {
  local b="$1" p
  for p in ${PROTECTED_BRANCHES:-main master}; do
    [ "$b" = "$p" ] && return 0
  done
  return 1
}

# Die if the target branch is protected (CON-041).
git_assert_safe_branch() {
  git_is_protected "$1" && die "refusing to operate on protected branch '$1' (CON-041)"
  return 0
}

# Best-effort base branch: HEAD's upstream, else main/master, else current.
git_default_base() {
  local up
  up="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null | sed 's#^[^/]*/##')"
  if [ -n "$up" ]; then printf '%s' "$up"; return; fi
  local b
  for b in main master; do
    git show-ref --verify --quiet "refs/heads/$b" && { printf '%s' "$b"; return; }
  done
  git_current_branch
}

# Create or reuse a feature branch (never protected).
git_make_feature_branch() {
  local branch="$1"
  git_assert_safe_branch "$branch"
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    info "reusing existing feature branch $branch"
  else
    git branch "$branch" && info "created feature branch $branch"
  fi
}

# Create or reuse an isolated worktree checked out to the feature branch.
git_setup_worktree() {
  local branch="$1" path="$2"
  git_assert_safe_branch "$branch"
  if git worktree list --porcelain 2>/dev/null | grep -Fq "worktree $path"; then
    info "reusing worktree at $path"
  elif git show-ref --verify --quiet "refs/heads/$branch"; then
    git worktree add "$path" "$branch" >/dev/null && info "worktree added at $path"
  else
    git worktree add -b "$branch" "$path" >/dev/null && info "worktree+branch added at $path"
  fi
}

# Commit everything currently staged/unstaged on the (asserted-safe) branch.
# Used for one-commit-per-task in real runs. No-op when the tree is clean.
git_commit_all() {
  local msg="$1"
  git_assert_safe_branch "$(git_current_branch)"
  if git_is_clean; then
    info "nothing to commit"
    return 0
  fi
  git add -A
  git commit --quiet -m "$msg"
}
