

gdm.require() {


  # echo "call# $PROJ_CONFIG_IDX to gdm.require got $# arguments: $@"

  
  if [[ -z "$PROJ_ROOT" ]] ; then
    local err_code
    # echo "calling gdm.project" #TEST
    # DO NOT execute gdm.project in subshell i.e. capture
    gdm.project --traverse-parents --validate-version --validate-script #FUNCTION CALL: gdm.register
    proj_err=$? #TODO: but should we: gdm.project init ??

    if ((err_code)) ; then  #TODO: or should we let them know to init??
      echo "gdm.project returned $proj_err" #TEST
      return $? 
    fi
  else echo "$(_S G)Project found at $PROJ_ROOT$(_S)"  #TEST
  fi

  # --reset-unused-register --reset-lone-instance --reset-lone-instance
  # $force_re_register && force_re_require=true

  local allow_orphan=true #TODO make this an argument option?
  local lone_allow='--disallow-lone' ; $allow_orphan && lone_allow='--allow-lone'


  # load GDM_ERRORS (expand associate keys as local variables)
  if ! eval "$(gdm_unpack GDM_ERRORS --local --all)" ; then 
    echo "$(_S R E)gdm_error_code_misread$(_S)" >&2  ; return $GDM_ERRORS[gdm_error_code_misread]
  fi

  ####### REGISTER REQUIREMENT, GETTING REGISTRATION VARS #############################################################
  
  local registration ; local reg_error=0
  registration="$(gdm.register $@)" || reg_error=$? #FUNCTION CALL: gdm.register
  #TODO: create some way to force reregistering of registers without any required instances:
  # if $force_re_register ; then registration="$(gdm.register --force $@)" || error=$?
  # else registration="$(gdm.register $@)" || error=$?
  # fi
  if ((reg_error)) ; then 
    echo "$(_S R E)Registration of $@ failed!$(_S)" >&2
    local reason="$(gdm_keyOfMapWithVal GDM_ERRORS $reg_error)"
    ! [[ -z $reason ]] && echo "$(_S R E)Reason: $reason$(_S)" >&2 || echo "$(_S R E)Error code $reg_error$(_S)" >&2
    # TODO: add suggested fix
    return $reg_error
  fi
  # declare as local, all variables assigned in registration string:
  local $GDM_REGISTRATION_VARS # Used: remote_url hash tag setup register_id register_path required_path register_manifest register_snapshot
  # NOT CURRENTLY USED: rev rev_is  branch to  register_parent prev_registered prev_registration_error register_created
  eval "$registration"


  ##### IF REQUIREMENT WAS PREVIOUSLY INSTALLED WITH VALID MANIFEST, RETURN  ##########################################
  local required_manifest="$required_path/$register_id.$GDM_MANIF_EXT"
  local manif_valid_assigns="$(gdm_echoVars --local $GDM_MANIF_VALIDATABLES)" #TODO: I made this local. Still working??
  local required_instance_err
  local snapshot_diff=""
  snapshot_diff="$(gdm_validateInstance --required --show-snapshot-mismatch-diff $lone_allow $required_manifest $required_path $register_snapshot $manif_valid_assigns $GDM_MANIF_VALIDATABLES)" #FUNCTION CALL: gdm_validateInstance
  required_instance_err=$?
  if ! ((required_instance_err)) ; then echo "$(_S G)Previous valid installation found at \"${required_path//$PWD/.}\"$(_S)" ; return 0 ; fi


  ##### POSSIBLY RECOVERABLE REQUIREMENT INSTALLATION ERRORS #########################################################
  local manifest_errors=($required_manifest_inode_mismatch $required_manifest_unlinked) # non-fatal gdm_validateInstance errors?
  if (($manifest_errors[(Ie)$required_instance_err])) ; then  #TODO test this
    
    ask "NEXT: REQUIRED INSTANCE MANIFEST ERROR: $(gdm.error $required_instance_err) REPAIR IT?" Y || return #TEST
    echo "HERE" #TEST
    if [[ -f $required_manifest ]] ; then
      ask "NEXT: REMOVING REQUIRED INSTANCE MANIFEST. continue?" Y || return #TEST
      rm "$required_manifest" ;
    fi
    ask "NEXT: COPY IN NEW REQUIRED INSTANCE MANIFEST. continue?" Y || return #TEST
    gdm_echoAndExec "cp -al \"$register_manifest\" \"$required_manifest\"" || {
      echo "Suggested fix: remove current installation (first backing up if desired) by running\n\n  $(_S B)rm -rf \"${required_path//$PWD/.}\"$(_S)\n\nthen require again."
      return $GDM_ERRORS[hardlink_failed]
    }
    #TODO: this gdm_validateInstance seems incorrect: first 3 non-flags should be paths of manifest instance snapshot
    #TODO: but we have manif_valid_assigns which is values of register_path remote_url hash tag setup_hash
    gdm_validateInstance --register "$manif_valid_assigns" register_path remote_url hash tag setup #FUNCTION CALL: gdm_validateInstance
    prev_inst_error=$? #TODO incorrect args???
  fi

 

  # if prev_inst_error is in gdm_validateInstance errors then we backup?
  local backup_ables=($required_manifest_version_outdated $required_manifest_unlinked $required_manifest_requirement_mismatch $required_was_modified) 

  if (($backup_ables[(Ie)$prev_inst_error])) ; then 
    if ((prev_inst_error==required_manifest_version_outdated)) ; then #TODO test
      echo "$(_S Y S)Previous installation from an earlier version of gdm was found at \"${required_path//$PWD/.}\"$(_S)"
    elif ((prev_inst_error==required_manifest_unlinked)) ; then #TODO test
      echo "$(_S Y S)Previous installation not tracked by gdm was found at \"${required_path//$PWD/.}\"$(_S)"
    elif ((prev_inst_error==required_manifest_requirement_mismatch)) ; then #TODO test
      echo "$(_S Y S)Previous installation with incorrect requirements was found at \"${required_path//$PWD/.}\"$(_S)"
    elif ((prev_inst_error==required_was_modified)) ; then #TODO test
      echo "$(_S Y S)Previous installation with files that have since been modified was found at \"${required_path//$PWD/.}\"$(_S)"
    fi

    local required_backup
    if ! required_backup="$(_renameDir $required_path)" ; then
      echo "$(_S R) attempt to backup \"${required_path//$PWD/.}\" failed" ; return $left_corrupted
    fi
    echo "$(_S Y S)Previous installation was backed up to \"${required_backup//$PWD/.}\"\nYou may want to delete this if it is not needed."
    prev_inst_error=$required_instance_missing
  fi

  ##### RE-INSTALLATON OR LEAN NEW INSTALLATON OF REQUIREMENT  #########################################################
  if ((prev_inst_error==required_instance_missing)) ; then # required_path is missing
    echo "$(_S D S E)Installing to \"${required_path//$PWD/.}\" from \"${register_path//$GDM_REGISTRY/\$GDM_REGISTRY}\"$(_S)"
    if ! [[ -e "${required_path:h}" ]] ; then
      gdm_echoAndExec "mkdir -p \"${required_path:h}\"" || return $GDM_ERRORS[mkdir_GDM_REQUIRED_failed]
    fi
    # cp -al "$register_path" "$required_path" >/dev/null 2>&1 || return $GDM_ERRORS[hardlink_failed] #OLD
    gdm_echoAndExec "cp -al \"$register_path\" \"$required_path\"" || return $GDM_ERRORS[hardlink_failed] #NEW
    echo "$(_S G)Installation to \"${required_path//$PWD/.}\" complete.$(_S)" ; return 0
  fi


  ##### NON-RECOVERABLE REQUIREMENT INSTALLATION ERRORS ###############################################################
  # if ((prev_inst_error)) ; then 

  #   if ((prev_inst_error==required_was_modified)) ; then # required_path is missing
  #     echo "$(_S R E)Installation of $@ failed because previous installation has be modified. Output from diff:$(_S)" >&2
  #     echo "$snapshot_diff" >&2
  #     #TODO: suggested fix: "if you want to keep these changes they must not be tracked by GDM so move the directory" 
  #     #TOD: (and if it is in config array suggest to remove it from there)
  #     return $prev_inst_error

  #   else
  #     echo "$(_S R E)Installation of $@ failed!$(_S)" >&2
  #     local reason="$(gdm_keyOfMapWithVal GDM_ERRORS $prev_inst_error)"
  #     ! [[ -z $reason ]] && echo "$(_S R E)Reason: $reason$(_S)" >&2 || echo "$(_S R E)Error code $prev_inst_error$(_S)" >&2
  #     # TODO: add suggested fix
  #     return $prev_inst_error
  #   fi
  # fi

  # now we have all but register_snapshot_missing covered, but that was checked with gdm_validateInstance of register_path

  if ((prev_inst_error)) ; then 
    echo "$(_S R E)Installation of $@ failed!$(_S)" >&2
    local reason="$(gdm_keyOfMapWithVal GDM_ERRORS $prev_inst_error)"
    ! [[ -z $reason ]] && echo "$(_S R E)Reason: $reason$(_S)" >&2 
    # TODO: add suggested fix
    return $prev_inst_error
  fi

}



