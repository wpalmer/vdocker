#!/bin/bash
container="$(sed -n '/^[0-9]*:[^:]*:\/docker\//{ s/^[^:]*:[^:]*:\/docker\///; p; q; }' /proc/1/cgroup)"
if [[ -z "${container}" ]]; then exec docker "$@"; fi

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
      "${container}"
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

  jq -r \
    --arg path "$mount_destination" \
    --arg path_tail "$path_tail" \
    <<<"$volumes" '
    [
      .[] | select(
        $path == .Destination or
        .Destination[0:(($path + $path_tail)|length + 1)] ==
        ($path + $path_tail + "/")
      ) | (
        .Source + $path_tail + ":" +
        (
          if .Destination[(($path + $path_tail)|length + 1):] | length == 0
          then
            "."
          else
            .Destination[(($path + $path_tail)|length + 1):]
          end
        )
      )
    ]|join(":")
  '
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

        mapped_component=
        mapped_source=
        mapped_dest=
        spec_tail_path="${spec_tail%%:*}"
        spec_tail_mode="${spec_tail#*:}"
        if [[ "$spec_tail_mode" = "$spec_tail" ]]; then
          spec_tail_mode=
        else
          spec_tail_mode=":$spec_tail_mode"
        fi

        while read -d : mapped_component; do
          if [[ -z "$mapped_source" ]]; then
            mapped_source="$mapped_component"
            continue
          fi
          mapped_dest="$mapped_component"

          if [[ "$mapped_dest" = "." ]]; then
            mapped_dest=
          else
            mapped_dest="/$mapped_dest"
          fi

          args=(
            "${args[@]}"
            --volume="$mapped_source:${spec_tail_path}$mapped_dest${spec_tail_mode}"
          )
          mapped_source=
          mapped_dest=
        done <<<"${mapped}:"
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
  args=( "${args[@]}" "$@" )
fi

if [[ -n "$VDOCKER_VERBOSE" ]]; then
	printf '+ ' >&2
	printf '%q ' docker "${args[@]}" >&2;
	echo >&2
fi
exec docker "${args[@]}"
