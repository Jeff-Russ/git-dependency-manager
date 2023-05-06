gdm_validateInstance() {
  # Input: [$flags[@]] $manifest $instance $snapshot $local_assignments
  #        followed by optional flags and the remaining args are var names that should be defined in manifest 
  # Flags (in no order but preceeding first non-flag):
  #   [--register|--required]        # default is --required (value after -- sets value of $mode)
  #   [--allow-unlinked|--disallow-unlinked] # default is 
  # Output to stdout (only if passed --show-output): 
  #       git diff if failed
  # Returns:0 if no error or GDM_ERRORs with the following keys (where mode is 'register' or 'required')
  #     ${mode}_instance_missing
  #     ${mode}_manifest_missing
  #     ${mode}_manifest_unlinked            # if passed --disallow-unlinked (not default)
  #     ${mode}_manifest_inode_mismatch
  #     ${mode}_manifest_version_outdated
  #     ${mode}_manifest_requirement_mismatch
  #     register_snapshot_missing            # (no matter the mode)
  #     ${mode}_snapshot_gitswap_failed
  #     ${mode}_was_modified

  # Output:
  #       to stdour but only if passed --show-output
  # NOTE: $assignments as show below must define, at minimum: manifest instance snapshot and, in addition,
  #       any of the remaining args that are variable names to be checked in the manifest.
  # Example 1:
  #   local assignments="$(gdm_echoVars manifest instance snapshot register_path remote_url hash tag setup)"
  #   gdm_validateInstance "$assignments" register_path remote_url hash tag setup
  # Example 2:
  #   gdm_validateInstance "$assignments" register_path remote_url hash tag setup

  # echo "$0 got $# args" >&2 #TEST
  local mode=required
  local allow_unlinked=true
  local show_output=false
  while [[ "$1" =~ '^--.+' ]] ; do
    if   [[ "$1" == '--register' ]] ; then mode=register ; shift
    elif [[ "$1" == '--required' ]] ; then mode=required ; shift 
    elif [[ "$1" =~ '^--allow-unlinked[^=]*$' ]] ; then allow_unlinked=true ; shift 
    elif [[ "$1" =~ '^--disallow-unlinked[^=]*$' ]] ; then allow_unlinked=false ; shift 
    elif [[ "$1" == '--show-output' ]]  ; then show_output=true ; shift
    # possibly add more options here, later on
    else break
    fi
  done
  local manifest="$1" # registered/required manifest path
  local instance="$2" # registered/required instance path
  local snapshot="$3" # registered snapshot path
  local local_assignments="$4"
  shift 4

  # echo "  $0 mode=$mode" >&2 #TEST

  # local_assignments is values for each "local $@"
  local $@ ; eval "$local_assignments" || return 1
  
  ! [[ -d "$instance" ]] && return $GDM_ERRORS[${mode}_instance_missing]
  ! [[ -f "$manifest" ]] && return $GDM_ERRORS[${mode}_manifest_missing]
  
  # ASSIGN MANIFEST VARIABLES TO LOCAL VARIABLES WITH _ PREPENDED TO EACH VARIABLE NAME:
  local manifest_vars=("${(@f)"$(<$manifest)"}") ; manifest_vars=($manifest_vars) # remove empty element
  manifest_vars=("local _"$^manifest_vars) ;  eval "$(print -l $manifest_vars)" 
  
  # COMPARE VALUES OF REMAINING ARGS (VARIABLE NAME) AGAINST THEIR VALUES IN MANIFEST:
  local manifest_requirement_mismatch=false
  for var_name in $@ ; do # If any manifest vars mismatch evaled vars, fail. 
    manifest_var_name="_$var_name"
    if [[ "${(P)var_name}" != "${(P)manifest_var_name}" ]] ; then
      if $show_output ; then
        echo "expecting $var_name=${(P)var_name} but got ${(P)manifest_var_name}"
        manifest_requirement_mismatch=true
      else
        return $GDM_ERRORS[${mode}_manifest_requirement_mismatch]
      fi
    fi
    $manifest_requirement_mismatch && return $GDM_ERRORS[${mode}_manifest_requirement_mismatch]
  done

  # CHECK SNAPSHOT TO SEE IF INSTANCE HAS BEEN MODIFED AND THUS NO LONGER MEETING REQUIREMENT:
  local snapDiff_assign_flags=(--$mode) ; $show_output && snapDiff_assign_flags+=(--show-output)
  local snapDiff_assign_arg="$(gdm_echoVars instance snapshot)"
  gdm_snapshotDiff $snapDiff_assign_flags $snapDiff_assign_arg || return $?
  #NOTE: gdm_snapshotDiff may have output to stdout of git diff. Possible returns beside 0 are: $GDM_ERRORS[register_snapshot_missing]
  # $GDM_ERRORS[${mode}_snapshot_gitswap_failed] (rare, unrecoverable) or $GDM_ERRORS[${mode}_was_modified] (the typical fail)
  
  # ENSURE MANIFEST FILE'S INODE MATCHES THE INODE IT SAYS IT IT:
  [[ "$_gdm_manifest_inode" != $(gdm_getInode "$manifest") ]] && return $GDM_ERRORS[${mode}_manifest_inode_mismatch]
  
  # ENSURE MANIFEST'S gdm_version STARTS WITH GDM_VER_COMPAT:
  ! [[ "$_gdm_version" =~ "^$GDM_VER_COMPAT.*" ]] && return $GDM_ERRORS[${mode}_manifest_version_outdated]

  # IF NOT ALLOWED: FAIL IF INSTANCE (MANIFEST) HAS NO LINKS TO IT:
  ! $allow_unlinked && [[ $(gdm_hardLinkCount "$manifest") -eq 0 ]] && return $GDM_ERRORS[${mode}_manifest_unlinked]

  return 0 # DO NOT DELETE 
}



###### gdm_validateInstance Helpers ###############################################################

gdm_snapshotDiff() {
  # Input: flags + eval-able string assigning instance and snapshot
  # Possible returns are 0 plus the values from $GDM_ERRORS with the following keys: 
  #  register_snapshot_missing
  #  register_snapshot_gitswap_failed   register_was_modified     (if passed --register)
  #  required_snapshot_gitswap_failed   required_was_modified     (if passed --required )
  # Output: to stdour but only if passed --show-output
  local mode=required
  local show_diff=false 
  local instance snapshot # instance can not be missing!
  for arg in $@ ; do
    if   [[ "$arg" == '--register' ]] ; then mode=register
    elif [[ "$arg" == '--required' ]] ; then mode=required
    elif [[ "$arg" == '--show-output' ]] ; then show_diff=true
    else eval "$arg" # sets: instance snapshot
    fi
  done
  
  ! [[ -d "$snapshot" ]] && return $GDM_ERRORS[register_snapshot_missing] 


  gdm_swapDotGits "$instance" "$snapshot" || return $GDM_ERRORS[${mode}_snapshot_gitswap_failed] # possibly left_corrupted
  local output error ; output=$(cd "$instance" && git status --porcelain) ; error=$? # error not needed? I think output tells all
  gdm_swapDotGits "$instance" "$snapshot" || return $GDM_ERRORS[${mode}_snapshot_gitswap_failed]
  [[ -z "$output" ]] && return 0
  $show_diff && echo "$output"
  return $GDM_ERRORS[${mode}_was_modified]
}

gdm_swapDotGits() {
  local parentdir_A="${1:a}"
  local parentdir_B="${2:a}"
  local tempdir_A=$(mktemp -d 2>/dev/null || mktemp -d -t 'mytmpdir')
  gdm_mvSubdirsTo "$parentdir_A" '.git' "$tempdir_A" 
  gdm_mvSubdirsTo "$parentdir_B" '.git' "$parentdir_A"
  gdm_mvSubdirsTo "$tempdir_A" '.git' "$parentdir_B"
  rm -rf "$tempdir_A"
}
