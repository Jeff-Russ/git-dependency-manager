#!/usr/bin/env zsh

look() {
  set
  echo "$A_GLOB"
}

export A_GLOB=""


set() {
  export A_GLOB="now set!"
}

main () {
  look
}

# main


catRange() {
  (($#<2)) && { echo "$0 requires at least two arguments: filepath and line_start" >&2 ; return 1 ; }
  local filepath="$1"
  local line_start="$2" 
  local line_end="$3" ; [[ -z $line_end ]] && line_end=$line_start
  local i=0
  while IFS= read -r line || [ -n "$line" ] ; do
    if [[ $line_start != END ]] && ((++i>=$line_start)) ; then
      if [[ $line_end == END ]] || ((i<=line_end)) ; then
        echo "$line"
      fi
    fi
  done <"$filepath"
}

catRange "$@"
