#!/bin/bash
cgroup="$(sed -n '1{ s/^[0-9]*:[^:]*://; p; q; }' /proc/1/cgroup)"
if [[ "${cgroup#/docker/}" = "$cgroup" ]]; then docker "$@"; exit "$?"; fi

map_volume(){
  local path="$(
    local canonical=
    local head="$1"
    local tail=

    while true; do
      canonical="$(readlink -f "$head")"
      [[ -n "$canonical" ]] && break
      [[ -n "$tail" ]] && tail="/$tail"
      tail="${head##*/}$tail"
      head="${head%/*}"
      [[ -z "$head" ]] && head=/ && tail="${tail#/}"
    done
    [[ "$head" != "/" ]] && [[ -n "$tail" ]] && tail="/$tail"
    printf '%s%s\n' "$canonical" "$tail"
  )"
  local volumes="$(
    docker inspect \
      --format='{{ json .Mounts }}' \
      "${cgroup#/docker/}"
  )"

  local mount_destination="$(
    jq -r --arg path "$path" <<<"$volumes" '
      [
        .[]|select(
          $path == .Destination or
          $path[0:(.Destination|length + 1)] == (.Destination + "/")
        )
      ] |
      sort_by(.Destination|length)|
      last |
      .Destination
    '
  )"

  if [[ "$mount_destination" = "null" ]]; then
    printf "Path '%s' is not within a volume\n" "$path" >&2
    return 1
  fi

  local path_tail=
  if [[ "$mount_destination" != "$path" ]]; then
    path_tail="${path#$mount_destination}"
  fi

  local mount_source="$(
    jq -r --arg path "$mount_destination" <<<"$volumes" '
      [.[]|select( $path == .Destination )]|first|.Source
    '
  )"

  printf '%s%s\n' "$mount_source" "$path_tail"
}

has_value_args=(
  $(
    docker run --help|
    sed -n '
      s/\([a-z0-9]\)   *.*/\1/;
      s/^  *//;
      / [a-z]/{
        s/ [a-z].*//;
        s/, /\n/;
        p;
      }
    '
  )
)

first="$1"; shift
args=( "$first" )

if [[ "$first" = "run" ]]; then
  while [[ $# -gt 0 ]]; do
    arg="$1"; shift
    case "$arg" in
      -v|--volume=*)
        if [[ "$arg" = "-v" ]]; then
          spec="$1"; shift
        else
          spec="${arg#--volume=}"
        fi

        src="${spec%%:*}"
        spec_tail="${spec#$src:}"

        mapped="$(map_volume "$src")"
        if [[ -z "$mapped" ]]; then
          exit 1
        fi

        args=( "${args[@]}" --volume="$mapped:$spec_tail" )
        ;;
      -*)
        args=( "${args[@]}" "$arg" )
        for has_value_arg in "${has_value_args[@]}"; do
          if [[ "$arg" = "$has_value_arg" ]]; then
            args=( "${args[@]}" "$1" ); shift
            break
          fi
        done
        ;;
      *)
        args=( "${args[@]}" "$arg" "$@" )
        break #from while loop
        ;;
    esac
  done
else
  args=( "$@" )
fi

docker "${args[@]}"
