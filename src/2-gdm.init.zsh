
# export _GDM_TESTMODE="${GDM_TESTMODE:=false}"

export GDM_CALL_EVAL_CONTEXT="$ZSH_EVAL_CONTEXT" 
export GDM_CALL_FFTRACE=("${funcfiletrace[@]}") 
export GDM_CALLER_WD="$PWD"

export GDM_PROJ_VARS="" # archive of local var assignments used to assign each other PROJ_* var
export PROJ_CALL_STATUS=""
export PROJ_ROOT=""
export PROJ_CONFIG_FILE=""
export PROJ_CONFIG_WAS=""
# (The function body is the lines between the lines specified below)
export PROJ_CONFIG_STARTLINE=""  # starting line number for export config in scanned PROJ_CONFIG_FILE
export PROJ_CONFIG_ENDLINE=""    #   ending line number for exported config array in scanned PROJ_CONFIG_FILE
export PROJ_LOCK_STARTLINE=""  # starting line number for exported config_lock array in scanned PROJ_CONFIG_FILE
export PROJ_LOCK_ENDLINE=""    #   ending line number for exported config_lock array in scanned PROJ_CONFIG_FILE
export PROJ_CONFIG_ARRAY=()
export PROJ_LOCK_ARRAY=()
export PROJ_CONFIG_IDX=0 # should be incremented as index of both PROJ_CONFIG_ARRAY and PROJ_LOCK_ARRAY (at once)


gdm.init() {
  # gdm.init initializes a new project by creating GDM_REQUIRE_CONF if it is not found (always at WD 
  #             if --traverse-parents is not provided) and, if project is found, validates the GDM_REQUIRE_CONF
  #             If GDM_REQUIRE_CONF is valid this function runs gdm_exportFromProjVars 
  # IMPORTANT: do not execute gdm.init in a subshell as would be the case when capturing output. Exports would fail!
  # (for additional details, see commments for gdm.locateProject)
  gdm_loadProj --init $@
  return $?
}


gdm_loadProj() {
  # gdm_loadProj is a 'private' function that forms the core of gdm.init when called with --init
  #          Whether called with --init, if gdm_loadProj successfully finds a valid project, 
  #          establishes the caller project details by assigning exported variables pertaining to it
  #          by calling gdm_exportFromProjVars (see gdm_exportFromProjVars  for details).
  #          When --init is passed (as 1st arg only) to gdm_loadProj, as is done when called  by gdm.init,
  #             it will initialize a  new project by creating GDM_REQUIRE_CONF if it is not found (always at WD 
  #             if --traverse-parents is not provided) 
  #           But can  also be called elsewhere without --init to skip creating of a new GDM_REQUIRE_CONF
  #             and just perform the part that establishes the caller project details via calling gdm_exportFromProjVars
  # IMPORTANT: do not execute gdm_loadProj in a subshell as would be the case when capturing output. Exports would fail!
  # (for additional details, see commments for gdm.locateProject)
  local assignments call_err eval_err 

  echo "$(_S M)$0$(_S)" #TEST
  # echo "$(_S G)HERE$(_S)" #TEST

  if [[ "$1" == --init ]] ; then
    shift
    assigments="$(gdm.locateProject --init $@)" ; call_err=$? # locateProject will return $GDM_ERRORS[no_project_found] if "$config_was"=='missing' 
  else
    assigments="$(gdm.locateProject $@)" ; call_err=$?
  fi


  local call_status config_was proj_root proj_conf # all set in assigments
  local errors=() ; local config_startline config_endline lock_startline lock_endline  # more set in assigments
  eval "$assigments" ; eval_err=$?

  if ((eval_err)) ; then
    echo "$(_S R)Unexpected Error: eval of assigments from gdm.locateProject resulted in error code $eval_err$(_S)" >&2
    return 1
  fi

  local display_proj_root="current working directory"
  ! [[ "$proj_root" == "$GDM_CALLER_WD" ]] && display_proj_root="${proj_root//$GDM_CALLER_WD/.}"
  
  if ((call_err)) ; then
    if ((call_err==$GDM_ERRORS[malformed_config_file])) ; then
      echo "$(_S R)Previous project was found at $display_proj_root with errors in ${proj_conf//$GDM_CALLER_WD/.}:$(_S Y D)" >&2
      print -l $errors >&2 ; echo -n "$(_S M D)" >&2
      echo "Possible fix: make a temporaray backup ${proj_conf//$GDM_CALLER_WD/.} by renaming it, create a" >&2
      echo "              new file with \`\$GDM init\` and then copy your contents from the backup to the new file.$(_S)" >&2
    elif ((call_err==$GDM_ERRORS[no_project_found])) ; then
      echo "$(_S Y)No project was found!$(_S) Run \`\$GDM init\` to create one." >&2 
    else
      echo "$(_S R)Unexpected Error: gdm.locateProject returned error code $call_err$(_S Y D)" >&2
      print -l $errors >&2 ; echo -n "$(_S)" >&2
    fi
    return $call_err
  fi
  echo "gdm_exportFromProjVars assigments=\n$assigments" #TEST

  GDM_PROJ_VARS="$(gdm_echoVars --local --append-array call_status proj_root proj_conf config_was config_startline config_endline lock_startline lock_endline errors)"

  gdm_exportFromProjVars || return $?
  # call_err=$? ; ((call_err)) && return $?
  
  if  [[ "$config_was" == 'missing' ]] ; then 
    # this can only happen if called without --init, which would be caught above. So this block is unreachable
    echo "$(_S Y)No project was found!$(_S) Run \`\$GDM init\` to create one." >&2 
    return $GDM_ERRORS[no_project_found]
  elif [[ "$config_was" == 'created' ]] ; then
    echo "$(_S G)Project initialized at $display_proj_root, creating ${proj_conf//$GDM_CALLER_WD/.}$(_S)" 
  else # [[ "$config_was" == 'valid' ]] ; then
    echo "$(_S G)Previous project was found at $display_proj_root via valid file: ${proj_conf//$GDM_CALLER_WD/.}$(_S)" 
  fi

  return 0
}


gdm_exportFromProjVars() {
  local  eval_err 
  assigments="$1"
  echo "$0 got:\n$assigments\nEND $0 got" # $TEST
  local proj_root proj_conf config_startline config_endline lock_startline lock_endline # from assigments
      # 'call_status' proj_root proj_conf 'config_was' config_startline config_endline lock_startline lock_endline 
  eval "$GDM_PROJ_VARS" ; eval_err=$?
  if ((eval_err)) ; then
    echo "Unexpected Error in gdm_exportFromProjVars: eval of assigments resulted in error code $eval_err"
    return 1
  fi

  PROJ_CALL_STATUS="$call_status"
  PROJ_ROOT="$proj_root"
  PROJ_CONFIG_FILE="$proj_conf"
  PROJ_CONFIG_WAS="$config_was"
  PROJ_CONFIG_STARTLINE=$config_startline
  PROJ_CONFIG_ENDLINE=$config_endline
  PROJ_LOCK_STARTLINE=$lock_startline
  PROJ_LOCK_ENDLINE=$lock_endline 
  shift $# # clear to prevent sourcing from forwarding arguments
  source "$PROJ_CONFIG_FILE"
  PROJ_CONFIG_ARRAY=("${config[@]}")
  PROJ_LOCK_ARRAY=("${config_lock[@]}")
}

# for debugging:
gdm_echoProjVars() {
  typeset -m 'GDM_CALL*'
  typeset -m 'PROJ*'
}


gdm.locateProject() { 
  # gdm.locateProject looks for a project based on how GDM was executed and, 
  #                   if PROJ_CONFIG_FILE if not found and --init is passed, creates it.
  #          If a PROJ_CONFIG_FILE is found, gdm.locateProject validates it and returns an error if:
  #            1) $config_was==invalid  which means the config file:
  #                                a) is found in the call stack but did not directly source GDM
  #                                b) did not export arrays: config config_lock  or export the strings: GDM GDM_VER.
  #                                c) --validate-version was passed and the check failed (see below)
  #                                d) --validate-script  was passed and the check failed (see below)
  #                                e) exporting config config_lock as well as sourcing GDM are not done properly or in the correct order.
  #            2) $config_was=="unknown error" (unlikely, possibly impossible)
  #          If a PROJ_CONFIG_FILE is found and is valid, it parses the file, assigning exported variables (see 'side effects').
  # Prerequisites:
  #           GDM_REQUIRE_CONF, GDM_CALLER_WD, GDM_CALL_EVAL_CONTEXT, and GDM_CALL_FFTRACE must be exported with valid values and 
  #           PROJ_ROOT, GDM_PROJ_REQUIRE_LINES, GDM_PROJ_LOCK_LINES must be exported (the latter two as empty arrays)
  # Input (all optional and non-positional)
  #       --init              # if PROJ_CONFIG_FILE is missing, create it.
  #       --traverse-parents  # Unless provided and not called by GDM_CALLER_WD or executed with GDM_CALLER_WD 
  #                           # in the call stack, only the GDM_CALLER_WD is searched for GDM_REQUIRE_CONF
  #       --validate-version  # fail if GDM_VER is not compatible with GDM_VERSION by beginning with GDM_VER_COMPAT 
  #                           # (requires that the latter two exports be assigned by this script prior to calling)
  #       --validate-script   # fail if GDM is is not equal to $GDM_SCRIPT 
  #                           # (requires that GDM_SCRIPT be exported by/assiged to this script's "$0" prior to calling)
  # Output: (all stdout) of eval-able assigments of (appending to in the case of the errors array) the following:
  #    Always Output:
  #       call_status="$how by conf"|"$how with conf found in stack"|"$how from shell without project"|"$how from shell at project $where"
  #                 WHERE: how=sourced|executed and where=root|subdir
  #       config_was=created|valid|invalid|"unexpected error"
  #                                    # if config_was missing, it will be created and thus config_was is reassigned to created, which means valid
  #                                    # if config_was found, it only stays as such until validation, which reassigs it to valid or invalid
  #                                    # "unexpected error" is an internal error (returning 1) which indicates a bug in GDM
  #       proj_root=<fullpath>|""      # non-empty if found (via conf found or config_was==missing), whether valid or not
  #       proj_conf=<fullpath>|""      # non-empty if found, whether valid or not
  #       errors=(<plain strings>) # error messages normally to be displayed to user, 
  #                                    # accumulating all errors found before finaly failing if nonempty
  #              Possible errors (returning $GDM_ERRORS[malformed_config_file]):
  #                    "GDM was not directly sourced by \"$conf_file\" (GDM was ${call_status//conf/\"$conf_file\"})"
  #                    "export <"GDM_VER"|"GDM> not found in \"$conf_file\""
  #                    "GDM_VER from \"$conf_file\" not compatible with '$GDM_VERSION' called ($GDM_SCRIPT)"
  #                    "GDM from \"$conf_file\" does not match location of GDM_SCRIPT called ($GDM_SCRIPT)"
  #                    "array <"config"|"config_lock"> not exported in \"$conf_file\""
  #                    "exported config_lock array cannot be defined before config in \"$conf_file\" at line $line_num"
  #                    "config array cannot be exported after config_lock in \"$conf_file\" at line $line_num"
  #                    "exported config_lock array cannot be defined after sourcing GDM in \"$conf_file\" at line $line_num"
  #                    "GDM is not sourced and/or not forwarded arguments properly in \"$conf_file\" at line $line_num"
  #                    "GDM is called again in \"$conf_file\" at line $line_num"
  #                    "config array was not properly exported in \"$conf_file\""
  #                    "config_lock array was not properly exported in \"$conf_file\""
  #                    "GDM is not properly sourced in \"$conf_file\""
  #              Possible errors (returning 1):
  #                    "Unexpected Error in gdm.locateProject: unknown call_status"
  #                    "Unexpected Error in gdm.locateProject: eval of gdm.validateConf output resulted in error code $eval_err"
  #                    "Unexpected Error in gdm.locateProject: eval of gdm.locateConfSections output resulted in error code $eval_err"
  #                    "Unexpected argument to gdm.validateConf: $arg"
  #    Sometimes Output (always if non-failing):
  #         config_startline            # line where config array is exported
  #         config_endline              # line where config array is closed
  #         lock_startline              # line where exported config_lock array is declared
  #         lock_endline                # line where exported config_lock array is closed
  # side effects: 
  #       There are no side effects but that is due to the limitation that a subshell, which is how this function should be called
  #       cannot successfully reassign an exported variable. Therefore, non-failing (output with config_was equaling 'created' or 'valid'
  #       should normally trigger assigment of:
  #           PROJ_ROOT="$proj_root"
  #           PROJ_CONFIG_FILE="$proj_conf"
  #           PROJ_CONFIG_STARTLINE=$config_startline
  #           PROJ_CONFIG_ENDLINE=$config_endline
  #           PROJ_LOCK_STARTLINE=$lock_startline
  #           PROJ_LOCK_ENDLINE=$lock_endline
  #       (OLD VERSION TODO: delete)
  #           GDM_PROJ_REQUIRE_LINES+=("${config_start_end_lines[@]}")
  #           GDM_PROJ_LOCK_LINES+=("${lock_start_end_lines[@]}")
  # return: $GDM_ERRORS[malformed_config_file] if $config_was==invalid ; 1 if $config_was=="unknown error" ; else 0

  # local validate_version=false
  # local validate_script=false

  local errors=() # will accumulate errors and be output
  local init=false
  local traverse_parents=false
  local gdm_validateConf_flags=()

  for arg in $@ ; do 
    if   [[ "$arg" ==  --init ]] ; then init=true
    elif [[ "$arg" ==  --traverse-parents ]] ; then traverse_parents=true
    elif [[ "$arg" ==  --validate-version ]] ; then gdm_validateConf_flags+=("$arg")
    elif [[ "$arg" ==  --validate-sript ]] ;   then gdm_validateConf_flags+=("$arg")
    else 
      errors+=("Unexpected argument to gdm.validateConf: $arg") 
      gdm_echoVars --append-array errors
      return 1
    fi
  done
  shift $# # clear to prevent sourcing from forwarding arguments


  local sourced=false ; [[ "$GDM_CALL_EVAL_CONTEXT" == *':file' ]] && sourced=true

  local call_status="$($sourced && echo sourced || echo executed)" 
  local config_was="unexpected error" 
  local proj_conf=""
  local conf_call_line="" # currently unsused
  local proj_root=""
  
  for i in {1..$#GDM_CALL_FFTRACE} ; do
    if [[ "$GDM_CALL_FFTRACE[$i]" =~ "/$GDM_REQUIRE_CONF:[0-9]+$" ]] ; then
      proj_conf="${${GDM_CALL_FFTRACE[$i]%:*}:a}" 
      proj_root="$proj_conf:h"
      conf_call_line="${GDM_CALL_FFTRACE[$i]##*:}"
      if ((i==1)) ; then
            call_status="$call_status by conf"
      else  call_status="$call_status with conf found in stack" 
      fi
      break
    fi
  done
  
  if [[ -z "$proj_root" ]] ; then # Otherwise, deduce it by looking for conf...
    proj_root="$GDM_CALLER_WD" 
    if [[ -f "$proj_root/$GDM_REQUIRE_CONF" ]] ; then # ...in directly in $PWD ...
      proj_conf="$proj_root/$GDM_REQUIRE_CONF" 
      call_status="$call_status from shell at project root"

    elif $traverse_parents  ; then # ...look in $PWD/.. then $PWD/../.. etc.
    # else  # ...look in $PWD/.. then $PWD/../.. etc.
      proj_root="${proj_root:h}"
      while [[ "$proj_root" != / ]] && ! [[ -f "$proj_root/$GDM_REQUIRE_CONF" ]] ; do proj_root="${proj_root:h}" ;  done

      if [[ -f "$proj_root/$GDM_REQUIRE_CONF" ]] ; then 
        proj_conf="$proj_root/$GDM_REQUIRE_CONF"
        call_status="$call_status from shell at project subdir"
      else
        proj_root="$GDM_CALLER_WD" 
        call_status="$call_status from shell without project" # no conf found
      fi
    else
      proj_root="$GDM_CALLER_WD" 
      call_status="$call_status from shell without project" # no conf found
    fi
  fi

  local conf_file="${proj_conf//$GDM_CALLER_WD/.}" # for displaying to user in errors
  
  local ret_code=0
  if [[ "$call_status" == 'executed by conf' ]] || [[ "$call_status" == *' with conf found in stack' ]] ; then
    config_was=invalid 
    errors+=("GDM was not directly sourced by \"$conf_file\" (GDM was ${call_status//conf/\"$conf_file\"})")
    ret_code=$GDM_ERRORS[malformed_config_file]
    
  elif [[ "$call_status" == *' from shell without project' ]] ; then
    config_was=missing # okay: not an error: 'missing' signals to $GDM init

  elif [[ "$call_status" == 'sourced by conf' ]] || [[ "$call_status" == *' from shell at project '* ]] ; then
    config_was=found # okay for now but could be invalid so next step would be to validate it

  else # This can't possibly happen but just in case...
    config_was="unexpected error"
    errors+=("Unexpected Error in gdm.locateProject: unknown call_status")
    ret_code=1 # generic error
  fi

  if ((ret_code!=0)) ; then
    gdm_echoVars --append-array call_status config_was proj_root proj_conf errors
    return $ret_code
  fi
  

  local assignments call_err eval_err 

  if [[ "$config_was" == found ]] ; then
    assignments="$(gdm.validateConf $proj_conf $gdm_validateConf_flags)" ; call_err=$? # only possible assigment is to append errors
    eval "$assignments" ; eval_err=$?
    
    if ((eval_err)) ; then
      errors+="Unexpected Error in gdm.locateProject: eval of gdm.validateConf output resulted in error code $eval_err"
      gdm_echoVars --append-array call_status config_was proj_root proj_conf errors
      return $eval_err
    elif ((call_err)) ; then
      gdm_echoVars --append-array call_status config_was proj_root proj_conf errors
      return $call_err
    fi 
  elif [[ "$config_was" == missing ]] ; then
    if $init ; then
      config_was=created
      echo "$(gdm_conf_template)" > "$proj_root/$GDM_REQUIRE_CONF" 
      chmod +x "$proj_root/$GDM_REQUIRE_CONF" 
      proj_conf="$proj_root/$GDM_REQUIRE_CONF" 
      source "$proj_conf"
    else
      gdm_echoVars --append-array call_status config_was proj_root proj_conf errors 
      return $GDM_ERRORS[no_project_found]
    fi
  fi

  local config_startline config_endline lock_startline lock_endline
  assignments="$(gdm.locateConfSections $proj_conf)" ; call_err=$?
  eval "$assignments" ; eval_err=$?
  
  if ((eval_err)) ; then
    errors+=("Unexpected Error in gdm.locateProject: eval of gdm.locateConfSections output resulted in error code $eval_err")
    gdm_echoVars --append-array call_status config_was proj_root proj_conf errors config_startline config_endline lock_startline lock_endline
    return 1
  elif ((call_err)) ; then
    gdm_echoVars --append-array call_status config_was proj_root proj_conf errors config_startline config_endline lock_startline lock_endline
    return $call_err
  else
    [[ "$config_was" == found ]] && config_was=valid # why check? We don't set to valid if  "$config_was" == created since it's always valid
    gdm_echoVars --append-array call_status config_was proj_root proj_conf errors config_startline config_endline lock_startline lock_endline
    return 0
  fi
}

gdm.validateConf() {
  # gdm.validateConf checks proj_conf ($1) by sourcing it and checking if it does the following:
  #            export arrays: config config_lock ; export the variables: GDM GDM_VER.
  #        NOTE: gdm.validateConf DOES NOT validate the sequence of sections in GDM_REQUIRE_CONF
  # input:
  #       proj_conf          # (require as arg 1) location of existing GDM_REQUIRE_CONF
  #           (Additional optional flags (unorded by never $1) may be passed:)
  #       --validate-version  # fail if GDM_VER is not compatible with GDM_VERSION by beginning with GDM_VER_COMPAT 
  #                           # (requires that the latter two exports be assigned by this script prior to calling)
  #       --validate-script   # fail if GDM is is not equal to $GDM_SCRIPT 
  #                           # (requires that GDM_SCRIPT be exported by/assiged to this script's "$0" prior to calling)
  # output: eval-able assigments of (appending to in the case of the errors array):
  #         errors=(<plain strings>) # error messages normally to be displayed to user, 
  #                                      # accumulating all errors found before finaly failing if nonempty
  #              Possible errors (returning $GDM_ERRORS[malformed_config_file]):
  #                    "export <"GDM_VER"|"GDM> not found in \"$conf_file\""
  #                    "GDM_VER from \"$conf_file\" not compatible with '$GDM_VERSION' called ($GDM_SCRIPT)"
  #                    "GDM from \"$conf_file\" does not match location of GDM_SCRIPT called ($GDM_SCRIPT)"
  #                    "array <"config"|"config_lock"> not exported in \"$conf_file\""
  #              Possible errors (returning 1):
  #                    "Unexpected argument to gdm.validateConf: $arg"
  # return: $GDM_ERRORS[malformed_config_file] if any checks fail ; 1 if $config_was=="unknown error" ; else 0
  local proj_conf="$1" ;
  [[ -z "$proj_conf" ]] && { echo "$0 usage:\n $0 ./$GDM_REQUIRE_CONF" >&2 ; return 1 ; }
  local validate_version=false
  local validate_script=false
  shift
  local errors=() #output

  for arg in $@ ; do 
    if   [[ "$arg" ==  --validate-version ]] ; then validate_version=true
    elif [[ "$arg" ==  --validate-sript ]] ; then validate_script=true
    else 
      errors+=("Unexpected argument to gdm.validateConf: $arg") 
      gdm_echoVars --append-array errors
      return 1
    fi
  done
  shift $# # clear to prevent sourcing from forwarding arguments

  local backups=() # BEFORE SOURCING, WE BACKUP CURRENT DEFINITIONS
  for var (GDM_VER GDM config config_lock) ; do
    eval "(( \${+$var} ))" && { backups+=("$(typeset -p $var)") ; unset $var ; }
  done

  local conf_file="${proj_conf//$GDM_CALLER_WD/.}" # for displaying to user in errors

  # SOURCE AND...
  source "$proj_conf" >/dev/null 2>&1 # || errors+=("source \"$conf_file\" returned error $?")
  # ...LOOK FOR MORE ERRORS:

  if ! (( ${+GDM_VER} )) ||  [[ "${(t)GDM_VER}" != scalar-export ]] ; then
    errors+=("export GDM_VER (string) not found in \"$conf_file\"") 
  elif $validate_version && ! [[ "$GDM_VER" =~ "^$GDM_VER_COMPAT.*" ]] ; then 
    errors+=("GDM_VER from \"$conf_file\" not compatible with '$GDM_VERSION' called ($GDM_SCRIPT)")
  fi

  if ! (( ${+GDM} )) || [[ "${(t)GDM}" != scalar-export ]] ; then
    errors+=("export GDM (string) not found in \"$conf_file\"") 
  elif $validate_script && ! [[ "$GDM" == "$GDM_SCRIPT" ]] ; then 
    errors+=("GDM from \"$conf_file\" does not match location of GDM_SCRIPT called ($GDM_SCRIPT)")
  fi

  if ! (( ${+config} )) || [[ "${(t)config}" != array-export ]] ; then
    errors+=("export config (array) not found in \"$conf_file\"") 
  fi
  if ! (( ${+config_lock} )) || [[ "${(t)config_lock}" != array-export ]] ; then
    errors+=("export config (array) not found in \"$conf_file\"") 
  fi

  gdm_echoVars --append-array errors

  if (($#errors)) ; then 
    for backup in $backups ; do eval "$backup" ; done # RESTORE BACKUPS
    return $GDM_ERRORS[malformed_config_file]  ;
  else
    return 0
  fi
}

gdm.locateConfSections() {
  # gdm.locateConfSections finds the line numbers where the config and config_lock arrays are exported a project config
  #             file as well as verify that they, along with sourcing GDM, are done properly and in the correct order.
  # input:
  #         proj_conf                # (require as arg 1) location of existing GDM_REQUIRE_CONF
  # output: eval-able assigments of (appending to in the case of the errors array):
  #         config_startline         # line where config array is exported
  #         config_endline           # line where config array is closed
  #         lock_startline           # line where config_lock is exported 
  #         lock_endline             # line where config_lock array is closed
  #         errors=(<plain strings>) # error messages normally to be displayed to user, 
  #                                  # accumulating all errors found before finaly failing if nonempty
  #              Possible errors (returning $GDM_ERRORS[malformed_config_file]):
  #                    "config_lock array cannot be exported before config in \"$conf_file\" at line $line_num"
  #                    "config array cannot be exported after config_lock in \"$conf_file\" at line $line_num"
  #                    "config_lock array cannot be exported after sourcing GDM in \"$conf_file\" at line $line_num"
  #                    "GDM is not sourced and/or not forwarded arguments properly in \"$conf_file\" at line $line_num"
  #                    "GDM is called again in \"$conf_file\" at line $line_num"
  #                    "config array was not properly exported in \"$conf_file\""
  #                    "config_lock array was not properly exported in \"$conf_file\""
  #                    "GDM is not properly sourced in \"$conf_file\""
  # return: $GDM_ERRORS[malformed_config_file] if any checks fail ; 1 if $config_was=="unknown error" ; else 0
  local proj_conf="$1"

  local errors=() # output
  
  # gdm_funcRegex() { # be sure to double excape dots in function names!!
  #   if (($#)) && ! [[ "$1" =~ '^-{1,2}(end|END)$' ]] ; then
  #         echo '^[ ]{0,1}(function[ ]+)?'"$1"'[ ]*\([ ]*\)[ ]*{'
  #   else  echo '^[ ]{0,1}}([ ]+#.*)?[ ]*$'
  #   fi
  # }
  gdm_exportArrayRegex() {
    if (($#)) && ! [[ "$1" =~ '^-{1,2}(end|END)$' ]] ; then
          echo '^[ ]{0,1}export[ ]+'"$1"'=\('
    else  echo "\)[ ]*([^\"'])*\$"
    fi
  }

  local config_start_regex=("$(gdm_exportArrayRegex config)")        ; local config_startline config_endline 
  local lock_start_regex=("$(gdm_exportArrayRegex config_lock)") ; local lock_startline lock_endline 
  local array_end_regex=("$(gdm_exportArrayRegex --END)") 
  local call_GDM_regex=('(^[ ]*|&& |; |&& { )(source |. )?("\$GDM"|\$GDM)( "\$@"| "\${@}"| \$@| \${@})?') # call_GDM (including invalid)
  local source_GDM_regex='(source |. )("\$GDM"|\$GDM)( "\$@"| "\${@}"| \$@| \${@})'      # (validates line matching call_GDM_regex)

  local call_found=false ; local source_gdm_line=""

  local look_for=(config_start config_end lock_start lock_end source_GDM)
  for i in {1..$#look_for} ; eval "local ${look_for[$i]}=$i" # makes local vars named after array elem values with values that are their indexes
  local looking_for=1
  
  local conf_file="${proj_conf//$GDM_CALLER_WD/.}" # for displaying to user in errors
  local line_num=0 ;

  while IFS= read -r line  || [ -n "$line" ] ; do 
    ((++line_num))
    if   [[ "$line" =~ "$config_start_regex" ]] ; then
      if ((looking_for==config_start)) ; then  config_startline=$line_num ; ((++looking_for))
        if [[ "$line" =~ "$array_end_regex" ]] ; then config_endline=$line_num ; ((++looking_for)) ; fi
      elif ((looking_for>lock_start)) ; then 
        errors+=("config array cannot be exported after config_lock in \"$conf_file\" at line $line_num") 
      fi #else we allow some nested re-definition as odd (and not even detectable) as it may be
    elif [[ "$line" =~ "$lock_start_regex" ]] ; then 
      if ((looking_for==lock_start)) ; then  lock_startline=$line_num ; ((++looking_for))
        if [[ "$line" =~ "$array_end_regex" ]] ; then lock_endline=$line_num ; ((++looking_for)) ; fi
      elif ((looking_for<=config_end)) ; then
        errors+=("exported config_lock array cannot be defined before config in \"$conf_file\" at line $line_num") 
      elif ((looking_for>=call_GDM)) ; then
        errors+=("exported config_lock array cannot be defined after sourcing GDM in \"$conf_file\" at line $line_num") 
      fi #else we allow some nested re-definition as odd (and not even detectable) as it may be
    elif [[ "$line" =~ "$array_end_regex" ]] ; then
      if   ((looking_for==config_end)) ; then config_endline=$line_num  ; ((++looking_for))
      elif ((looking_for==lock_end)) ; then lock_endline=$line_num  ; ((++looking_for))
      fi 
      
    elif [[ "$line" =~ "$call_GDM_regex" ]] ; then
      if ((looking_for==source_GDM)) ; then
        if [[ "$line" =~ "$source_GDM_regex" ]] ; then source_gdm_line=$line_num ; ((++looking_for)) 
        else errors+=("GDM is not sourced and/or not forwarded arguments properly in \"$conf_file\" at line $line_num") 
        fi
      else errors+=("GDM is called in \"$conf_file\" at line $source_gdm_line then called again at line $line_num") 
      fi

    fi
  done <"$proj_conf"

  if   ((looking_for<=2)) ; then errors+=("config array was not properly exported in \"$conf_file\"")
  elif ((looking_for<=4)) ; then errors+=("config_lock array was not properly exported in \"$conf_file\"")
  elif ((looking_for<=5)) ; then errors+=("GDM is not properly sourced in \"$conf_file\"")
  fi


  gdm_echoVars --append-array config_startline config_endline lock_startline lock_endline errors
  if (($#errors)) ; then 
    return $GDM_ERRORS[malformed_config_file]  ;
  else return 0
  fi

}



gdm_assembleConfSection() {
  # local assembled_conf=( "$PROJ_CONFIG_A[@]" "$PROJ_CONFIG_B[@]" "$PROJ_CONFIG_C[@]" "$PROJ_CONFIG_D[@]" "$PROJ_CONFIG_E[@]")
  # print -l "$assembled_conf[@]" 
}

