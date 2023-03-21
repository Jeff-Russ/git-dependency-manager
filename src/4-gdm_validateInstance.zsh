
gdm_validateInstance() {
  # Input: after any optional flags pass an eval-able declaration of local vars as the next argument
  #        followed by optional flags and the remaining args are var names that should be defined in manifest 
  # Output: no output... only a returned error from GDM_ERRORS or a return of 0
  # NOTE: $assignments as show below must define, at minimum: manifest instance snapshot and, in addition,
  #       any of the remaining args that are variable names to be checked in the manifest.
  # Example 1: #changed gdm_register_path to regis_instance
  #   local assignments="$(gdm_echoVars manifest instance snapshot regis_instance remote_url hash tag setup)" #changed gdm_register_path to regis_instance
  #   gdm_validateInstance "$assignments" regis_instance remote_url hash tag setup #changed gdm_register_path to regis_instance
  # Example 2: #changed gdm_register_path to regis_instance
  #   gdm_validateInstance "$assignments" regis_instance remote_url hash tag setup #changed gdm_register_path to regis_instance

  local allow_lone=true
  while [[ "$1" =~ '^--' ]] ; do
    if  [[ "$1" =~ '^--allow-lone[^=]*$' ]] ; then allow_lone=true ; shift 
    elif [[ "$1" =~ '^--disallow-lone[^=]*$' ]] ; then allow_lone=false ; shift 
    # possibly add more options here, later on
    else break
    fi
  done
  local manifest="$1" 
  local instance="$2"
  local snapshot="$3"
  local local_assignments="$4"
  shift 4
  # local_assignments ets values for each "local $@"
  local $@ ; eval "$local_assignments" || return $?

  eval "$(gdm_fromMap GDM_ERRORS --local --all)" || return $?

  ! [[ -d "$instance" ]] && return $instance_missing
  ! [[ -f "$manifest" ]] && return $manifest_missing
  
  ! $allow_lone && [[ $(gdm_hardLinkCount "$manifest") -eq 0 ]] && return $lone_instance # no other files w same inode as manifest exist
  
  local manifest_vars=("${(@f)"$(<$manifest)"}") ; manifest_vars=($manifest_vars) # remove empty element
  manifest_vars=("local _"$^manifest_vars) # prepend each with "local _" so var are local and start with _
  eval "$(print -l $manifest_vars)"

  [[ "$_gdm_manifest_inode" != $(gdm_getInode "$manifest") ]] && return $manifest_inode_mismatch
  # manifest gdm_version must start with GDM_VER_COMPAT:
  ! [[ "$_gdm_version" =~ "^$GDM_VER_COMPAT.*" ]] && return $gdm_version_outdated 

  
  for var_name in $@ ; do # If any manifest vars mismatch evaled vars, fail. 
    manifest_var_name="_$var_name"
    [[ "${(P)var_name}" != "${(P)manifest_var_name}" ]] && return $manifest_requirement_mismatch
  done

  gdm_snapshotDiff "$(gdm_echoVars instance snapshot)" || return $?
  return 0
}

gdm_snapshotDiff() {
  local show_diff=false
  if [[ "$1" == '--show-diff' ]] ; then show_diff=true ; shift ; fi

  local instance snapshot # instance can not be missing!
  eval "$1" # sets: instance snapshot
  # ! [[ -d "$instance" ]] && return $GDM_ERRORS[instance_missing]
  ! [[ -d "$snapshot" ]] && return $GDM_ERRORS[regis_snapshot_missing]

  gdm_swapDotGits "$instance" "$snapshot" || return $GDM_ERRORS[snapshot_check_failed]
  local output error ; output=$(cd "$instance" && git status --porcelain) ; error=$?
  gdm_swapDotGits "$instance" "$snapshot" || return $GDM_ERRORS[snapshot_check_failed]
  ((error)) && return $GDM_ERRORS[snapshot_check_failed]
  [[ -z "$output" ]] && return 0
  $show_diff && echo 
  return $GDM_ERRORS[snapshot_check_mismatch]
}
