#!/usr/bin/env bash
# adapters/detect.sh — print the stack name(s) detected in a repo, one per line.
#
# Detection is by manifest / lockfile presence, shallow (up to 2 levels deep) so
# common monorepo layouts are found without scanning vendored or build trees.
# A repo may match several stacks; the gate runner runs the union.
#
# Usage: detect.sh [ROOT]   (ROOT defaults to the current directory)
set -euo pipefail

ROOT="${1:-.}"
emit() { printf '%s\n' "$1"; }

{
  while IFS= read -r f; do
    case "${f##*/}" in
      package.json)                          emit node ;;
      go.mod)                                emit go ;;
      Cargo.toml)                            emit rust ;;
      pom.xml|build.gradle|build.gradle.kts) emit java ;;
      Gemfile|*.gemspec)                     emit ruby ;;
      pyproject.toml|setup.py|setup.cfg|requirements.txt) emit python ;;
      *.sln|*.csproj|*.fsproj|*.vbproj)      emit dotnet ;;
    esac
  done < <(
    find "$ROOT" -maxdepth 2 \
      \( -name .git -o -name node_modules -o -name vendor -o -name target \
         -o -name dist -o -name build -o -name .venv -o -name .tox \) -prune -o \
      -type f -print 2>/dev/null
  )
} | sort -u
