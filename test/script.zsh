#!/usr/bin/env zsh

# func() {
#   local ARGV=("$@")
#   echo ${#ARGV}
#   typeof ARGV
#   local args=("${ARGV[@]}")
#   echo ${#args}
#   typeof args
# }

# func "$@"

echo $LINENO

. "${0:a:h}/gdm.zsh" "$@"