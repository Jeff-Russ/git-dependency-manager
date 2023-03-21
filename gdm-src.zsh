#!/usr/bin/env zsh

# This file is to test the code in src/ without compiling it to dist/ or $GDM_REGISTRY

export _GDM_WORKROOT="${0:h}" # Note: only correct if $0 is in root of gdm repo: so don't move this file


gdm_args=("${@}") ; shift $# # store and delete command line args for passing to src because if not, source ./run gets them!!!

# source ./run # for GDM_WORKROOT _export_SRC_FILES SRC_FILES and setGDM 
# _export_SRC_FILES # sets SRC_FILES

source "$_GDM_WORKROOT/run" _export_SRC_FILES # for GDM_WORKROOT SRC_FILES and setGDM 


main() {
  for i in {1..$#SRC_FILES} ; do
    ((i!=$#SRC_FILES)) && source "$SRC_FILES[$i]" || source "$SRC_FILES[$i]" "$gdm_args[@]"
  done
}
main "$@"