##### NEW VERSION OF gdm.register, WHICH IS END OF OLD VERSION (THE PART THAT ACTUALLY MODIFIES THE FS) ###############



gdm.register() {
  # Input: $1 is assigments of remote_url hash setup regis_manifest regis_instance regis_snapshot regis_parent_dir regis_id destin_instance
  # Needed: GDM_VERSION GDM_MANIF_VARS GDM_SNAP_EXT destructured GDM_ERRORS

  local force_re_register=false
  local force_arg=""
  local allow_lone_registry=true
  local dry_run=false

  if ! (($#)) ; then echo "$(_S Y)$0 received no arguments!$(_S)" >&2  ; return $GDM_ERRORS[invalid_argument] ; fi

  while [[ "$1" =~ '^--' ]] ; do
    if  [[ "$1" =~ '^--(force-re-register|force)$' ]] ; then force_arg="$1" force_re_register=true ; shift
    elif  [[ "$1" =~ '^--allow-lone[^=]*$' ]] ; then allow_lone_registry=true ; shift 
    elif [[ "$1" =~ '^--disallow-lone[^=]*$' ]] ; then allow_lone_registry=false ; shift 
    elif [[ "$1" =~ '^--dry-run$' ]] ; then dry_run=true ; shift 
    # possibly add more options here, later on
    else break
    fi
  done

  # load GDM_ERRORS (expand associate keys as local variables)
  if ! eval "$(gdm_fromMap GDM_ERRORS --local --all)" ; then 
    echo "$(_S R E)gdm_error_code_misread$(_S)" >&2  ; return $GDM_ERRORS[gdm_error_code_misread]
  fi

  local requirement requirement_error
  requirement="$(gdm_parseRequirement $@)" ; requirement_error=$? #FUNCTION CALL: gdm_parseRequirement
  ((requirement_error==invalid_argument)) && return $invalid_argument ;
  local $GDM_REQUIREMENT_VARS #NEW
  # local remote_url rev rev_is hash tag branch to setup setup_hash regis_parent_dir regis_prefix regis_suffix regis_id
  # local regis_instance destin_instance regis_manifest regis_snapshot previously_registered previous_regis_error
  eval "$requirement"
  
  local register_created=false # outputVars are $requirement assigments + register_created
  local outputVars=(remote_url rev rev_is hash tag branch to setup setup_hash regis_parent_dir regis_prefix regis_suffix regis_id
    regis_instance destin_instance regis_manifest regis_snapshot previously_registered previous_regis_error register_created)
  
  if $previously_registered ; then
    echo "$(_S D S E)Validating previous registration for $@ in ${regis_instance//$GDM_REGISTRY\//} ...$(_S)" >&2
    if ((previous_regis_error==0)) ; then
      echo "$(_S G)Previous registration is valid!$(_S) Location: \$GDM_REGISTRY/${regis_parent_dir#*$GDM_REGISTRY/}/$regis_id" >&2
      if $force_re_register ; then echo "$(_S M)Re-generating registration.$(_S) Reason: $force_arg" >&2
      else
        gdm_echoVars $outputVars ; return 0 ;
      fi

    elif ((previous_regis_error==manifest_missing)) ; then 
      echo "$(_S M)Generating new registration.$(_S) Reason: previous regis_manifest not found in \$GDM_REGISTRY" >&2
    else echo "$(_S M)Re-generating registration.$(_S) Reason: $(gdm_keyOfMapWithVal GDM_ERRORS $previous_regis_error)" >&2
    fi
  else
    echo "$(_S M)Generating new registration for $@$(_S) Reason: not previously registered." >&2
  fi

  if $dry_run ; then gdm_echoVars $outputVars ; return 0 ; fi


  # REMOVE OLD BEFORE (RE)CREATING REGISTER:
  [[ -d "$regis_instance" ]] && rm -rf "$regis_instance" ;
  # [[ -f "$regis_manifest" ]] && rm -rf "$regis_manifest" ; # (commented out since regis_manifest is inside regis_instance)
  [[ -d "$regis_snapshot" ]] && rm -rf "$regis_snapshot" ;
  mkdir -p "$regis_parent_dir"

  local gdm_version="$GDM_VERSION"
  # local regis_instance="\$GDM_REGISTRY/${regis_parent_dir#*$GDM_REGISTRY/}/$regis_id" #Not sure why I had this
  local manifest_contents gdm_manifest_inode

  # CLONE:
  gdm_echoAndExec "cd \"$regis_parent_dir\" && git clone --filter=blob:none --no-checkout \"$remote_url\" \"$regis_id\"" || return $clone_failed
  # CHECKOUT:
  gdm_echoAndExec "cd \"$regis_parent_dir/$regis_id\" && git checkout \"$hash\"" || return $checkout_failed
  # SETUP:
  if ! [[ -z "$setup" ]] ; then gdm_echoAndExec "cd \"$regis_parent_dir/$regis_id\" && $setup \"$destin_instance\"" || return $setup_returned_error ; fi
  # MAKE MANIFEST:
  touch "$regis_manifest" || return $manifest_creation_failed
  gdm_manifest_inode="$(gdm_getInode "$regis_manifest")" || return $manifest_creation_failed
  manifest_contents="$(gdm_echoVars $GDM_MANIF_VARS)" # GDM_MANIF_VARS is a global
  echo -n "$manifest_contents" > "$regis_manifest" || return $manifest_creation_failed
  # MAKE A SNAPSHOT of the requirement. (init a new repo and store .git as the snapshot. NOTE: tempdir non-local. Good idea?): 
  tempdir=$(mktemp -d 2>/dev/null || mktemp -d -t 'mytmpdir') || return $snapshot_tempdir_failed # But first...
  gdm_mvSubdirsTo "$regis_parent_dir/$regis_id" '.git' "$tempdir"  || return $snapshot_preswap_failed # move out all current .git/
  gdm_echoAndExec "cd \"$regis_parent_dir/$regis_id\" && git init && git add . && git commit -m \"$manifest_contents\"" || return $snapshot_failed
  mkdir "$regis_parent_dir/$regis_id.$GDM_SNAP_EXT" || return $snapshot_mkdir_failed # we'll move snapshot's .git/ to this directory
  mv "$regis_parent_dir/$regis_id/.git" "$regis_parent_dir/$regis_id.$GDM_SNAP_EXT" || return $?
  gdm_mvSubdirsTo "$tempdir" '.git' "$regis_parent_dir/$regis_id" || return $snapshot_postswap_failed
  rm -rf "$tempdir"

  register_created=true
  echo "$(_S M)Done Registering$(_S)" >&2
  gdm_echoVars $outputVars 
  return 0
}




