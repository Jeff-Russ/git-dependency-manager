
gdm_validateInstance() {
  # Input: [$flags[@]] $manifest $instance $snapshot $local_assignments
  #        followed by optional flags and the remaining args are var names that should be defined in manifest 
  # Flags (in no order but preceeding first non-flag):
  #   [--register|--required]        # default is --required (value after -- sets value of $mode)
  #   [--allow-lone|--disallow-lone] # default is 
  # Output: 
  #       git diff output to stdout but (only if passed --show-snapshot-mismatch-diff)
  # Returns:0 if no error or GDM_ERRORs with the following keys (where mode is 'register' or 'required')
  #     ${mode}_instance_missing
  #     ${mode}_manifest_missing
  #     ${mode}_manifest_unlinked            # if passed --disallow-lone (not default)
  #     ${mode}_manifest_inode_mismatch
  #     ${mode}_manifest_version_outdated
  #     ${mode}_manifest_requirement_mismatch
  #     register_snapshot_missing            # (no matter the mode)
  #     ${mode}_snapshot_gitswap_failed
  #     ${mode}_was_modified

  # Output:
  #       to stdour but only if passed --show-snapshot-mismatch-diff
  # NOTE: $assignments as show below must define, at minimum: manifest instance snapshot and, in addition,
  #       any of the remaining args that are variable names to be checked in the manifest.
  # Example 1:
  #   local assignments="$(gdm_echoVars manifest instance snapshot register_path remote_url hash tag setup)"
  #   gdm_validateInstance "$assignments" register_path remote_url hash tag setup
  # Example 2:
  #   gdm_validateInstance "$assignments" register_path remote_url hash tag setup

  local mode=required
  local allow_lone=true
  local show_snapshot_mismatch_diff=false
  while [[ "$1" =~ '^--' ]] ; do
    if   [[ "$1" == '--register' ]] ; then mode=register
    elif [[ "$1" == '--required' ]] ; then mode=required
    elif [[ "$1" =~ '^--allow-lone[^=]*$' ]] ; then allow_lone=true ; shift 
    elif [[ "$1" =~ '^--disallow-lone[^=]*$' ]] ; then allow_lone=false ; shift 
    elif [[ "$1" == '--show-snapshot-mismatch-diff' ]]  ; then show_snapshot_mismatch_diff=true ; shift
    # possibly add more options here, later on
    else break
    fi
  done
  local manifest="$1" # registered/required manifest path
  local instance="$2" # registered/required instance path
  local snapshot="$3" # registered snapshot path
  local local_assignments="$4"
  shift 4

  # local_assignments is values for each "local $@"
  local $@ ; eval "$local_assignments" || return $?

  ! [[ -d "$instance" ]] && return $GDM_ERRORS[${mode}_instance_missing] #TODO add to GDM_ERRORS and modify all refs
  ! [[ -f "$manifest" ]] && return $GDM_ERRORS[${mode}_manifest_missing] #TODO add to GDM_ERRORS and modify all refs
  
  # IF NOT ALLOWED: FAIL IF INSTANCE (MANIFEST) HAS NO LINKS TO IT:
  ! $allow_lone && [[ $(gdm_hardLinkCount "$manifest") -eq 0 ]] && return $GDM_ERRORS[${mode}_manifest_unlinked] #TODO add to GDM_ERRORS and modify all refs
  
  # ASSIGN MANIFEST VARIABLES TO LOCAL VARIABLES WITH _ PREPENDED TO EACH VARIABLE NAME:
  local manifest_vars=("${(@f)"$(<$manifest)"}") ; manifest_vars=($manifest_vars) # remove empty element
  manifest_vars=("local _"$^manifest_vars) ;  eval "$(print -l $manifest_vars)" 

  # ENSURE MANIFEST FILE'S INODE MATCHES THE INODE IT SAYS IT IT:
  [[ "$_gdm_manifest_inode" != $(gdm_getInode "$manifest") ]] && return $GDM_ERRORS[${mode}_manifest_inode_mismatch] #TODO add to GDM_ERRORS and modify all refs
  
  # ENSURE MANIFEST'S gdm_version STARTS WITH GDM_VER_COMPAT:
  ! [[ "$_gdm_version" =~ "^$GDM_VER_COMPAT.*" ]] && return $GDM_ERRORS[${mode}_manifest_version_outdated] #TODO add to GDM_ERRORS and modify all refs

  # COMPARE VALUES OF REMAINING ARGS (VARIABLE NAME) AGAINST THEIR VALUES IN MANIFEST:
  for var_name in $@ ; do # If any manifest vars mismatch evaled vars, fail. 
    manifest_var_name="_$var_name"
    [[ "${(P)var_name}" != "${(P)manifest_var_name}" ]] && return $GDM_ERRORS[${mode}_manifest_requirement_mismatch] #TODO add to GDM_ERRORS and modify all refs
  done

  # CHECK SNAPSHOT TO SEE IF INSTANCE HAS BEEN MODIFED AND THUS NO LONGER MEETING REQUIREMENT:
  local snapDiff_assign_flags=(--$mode) ; $show_snapshot_mismatch_diff && snapDiff_assign_flags+=(--show-snapshot-mismatch-diff)
  local snapDiff_assign_arg="$(gdm_echoVars instance snapshot)"
  gdm_snapshotDiff $snapDiff_assign_flags $snapshot_assign_arg #NOTE: may have output to stdout
  return $?
  # Possible returns are 0 plus the values from $GDM_ERRORS with the following keys: 
 
}



###### gdm_validateInstance Helpers ###############################################################

gdm_snapshotDiff() {
  # Input: flags + eval-able string assigning instance and snapshot
  # Possible returns are 0 plus the values from $GDM_ERRORS with the following keys: 
  #  register_snapshot_missing
  #  register_snapshot_gitswap_failed   register_was_modified     (if passed --register)
  #  required_snapshot_gitswap_failed   required_was_modified     (if passed --required )
  # Output: to stdour but only if passed --show-snapshot-mismatch-diff
  local mode=required
  local show_diff=false 
  local instance snapshot # instance can not be missing!
  for arg in $@ ; do
    if   [[ "$arg" == '--register' ]] ; then mode=register
    elif [[ "$arg" == '--required' ]] ; then mode=required
    elif [[ "$arg" == '--show-snapshot-mismatch-diff' ]] ; then show_diff=true
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