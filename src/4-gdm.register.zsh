export GDM_REGISTRATION_VARS=(remote_url rev rev_is hash tag branch to setup register_parent register_id setup_hash
register_path required_path register_manifest register_snapshot prev_registered prev_registration_error register_created)

gdm.register() {
  # Input: $1 is assigments of remote_url hash setup register_manifest register_path register_snapshot register_parent register_id required_path
  # Needed: GDM_VERSION GDM_MANIF_VARS GDM_SNAP_EXT destructured GDM_ERRORS

  local unlinked_regis_flag="--allow-unlinked-register" # allow
  local dry_run=false # If true, gdm.register can be used as a visual front end for a dry run of parseRequirement
  
  while [[ "$1" =~ '^--.+' ]] ; do
    if  [[ "$1" == --re-register-unlinked ]] ; then unlinked_regis_flag="--disallow-unlinked-register" ; shift
    elif  [[ "$1" == --re-register-unlinked=false ]] ; then unlinked_regis_flag="--allow-unlinked-register" ; shift
    elif [[ "$1" =~ '^--dry-run$' ]] ; then dry_run=true ; shift 
    # possibly add more options here, later on
    else break
    fi
  done

  if ! (($#)) ; then echo "$(_S Y)$0 received no arguments!$(_S)" >&2  ; return $GDM_ERRORS[invalid_argument] ; fi

  local outputVars=("${GDM_REGISTRATION_VARS[@]}")
  local register_created=false

  # load GDM_ERRORS (expand associate keys as local variables)
  if ! eval "$(gdm_unpack GDM_ERRORS --local --all)" ; then 
    echo "$(_S R E)gdm_error_code_misread$(_S)" >&2  ; return $GDM_ERRORS[gdm_error_code_misread]
  fi

  ###### PARSE REQUIREMENT ########################################################################
  local requirement requirement_error
  requirement="$(gdm.parseRequirement $unlinked_regis_flag $@)" ; requirement_error=$? #FUNCTION CALL: gdm.parseRequirement
  ((requirement_error==invalid_argument)) && return $invalid_argument ;
  local $GDM_REQUIREMENT_VARS ;  eval "$requirement"
  
  ###### INFORMAIONAL OUTPUT (TO stderr TO KEEP stdout CLEAR FOR outputVars) ######################
  if $prev_registered ; then
    echo "$(_S D S E)Validating previous registration for $@ in ${register_path//$GDM_REGISTRY\//} ...$(_S)" >&2
    if ((prev_registration_error==0)) ; then
      echo "$(_S G)Previous registration is valid!$(_S) Location: \$GDM_REGISTRY/${register_parent#*$GDM_REGISTRY/}/$register_id" >&2
      gdm_echoVars $outputVars ; return 0 ;
    elif ((prev_registration_error==register_manifest_missing)) ; then 
      echo "$(_S M)Generating new registration.$(_S) Reason: previous register_manifest not found in \$GDM_REGISTRY" >&2
    elif ((prev_registration_error==register_manifest_unlinked)) ; then 
      echo "$(_S M)Generating new registration.$(_S) Reason: $unlinked_regis_flag was passed and previous register has no required instances" >&2
    else
      local disp_err="$(gdm_keyOfMapWithVal GDM_ERRORS $prev_registration_error)" ; [[ -z $disp_err ]] && disp_err=$prev_registration_error
      echo "$(_S M)Re-generating registration for $@$(_S) Reason: Previously registration returned error: $disp_err" >&2
    fi
  else echo "$(_S M)Generating new registration for $@$(_S) Reason: not previously registered." >&2
  fi

  ###### PERFORM REGISTRATION (WITH INFORMATIONAL OUTPUT) #########################################
  if $dry_run ; then gdm_echoVars $outputVars ; return 0 ; fi
  # REMOVE OLD BEFORE (RE)CREATING REGISTER:
  [[ -d "$register_path" ]] && rm -rf "$register_path" ;
  # [[ -f "$register_manifest" ]] && rm -rf "$register_manifest" ; # (commented out since register_manifest is inside register_path)
  [[ -d "$register_snapshot" ]] && rm -rf "$register_snapshot" ;
  mkdir -p "$register_parent"
  local gdm_version="$GDM_VERSION" #NEEDED: written to manifest!
  local manifest_contents gdm_manifest_inode
  # CLONE:
  gdm_echoAndExec "cd \"$register_parent\" && git clone --filter=blob:none --no-checkout \"$remote_url\" \"$register_id\"" || return $clone_failed
  # CHECKOUT:
  gdm_echoAndExec "cd \"$register_parent/$register_id\" && git checkout \"$hash\"" || return $checkout_failed
  # SETUP:
  if ! [[ -z "$setup" ]] ; then gdm_echoAndExec "cd \"$register_parent/$register_id\" && $setup \"$required_path\"" || return $setup_returned_error ; fi
  # MAKE MANIFEST:
  touch "$register_manifest" || return $manifest_creation_failed
  gdm_manifest_inode="$(gdm_getInode "$register_manifest")" || return $manifest_creation_failed
  manifest_contents="$(gdm_echoVars $GDM_MANIF_VARS)" # GDM_MANIF_VARS is a global
  echo -n "$manifest_contents" > "$register_manifest" || return $manifest_creation_failed
  # MAKE A SNAPSHOT of the requirement. (init a new repo and store .git as the snapshot. NOTE: tempdir non-local. Good idea?): 
  tempdir=$(mktemp -d 2>/dev/null || mktemp -d -t 'mytmpdir') || return $snapshot_tempdir_failed # But first...
  gdm_mvSubdirsTo "$register_parent/$register_id" '.git' "$tempdir"  || return $snapshot_preswap_failed # move out all current .git/
  gdm_echoAndExec "cd \"$register_parent/$register_id\" && git init" || return $snapshot_failed
  gdm_echoAndExec "cd \"$register_parent/$register_id\" && git add . " || return $snapshot_failed
  gdm_echoAndExec "cd \"$register_parent/$register_id\" && git commit -m '$manifest_contents'" || return $snapshot_failed
  mkdir "$register_parent/$register_id.$GDM_SNAP_EXT" || return $snapshot_mkdir_failed # we'll move snapshot's .git/ to this directory
  mv "$register_parent/$register_id/.git" "$register_parent/$register_id.$GDM_SNAP_EXT" || return $?
  gdm_mvSubdirsTo "$tempdir" '.git' "$register_parent/$register_id" || return $snapshot_postswap_failed
  rm -rf "$tempdir"

  register_created=true
  echo "$(_S M)Done Registering$(_S)" >&2
  gdm_echoVars $outputVars 
  return 0
}




