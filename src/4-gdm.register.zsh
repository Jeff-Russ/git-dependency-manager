gdm.register() {
  # Input is the following arguments:
  #     [https://][domain]<vendor>/<repo>[.git][#<hash>|<tag>|<branch>] [ setup=<function>|<script_path>|cmd> ] [ to=<path> | as=<dirname> ]
  # 
  local outputVars=(remote_url rev rev_is hash tag branch destin_option setup setup_hash regis_parent_dir regis_prefix regis_suffix 
      previously_registered register_created regis_instance regis_manifest regis_snapshot destin_instance requirement_lock) 
  
  local force_re_register=false
  local allow_lone_registry=true
  local dry_run=false

  if ! (($#)) ; then
    echo "$(_S Y)$gdm.require received no arguments!$(_S)" >&2  ; return $GDM_ERRORS[invalid_argument]
  fi

  while [[ "$1" =~ '^--' ]] ; do
    if  [[ "$1" =~ '^--(force-re-register|force)$' ]] ; then allow_lone=true ; shift 
    elif  [[ "$1" =~ '^--allow-lone[^=]*$' ]] ; then allow_lone_registry=true ; shift 
    elif [[ "$1" =~ '^--disallow-lone[^=]*$' ]] ; then allow_lone_registry=false ; shift 
    elif [[ "$1" =~ '^--dry-run$' ]] ; then dry_run=true ; shift 
    # possibly add more options here, later on
    else break
    fi
  done

  local requirement error 
  requirement="$(gdm_parseRequirement $@)" || return $? # FUNCTION CALL
  local remote_url rev rev_is hash tag branch destin_option setup setup_hash regis_parent_dir regis_prefix regis_suffix regis_instance destin_instance
  
  # The above are requirement vars set by eval of output from gdm_parseRequirement:
  #   remote_url=<expanded from repo_identifier, usualy lowercased)
  #   rev=[<value after # in repo_identifier]
  #   rev_is="hash|tag|tag_pattern|branch"
  #   hash=<full_hash (lowercased) from repo_identifier>
  #   tag=[<full_tag not lowercased>]
  #   branch=[<branch_name not lowercased>]
  #   destin_option=as|to-proj-as|to-fs-as|to-proj-in|to-fs-in       (never blank-'as' if not provided)
  #   setup_hash=[hash of setup if passed] 
  #   regis_parent_dir="$GDM_REGISTRY/domain/vendor/repo"
  #   regis_prefix="<tag if found>|<estim. short hash if no tag>"
  #   regis_suffix="_setup-<setup hash>"
  #   regis_instance="$regis_parent_dir/$regis_prefix$regis_suffix"
  #   destin_instance="<full abs path to location where required>"
  eval "$requirement" ; # all requirement vars are set but rev, branch, tag may be empty.

  local repo_name="${remote_url:t:r}" # Needed??
  local manifest_found=false
  local regis_id="$regis_prefix$regis_suffix"

  if [[ -d "$regis_parent_dir" ]] ; then
    if [[ -z $tag ]] ; then
    local hash_backup="$hash"
    local found_hash
      for len in {$#regis_prefix..$#hash} ; do
        regis_prefix="$hash[1,$len]"
        regis_id="$regis_prefix$regis_suffix"
        
        if [[ -f "$regis_parent_dir/$regis_id/$regis_id.$GDM_MANIF_EXT" ]] ; then 
          found_hash=$(source "$regis_parent_dir/$regis_id/$regis_id.$GDM_MANIF_EXT" && echo "$hash") || break
          if [[ $found_hash == $hash ]] ; then  manifest_found=true ; break ; fi
          # else # doesn't match so we need a longer short hash (regis_prefix)
        else  break # missing, so we can use this short hash (regis_prefix)
        fi
      done
      hash="$hash_backup"
    elif [[ -f "$regis_parent_dir/$regis_id/$regis_id.$GDM_MANIF_EXT" ]] ; then manifest_found=true
    fi
  fi

  # local regis_instance="$regis_parent_dir/$regis_id" #changed gdm_register_path to regis_instance
  local regis_manifest="$regis_instance/$regis_id.$GDM_MANIF_EXT" #changed gdm_register_path to regis_instance
  local regis_snapshot="$regis_instance.$GDM_SNAP_EXT" #changed gdm_register_path to regis_instance

  local previously_registered=false
  local register_created=false

  # load GDM_ERRORS (expand associate keys as local variables)
  if ! eval "$(gdm_fromMap GDM_ERRORS --local --all)" ; then 
    echo "$(_S R E)gdm_error_code_misread$(_S)" >&2  ; return $GDM_ERRORS[gdm_error_code_misread]
  fi

  if $manifest_found ; then
    local prev_reg_error=0
    local assignments="$(gdm_echoVars $GDM_MANIF_VALIDATABLES)" #changed gdm_register_path to regis_instance
    ! $dry_run && echo "$(_S D S E)Validating previous registration of ${regis_instance//$GDM_REGISTRY\//} ...$(_S)" >&2
    local lone_allow='--disallow-lone' ; $allow_lone_registry && lone_allow='--allow-lone'
    gdm_validateInstance $lone_allow $regis_manifest $regis_instance $regis_snapshot "$assignments" $GDM_MANIF_VALIDATABLES ; prev_reg_error=$? #changed gdm_register_path to regis_instance

    if ! ((prev_reg_error)) ; then 
      previously_registered=true
      ! $dry_run && echo "$(_S G)Previous registration is valid!$(_S) Location: \$GDM_REGISTRY/${regis_parent_dir#*$GDM_REGISTRY/}/$regis_id" >&2
      if ! $force_re_register || $dry_run ; then 
        gdm_echoVars $outputVars #TODO?
        return 0
      fi
    else
      if $dry_run ; then
        echoVars $outputVars #TODO?
        return $prev_reg_error
      fi
      echo "$(_S M)Re-generating registration.$(_S) Reason: $(gdm_keyOfMapWithVal GDM_ERRORS $prev_reg_error)" >&2
    fi
  elif [[ -d "$regis_instance" ]] ; then #changed gdm_register_path to regis_instance
    if $dry_run ; then gdm_echoVars $outputVars ; return $manifest_missing ; fi
    echo "$(_S M)Generating new registration for $@$(_S) Reason: previous regis_manifest not found in \$GDM_REGISTRY" >&2
  else
    if $dry_run ; then gdm_echoVars $outputVars ; return $instance_missing ; fi
    echo "$(_S M)Generating new registration for $@$(_S) Reason: not previously registerd." >&2
  fi

  # if $dry_run && gdm_echoVars $outputVars ; return 1 ; fi
  
  # remote_url rev rev_is hash tag branch  setup destin_instance regis_parent_dir regis_prefix regis_suffix previously_registered register_created regis_instance regis_manifest regis_snapshot #changed gdm_register_path to regis_instance
  if $force_re_register ; then echo "$(_S M)Generating new registration for $@$(_S) Reason: --force-re-register" >&2 ; fi

  # REMOVE OLD BEFORE (RE)CREATING REGISTER:
  [[ -d "$regis_instance" ]] && rm -rf "$regis_instance" ; #NEW
  # [[ -f "$regis_manifest" ]] && rm -rf "$regis_manifest" ; #NEW (commented out since regis_manifest is inside regis_instance)
  [[ -d "$regis_snapshot" ]] && rm -rf "$regis_snapshot" ; #NEW
  mkdir -p "$regis_parent_dir"

  local gdm_version="$GDM_VERSION"
  local regis_instance="\$GDM_REGISTRY/${regis_parent_dir#*$GDM_REGISTRY/}/$regis_id" #changed gdm_register_path to regis_instance
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
  # MAKE A SNAPSHOT of the requirement (init a new repo and store .git as the snapshot): 
  tempdir=$(mktemp -d 2>/dev/null || mktemp -d -t 'mytmpdir') || return $snapshot_tempdir_failed # But first...
  gdm_mvSubdirsTo "$regis_parent_dir/$regis_id" '.git' "$tempdir"  || return $snapshot_preswap_failed # move out all current .git/
  gdm_echoAndExec "cd \"$regis_parent_dir/$regis_id\" && git init && git add . && git commit -m \"$manifest_contents\"" || return $snapshot_failed
  mkdir "$regis_parent_dir/$regis_id.$GDM_SNAP_EXT" || return $snapshot_mkdir_failed # we'll move snapshot's .git/ to this directory
  mv "$regis_parent_dir/$regis_id/.git" "$regis_parent_dir/$regis_id.$GDM_SNAP_EXT" || return $?
  gdm_mvSubdirsTo "$tempdir" '.git' "$regis_parent_dir/$regis_id" || return $snapshot_postswap_failed
  rm -rf "$tempdir"

  register_created=true
  echo "$(_S M)Done Registering$(_S)" >&2
  gdm_echoVars $outputVars #TODO?
  return 0
}
