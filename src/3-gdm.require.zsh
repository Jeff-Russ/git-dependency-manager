gdm.require() {

  # echo "call# $GDM_PROJ_CONFIG_IDX to gdm.require got $# arguments: $@"
  
  if [[ -z "$GDM_PROJ_ROOT" ]] ; then
    local proj_err
    # echo "calling gdm.project" #TEST
    # DO NOT execute gdm.project in subshell i.e. capture
    gdm.project --traverse-parents --validate-version --validate-script #FUNCTION CALL: gdm.register
    proj_err=$? #TODO: but should we: gdm.project init ??

    if ((proj_err)) ; then  #TODO: or should we let them know to init??
      echo "gdm.project returned $proj_err" #TEST
      return $? 
    fi
  else echo "$(_S G)Project found at $GDM_PROJ_ROOT$(_S)"  #TEST
  fi


  # load GDM_ERRORS (expand associate keys as local variables)
  if ! eval "$(gdm_unpack GDM_ERRORS --local --all)" ; then 
    echo "$(_S R E)gdm_error_code_misread$(_S)" >&2  ; return $GDM_ERRORS[gdm_error_code_misread]
  fi

  ####### REGISTER REQUIREMENT, GETTING REGISTRATION VARS #############################################################

  local conf_entry
  
  local registration ; local reg_error=0
  registration="$(gdm.register $@)" || reg_error=$? #FUNCTION CALL: gdm.register
  #TODO: create some way to force reregistering of registers without any required instances:
  # if $force_re_register ; then registration="$(gdm.register --re-register-unlinked $@)" || error=$?
  # else registration="$(gdm.register $@)" || error=$?
  # fi
  #TODO: handle errors similar to as we do with validation of required instance (later in this function)
  if ((reg_error)) ; then 
    echo "$(_S R E)Registration of $@ failed! $(_S)" >&2
    local reason="$(gdm_keyOfMapWithVal GDM_ERRORS $reg_error)"
    ! [[ -z $reason ]] && echo "$(_S R E)Reason: $reason$(_S)" >&2 || echo "$(_S R E)Error code $reg_error$(_S)" >&2
    # TODO: add suggested fix
    return $reg_error
  fi
  # declare as local, all variables assigned in registration string:
  local $GDM_REGISTRATION_VARS # Used: remote_url hash tag setup register_id register_path required_path register_manifest register_snapshot
  # NOT CURRENTLY USED: rev rev_is  branch destin  register_parent prev_registered prev_registration_error register_created
  eval "$registration"

  
  ##### WORKING WITH PREVIOUSLY REQUIRED INSTANCE #####################################################################
  #NOTE: If we are still here, we are done with registering (were registered without error)
  local required_manifest="$required_path/$register_id.$GDM_MANIF_EXT"
  local manif_valid_assigns="$(gdm_echoVars --local $GDM_MANIF_VALIDATABLES)" 
  local validateReqInst_args=(--required --show-output $required_manifest $required_path $register_snapshot $manif_valid_assigns $GDM_MANIF_VALIDATABLES)


  #----- IF REQUIREMENT WAS PREVIOUSLY INSTALLED WITH VALID MANIFEST, RETURN  -------------------------------
  
  local required_instance_err
  local validateReqInst_output=""
  validateReqInst_output="$(gdm_validateInstance $validateReqInst_args[@])" ; required_instance_err=$? #FUNCTION CALL: gdm_validateInstance
  if ! ((required_instance_err)) ; then echo "$(_S G)Previous valid installation found at \"${required_path//$PWD/.}\"$(_S)" ; return 0 ; fi
  # NOTE The most likely `else` here is required_instance_err==required_instance_missing but we'll hold off on handling that because
  # we may have some other errors that would be handled by fixing the manifest or backing up and reinstalling..

  ####### HELPERS FOR PREVIOUS INSTALLATION VALIDATION ERROR MESSAGES #################################################
  # Use on $GDM_ERRORS[<show in comments below>] from gdm_validateInstance --required
  $0.suggestBackupAndReRequire() { # use on any unrecoverable $GDM_ERRORS
    echo "Suggested fix: remove current installation (first backing up if desired) by running"
    echo "\n  $(_S B)rm -rf \"${required_path//$PWD/.}\"$(_S)\n\nthen require again."
  }
  $0.showModifiedInfo() { # use on $GDM_ERRORS[required_was_modified] 
    echo "$(_S Y S)Previous installation with files that have since been modified was found at \"${required_path//$PWD/.}\"$(_S)"
    echo "$(_S Y S)Here is the output from git diff:\n$(_S)$validateReqInst_output" 
  }
  $0.showReqMismatchInfo() { # use on $GDM_ERRORS[required_manifest_requirement_mismatch]
    echo "$(_S Y S)Previous installation found at \"${required_path//$PWD/.}"
    echo "failed validation due to it's manifest not matching the following requirements:$(_S)\n"
  }
  $0.showAnyErrorInfo() { # use on other $GDM_ERRORS
    local required_instance_err_key="$(gdm_keyOfMapWithVal GDM_ERRORS $required_instance_err)"
    [[ -z $required_instance_err_key ]] && required_instance_err_key="$required_instance_err"
    echo "$(_S Y S)Previous installation found which failed validation (returning $required_instance_err_key)"
    echo "was found at \"${required_path//$PWD/.}\"$(_S)"
  }

  ####### ATTEMPT TO RECOVER FROM PREVIOUS REQUIREMENT INSTALLATION ERRORS #############################################
  #NOTE: This all depends on the order of checks in gdm_validateInstance, so if they're modifed, this must also be!
  
  # $required_instance_missing              #31 All clear to install but we'll hold off to respond to recoverables first
  local replace_manifest_and_revalidate=(
    $required_manifest_missing              #32 $required_manifest file does not exist (try to insert it but if we git a diff error, remove it)
  )
  local backup_and_reinstall=(
    $required_manifest_requirement_mismatch #33 Can happen if required_path was used before with different requirement (HAS OUTPUT of all mismatches)
    # $register_snapshot_missing            #30 IMPOSSIBLE since would have already happened as reg_error
    # $required_snapshot_gitswap_failed     #34 UNRECOVERABLE and unexpected: Cannot swap $required_path/.git to or from $required_path.gdm_snapshot/.git
    $required_was_modified                  #35 (HAS OUTPUT from diff) $required_path code mismatches snapshot
  )
  replace_manifest_and_revalidate+=(
    $required_manifest_inode_mismatch       #36 (diff passed but) manifest file's inode does not match what it reports (replace and, if still failing return fail)
  )
  # $required_manifest_version_outdated     #37 IMPOSSIBLE since register manifest wasn't outdated and we now know inode and content are the same
  # $required_manifest_unlinked             #38 IMPOSSIBLE since inode is the same (--disallow-unlinked (not the default) and $required_manifest has no hardlinks)

  local revert_code="" # PREPEND on some code here (in one line w/semicolons or \n) to be eval'ed upon ultimate failure (even if empty)
  if (($replace_manifest_and_revalidate[(Ie)$required_instance_err])) ; then  #TODO test this
    # Before creating a new $required_manifest, remove it if it exists, else we'll remove created one if we fail:
    [[ -f $required_manifest ]] && rm "$required_manifest" || revert_code="[[ -f $required_manifest ]] && rm \"$required_manifest\" ; $revert_code"
    # Link in new $required_manifest:
    gdm_echoAndExec "cp -al \"$register_manifest\" \"$required_manifest\"" || { 
      $0.suggestBackupAndReRequire ; eval "$revert_code" ; return $hardlink_failed
    }
    # re-validate required instance with correct required_manifest in place (we'll check out how this turned out later...)
    validateReqInst_output="$(gdm_validateInstance $validateReqInst_args[@])" ; required_instance_err=$? #FUNCTION CALL: gdm_validateInstance
  fi
  if (($backup_and_reinstall[(Ie)$required_instance_err])) ; then  # NOTE elif in case previous if changed required_instance_err
    if ((required_instance_err==required_was_modified)) ; then $0.showModifiedInfo  #TODO test
    else $0.showAnyErrorInfo # impossible unless we add to backup_and_reinstall array
    fi
    local required_backup
    if ! required_backup="$(gdm_autoRename $required_path)" ; then # this moves so $required_path is effectively deleted
      eval "$revert_code" # Note that this is no problem if revert_code is empty
      echo "$(_S R)Error: Attempt to backup \"${required_path//$PWD/.}\" failed" ; return $unexpected_error # impossible?
    fi
    echo "$(_S Y S)\"${required_path//$PWD/.}\" was backed up as \"${required_backup//$PWD/.}\"\nYou may want to delete this if it is not needed"
    revert_code="[[ -d $required_manifest ]] && rm -rf \"$required_path\" && mv \"$required_backup\" \"$required_path\" ; $revert_code"
    required_instance_err=$required_instance_missing
  fi


  ##### RE-INSTALLATON OR CLEAN NEW INSTALLATON OF REQUIREMENT  #######################################################
  if ((required_instance_err==required_instance_missing)) ; then # required_path is missing
    echo "$(_S D S E)Installing to \"${required_path//$PWD/.}\" from \"${register_path//$GDM_REGISTRY/\$GDM_REGISTRY}\"$(_S)"
    if ! [[ -e "${required_path:h}" ]] ; then
      gdm_echoAndExec "mkdir -p \"${required_path:h}\"" || {
        eval "$revert_code" # Note that this is no problem if revert_code is empty
        return $mkdir_GDM_REQUIRED_failed
      }
    fi
    gdm_echoAndExec "cp -al \"$register_path\" \"$required_path\"" || {
      eval "$revert_code" # Note that this is no problem if revert_code is empty
      return $hardlink_failed 
    }
    echo "$(_S G)Installation to \"${required_path//$PWD/.}\" complete.$(_S)" ; return 0
  fi


  ##### FINAL OR NON-RECOVERABLE REQUIREMENT INSTALLATION ERRORS ######################################################
  if ((required_instance_err)) ; then 
    echo "$(_S R E)Installation of $@ failed! $(_S)" >&2
    local reason="$(gdm_keyOfMapWithVal GDM_ERRORS $required_instance_err)"
    ! [[ -z $reason ]] && echo "$(_S R E)Reason: $reason$(_S)" >&2 || echo "$(_S R E)Error code $required_instance_err$(_S)" >&2
    # TODO: add suggested fix
    eval "$revert_code" # Note that this is no problem if revert_code is empty
    return $required_instance_err
  fi
}
