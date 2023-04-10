gdm.require() {

  # --reset-unused-register --reset-lone-instance --reset-lone-instance 
  # echo "call# $PROJ_CONFIG_IDX to gdm.require got $# arguments: $@"

  # if [[ -z "$PROJ_ROOT" ]] ; then
  #   gdm.init >/dev/null || return $?
  #   echo "GDM_CALL_STATUS=$GDM_CALL_STATUS"
  # fi
  # echo "  gdm require $@"

  # GDM_FFTRACE=("${functrace[@]}") 
  # gdm_echoVars GDM_FFTRACE #ARRAY_APPEND -> GDM_FFTRACE

  # if ! (($#)) ; then
  #   echo "$(_S Y)\$gdm.require received no arguments!$(_S)" >&2  ; return $GDM_ERRORS[invalid_argument]
  # fi


  # $force_re_register && force_re_require=true

  local allow_orphan=true #TODO make this an argument option?
  local lone_allow='--disallow-lone' ; $allow_orphan && lone_allow='--allow-lone'

  [[ -z "$PROJ_ROOT" ]] && PROJ_ROOT="$PWD" ; # TODO: this is unsafe: PROJ_ROOT should always be non-empty in require

  # load GDM_ERRORS (expand associate keys as local variables)
  if ! eval "$(gdm_fromMap GDM_ERRORS --local --all)" ; then 
    echo "$(_S R E)gdm_error_code_misread$(_S)" >&2  ; return $GDM_ERRORS[gdm_error_code_misread]
  fi
  
  local registration ; local reg_error=0
  registration="$(gdm.register $@)" || reg_error=$? #FUNCTION CALL: gdm.register

  # if $force_re_register ; then registration="$(gdm.register --force $@)" || error=$?
  # else registration="$(gdm.register $@)" || error=$?
  # fi
  if ((reg_error)) ; then 
    echo "$(_S R E)Registration of $@ failed!$(_S)" >&2
    local reason="$(gdm_keyOfMapWithVal GDM_ERRORS $reg_error)"
    ! [[ -z $reason ]] && echo "$(_S R E)Reason: $reason$(_S)" >&2 

    # TODO: add suggested fix
    return $reg_error
  fi

  # variables assigned in registration string:
  local $GDM_REGISTRATION_VARS # Used: remote_url hash tag setup regis_id regis_instance destin_instance regis_manifest regis_snapshot
  # NOT CURRENTLY USED: rev rev_is  branch to  regis_parent_dir previously_registered previous_regis_error register_created
  eval "$registration"


  ##### VALIDATE REQUIRED INSTANCE VIA MANIFEST  ##################################################
  local destin_manifest="$destin_instance/$regis_id.$GDM_MANIF_EXT"
  local assignments="$(gdm_echoVars $GDM_MANIF_VALIDATABLES)" #TODO: shouldn't these be --local? see gdm_validateInstance
  local prev_inst_error
  gdm_validateInstance $lone_allow $destin_manifest $destin_instance $regis_snapshot "$assignments" $GDM_MANIF_VALIDATABLES #FUNCTION CALL: gdm_validateInstance
  prev_inst_error=$?

  ##### RETURN IF REQUIRED INSTANCE IS VALID  #####################################################
  if ! ((prev_inst_error)) ; then echo "$(_S G)Previous valid installation found at \"${destin_instance//$PWD/.}\"$(_S)" ; return 0 ; fi

  local retry_ables=($manifest_inode_mismatch $manifest_missing) # non-fatal gdm_validateInstance errors?
  if (($retry_ables[(Ie)$prev_inst_error])) ; then  #TODO test this
    gdm_echoAndExec "cp -al \"$regis_manifest\" \"$destin_manifest\"" || {
      echo "Suggested fix: $reinistall_msg remove current installation (first backing up if desired) by running\n\n  $(_S B)rm -rf \"${destin_instance//$PWD/.}\"$(_S)\n\nthen require again."
      return $GDM_ERRORS[hardlink_failed]
    }
    gdm_validateInstance "$assignments" regis_instance remote_url hash tag setup #FUNCTION CALL: gdm_validateInstance
    prev_inst_error=$? #TODO incorrect args???
  fi

  # if prev_inst_error is in gdm_validateInstance errors then we backup?
  local backup_ables=($gdm_version_outdated $lone_instance $manifest_requirement_mismatch $instance_snaphot_mismatch) 

  if (($backup_ables[(Ie)$prev_inst_error])) ; then 
    if ((prev_inst_error==gdm_version_outdated)) ; then #TODO test
      echo "$(_S Y S)Previous installation from an earlier version of gdm was found at \"${destin_instance//$PWD/.}\"$(_S)"
    elif ((prev_inst_error==lone_instance)) ; then #TODO test
      echo "$(_S Y S)Previous installation not tracked by gdm was found at \"${destin_instance//$PWD/.}\"$(_S)"
    elif ((prev_inst_error==manifest_requirement_mismatch)) ; then #TODO test
      echo "$(_S Y S)Previous installation with incorrect requirements was found at \"${destin_instance//$PWD/.}\"$(_S)"
    elif ((prev_inst_error==instance_snaphot_mismatch)) ; then #TODO test
      echo "$(_S Y S)Previous installation with files that have since been modified was found at \"${destin_instance//$PWD/.}\"$(_S)"
    fi

    local destin_instance_backup
    if ! destin_instance_backup="$(_renameDir $destin_instance)" ; then
      echo "$(_S R) attempt to backup \"${destin_instance//$PWD/.}\" failed" ; return $left_corrupted
    fi
    echo "$(_S Y S)Previous installation was backed up to \"${destin_instance_backup//$PWD/.}\"\nYou may want to delete this if it is not needed."
    prev_inst_error=$instance_missing
  fi

  if ((prev_inst_error==instance_missing)) ; then # destin_instance is missing
    echo "$(_S D S E)Installing to \"${destin_instance//$PWD/.}\" from \"${regis_instance//$GDM_REGISTRY/\$GDM_REGISTRY}\"$(_S)"
    gdm_echoAndExec "mkdir -p \"$destin_instance:h\"" || return $GDM_ERRORS[mkdir_GDM_REQUIRED_failed]
    # cp -al "$regis_instance" "$destin_instance" >/dev/null 2>&1 || return $GDM_ERRORS[hardlink_failed] #OLD
    gdm_echoAndExec "cp -al \"$regis_instance\" \"$destin_instance\"" || return $GDM_ERRORS[hardlink_failed] #NEW
    echo "$(_S G)Installation complete.$(_S)" ; return 0
  fi

  if ((prev_inst_error)) ; then 
    echo "$(_S R E)Installation of $@ failed!$(_S)" >&2
    local reason="$(gdm_keyOfMapWithVal GDM_ERRORS $reg_error)"
    ! [[ -z $reason ]] && echo "$(_S R E)Reason: $reason$(_S)" >&2 
    # TODO: add suggested fix
    return $reg_error
  fi

  # now we have all but regis_snapshot_missing covered, but that was checked with gdm_validateInstance of regis_instance
}



