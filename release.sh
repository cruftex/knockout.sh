#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'HELP'
Usage:
  ./release.sh check              Check the local checkout and run tests.
  ./release.sh prepare vX.Y.Z     Build a tarball and print its temporary directory.
  ./release.sh verify DIRECTORY   Check the tarball's commit, checksum, and version.
  ./release.sh draft DIRECTORY    Retest, push the tag, and attach the tarball to a draft.
  ./release.sh vX.Y.Z             Run the full workflow and clean up the local tarball.

To inspect a release before pushing the tag:
  ./release.sh check
  prepared="$(./release.sh prepare v0.1.0)"
  ./release.sh verify "$prepared"
  tar -tzf "$prepared/knockout.sh-v0.1.0.tar.gz"
  ./release.sh draft "$prepared"

The first three steps work offline. Keep the prepared directory for retries,
then remove it when you are done.
The draft step requires GitHub CLI authentication and main to match GitHub.
Use $release-summary in Codex for release notes, then publish the draft in GitHub.
HELP
}

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

require_tag() {
  [[ $1 =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] ||
    die 'Expected a release tag in the form vMAJOR.MINOR.PATCH.'
}

clean_main_commit() {
  local branch status
  branch="$(git branch --show-current)"
  [[ $branch == main ]] || die 'Check out main before releasing.'
  status="$(git status --porcelain --untracked-files=normal)"
  [[ -z $status ]] || die 'The working tree must be clean before releasing.'
  git rev-parse HEAD
}

check_release() {
  local commit="$1" current
  printf 'Testing %s\n' "$commit"
  env PATH=/usr/bin:/bin make test || die 'Release tests failed.'
  current="$(clean_main_commit)"
  [[ $current == "$commit" ]] || die 'HEAD changed during the release checks.'
}

build_package() (
  local tag="$1" commit="$2" destination="$3"
  local package="knockout.sh-$tag" staging runner version archive checksum
  staging="$(mktemp -d)"
  trap 'rm -rf -- "$staging"' EXIT

  git archive --prefix="$package/" "$commit" | tar -x -C "$staging"
  runner="$staging/$package/bin/knockout.sh"
  sed -i "s/^KNOCKOUT_VERSION='GIT'$/KNOCKOUT_VERSION='${tag#v}'/" "$runner"
  version="$("$runner" -v)" || die 'Could not read the packaged version.'
  [[ $version == "${tag#v}" ]] ||
    die "Packaged version '$version' does not match release tag '$tag'."

  archive="$destination/$package.tar.gz"
  tar -czf "$archive" -C "$staging" "$package"
  checksum="$(sha256sum <"$archive")"
  printf '%s %s %s\n' "$tag" "$commit" "${checksum%% *}" >"$destination/release.info"
)

prepare_release() (
  local tag="$1" commit directory
  require_tag "$tag"
  commit="$(clean_main_commit)"
  directory="$(mktemp -d)"
  trap 'rm -rf -- "$directory"' EXIT
  build_package "$tag" "$commit" "$directory"
  local output
  output="$(realpath -- "$directory")"
  trap - EXIT
  printf '%s\n' "$output"
)

# Read the preparation record without executing it. Return values to main.
read_prepared_release() {
  local directory="$1" extra expected_checksum
  IFS=' ' read -r release_tag release_commit expected_checksum extra <"$directory/release.info" ||
    die "Could not read preparation record in $directory."
  require_tag "$release_tag"
  [[ $release_commit =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ &&
     $expected_checksum =~ ^[0-9a-f]{64}$ && -z $extra ]] ||
    die "Invalid preparation record in $directory."

  release_archive="$directory/knockout.sh-$release_tag.tar.gz"
  [[ -f $release_archive ]] || die "Missing archive: $release_archive"
  release_checksum="$expected_checksum"
}

verify_package() {
  local tag="$1" commit="$2" archive="$3" expected_checksum="$4"
  local current_checksum head runner_path
  head="$(git rev-parse HEAD)"
  [[ $head == "$commit" ]] ||
    die "Prepared commit $commit differs from HEAD $head. Prepare the release again."
  current_checksum="$(sha256sum <"$archive")"
  [[ ${current_checksum%% *} == "$expected_checksum" ]] ||
    die "Archive checksum changed: $archive"

  runner_path="knockout.sh-$tag/bin/knockout.sh"
  if ! tar -xOzf "$archive" "$runner_path" | grep -Fx "KNOCKOUT_VERSION='${tag#v}'" >/dev/null; then
    die "Archive does not contain the runner stamped for $tag."
  fi
}

require_release_remote() {
  case "$1" in
    git@github.com:cruftex/knockout.sh|git@github.com:cruftex/knockout.sh.git|\
    ssh://git@github.com/cruftex/knockout.sh|ssh://git@github.com/cruftex/knockout.sh.git|\
    https://github.com/cruftex/knockout.sh|https://github.com/cruftex/knockout.sh.git)
      ;;
    *) die 'Origin must fetch from and push to github.com/cruftex/knockout.sh.' ;;
  esac
}

remote_tag_for_release() {
  local tag_ref="$1" commit="$2"
  local refs object ref main= tag= peeled_tag=
  refs="$(git ls-remote origin refs/heads/main "$tag_ref" "${tag_ref}^{}")"
  while IFS=$'\t' read -r object ref; do
    case "$ref" in
      refs/heads/main) main="$object" ;;
      "$tag_ref") tag="$object" ;;
      "${tag_ref}^{}") peeled_tag="$object" ;;
    esac
  done <<< "$refs"

  [[ $main == "$commit" ]] || die 'Local main must match main on GitHub.'
  [[ -z $tag || ${peeled_tag:-$tag} == "$commit" ]] ||
    die "GitHub tag ${tag_ref#refs/tags/} points to a different object."
  printf '%s\n' "$tag"
}

existing_github_release() {
  local tag="$1" asset="$2"
  gh api --hostname github.com --paginate \
    'repos/cruftex/knockout.sh/releases?per_page=100' \
    --jq ".[] | select(.tag_name == \"$tag\") |
      [.draft, any(.assets[]; .name == \"$asset\" and .state == \"uploaded\"),
        ([.assets[] | select(.name == \"$asset\" and .state == \"starter\") | .id] | first // 0),
        .html_url] | @tsv"
}

draft_release() (
  local tag="$1" commit="$2" archive="$3" checksum="$4"
  local repo='github.com/cruftex/knockout.sh' tag_ref="refs/tags/$1"
  local current remote_tag local_tag= fetch_url push_url staging upload_archive
  local existing is_draft has_asset starter_asset=0 draft_url=

  current="$(clean_main_commit)"
  [[ $current == "$commit" ]] || die 'HEAD differs from the prepared commit. Prepare the release again.'
  staging="$(mktemp -d)"
  trap 'rm -rf -- "$staging"' EXIT
  upload_archive="$staging/${archive##*/}"
  cp -- "$archive" "$upload_archive"
  verify_package "$tag" "$commit" "$upload_archive" "$checksum"

  command -v gh >/dev/null || die 'Install the GitHub CLI (gh) before releasing.'
  fetch_url="$(git remote get-url origin)"
  push_url="$(git remote get-url --push --all origin)"
  require_release_remote "$fetch_url"
  require_release_remote "$push_url"
  remote_tag="$(remote_tag_for_release "$tag_ref" "$commit")"
  if git show-ref --verify --quiet "$tag_ref"; then
    local_tag="$(git rev-parse "${tag_ref}^{}")"
    [[ $local_tag == "$commit" ]] || die "Local tag $tag points to a different object."
  fi
  gh auth status --hostname github.com ||
    die 'Authenticate GitHub CLI for github.com before releasing.'

  existing="$(existing_github_release "$tag" "${archive##*/}")"
  if [[ -n $existing ]]; then
    IFS=$'\t' read -r is_draft has_asset starter_asset draft_url <<< "$existing"
    if [[ $is_draft != true || $has_asset == true ]]; then
      printf 'GitHub already has a release or draft for %s\n%s\n' "$tag" "$draft_url"
      return 0
    fi
  fi

  check_release "$commit"
  remote_tag="$(remote_tag_for_release "$tag_ref" "$commit")"
  if [[ -z $remote_tag ]]; then
    if [[ -z $local_tag ]]; then
      git tag --annotate "$tag" --message "knockout.sh $tag" "$commit"
    fi
    printf 'Pushing tag %s to GitHub\n' "$tag"
    git push origin "$tag_ref:$tag_ref"
  fi

  if [[ -z $draft_url ]]; then
    draft_url="$(gh release create "$tag" --repo "$repo" --verify-tag --draft \
      --title "knockout.sh $tag" --generate-notes)" ||
      die 'Draft creation failed. Rerun the same command to reuse the pushed tag.'
  fi
  if [[ $starter_asset != 0 ]]; then
    gh api --hostname github.com --method DELETE "repos/cruftex/knockout.sh/releases/assets/$starter_asset"
  fi
  gh release upload "$tag" --repo "$repo" "$upload_archive" ||
    die "Asset upload failed for $draft_url. Rerun the same command to retry."
  printf 'Review and publish the draft on GitHub\n%s\n' "$draft_url"
)

main() (
  local command="${1:-help}" directory= commit
  local release_tag release_commit release_archive release_checksum
  case "$command" in
    help|-h|--help)
      [[ $# -le 1 ]] || die 'See ./release.sh --help.'
      usage
      return 0
      ;;
    prepare|verify|draft)
      [[ $# == 2 ]] || die 'See ./release.sh --help.'
      if [[ $command != prepare ]]; then
        directory="$(realpath -e -- "$2")" || die "Cannot open prepared directory: $2"
        [[ -d $directory ]] || die "Expected a prepared directory: $2"
      fi
      ;;
    check|v*)
      [[ $# == 1 ]] || die 'See ./release.sh --help.'
      ;;
    *) die 'See ./release.sh --help.' ;;
  esac

  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null
  case "$command" in
    check)
      commit="$(clean_main_commit)"
      check_release "$commit"
      ;;
    prepare)
      prepare_release "$2"
      ;;
    verify|draft)
      read_prepared_release "$directory"
      if [[ $command == verify ]]; then
        verify_package "$release_tag" "$release_commit" "$release_archive" "$release_checksum"
        printf 'Verified %s at %s\n%s\n' "$release_tag" "$release_commit" "$release_archive"
      else
        draft_release "$release_tag" "$release_commit" "$release_archive" "$release_checksum"
      fi
      ;;
    *)
      require_tag "$command"
      commit="$(clean_main_commit)"
      directory="$(mktemp -d)"
      trap 'rm -rf -- "$directory"' EXIT
      build_package "$command" "$commit" "$directory"
      read_prepared_release "$directory"
      draft_release "$release_tag" "$release_commit" "$release_archive" "$release_checksum"
      ;;
  esac
)

main "$@"
