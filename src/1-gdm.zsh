# environment variables used in require and register:
export GDM_MANIF_EXT="gdm_manifest"
export GDM_MANIF_VARS=(gdm_manifest_inode gdm_version regis_instance remote_url hash tag setup_hash) #changed gdm_register_path to regis_instance
export GDM_MANIF_VALIDATABLES=(regis_instance remote_url hash tag setup_hash)
# used only in register:
export GDM_SNAP_EXT="gdm_snapshot" 
# used in gdm_parseRequirement:
export GDM_MIN_HASH_LEN=7


gdm() {
  # which _S

  (($#==0)) && { echo "$(_S Y)gdm called without arguments$(_S)" >&2 ; return 127 ; }

  local config_fn_def=""

  if config_fn_def="$(typeset -f "$1" 2>/dev/null)" ; then
    local fn="$1" ; shift
    echo "got function $fn\n"
    $fn "$@"
    return $?
  fi
  # (($#<2)) && { echo "$(_S Y)gdm only got $# arguments$(_S)" >&2 ; return 127 ; }
  local method="$1" ; shift

  if ! (type gdm.$method >/dev/null 2>&1) ; then
    echo "$(_S R)gdm failed due to unknown option: $(_S G)$method$(_S)" ; return 127
  else
    echo "gdm is executing gdm.$method $@"
    gdm.$method "$@" 
    return $?
  fi
}




