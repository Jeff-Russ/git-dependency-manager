export GDM_SCRIPT="$0"
# export _GDM_TESTMODE="${GDM_TESTMODE:=false}"

export GDM_EVAL_CONTEXT="$ZSH_EVAL_CONTEXT" 
export GDM_INITAL_FFTRACE=("${funcfiletrace[@]}") 
export GDM_FTRACE=("${functrace[@]}") 

export GDM_CALLER_WD="$PWD"
export GDM_PROJ_ROOT=""
export GDM_PROJ_CONF=""


# (The function body is the lines between the lines specified below)
export GDM_REQUIRE_STARTLINE  # starting line number for function config in scanned GDM_PROJ_CONF
export GDM_REQUIRE_ENDLINE    #   ending line number for function config in scanned GDM_PROJ_CONF
export GDM_LOCK_STARTLINE  # starting line number for function config.lock in scanned GDM_PROJ_CONF
export GDM_LOCK_ENDLINE    #   ending line number for function config.lock in scanned GDM_PROJ_CONF
export GDM_CALL_STATUS=""


gdm.init() {
  # gdm.init initializes a new project by creating GDM_REQUIRE_CONF if it is not found (always at WD 
  #             if --traverse-parents is not provided) and, if project is found, validates the GDM_REQUIRE_CONF
  #             If GDM_REQUIRE_CONF is valid this function runs gdm_exportProjVars 
  # (for additional details, see commments for gdm_locateProject)

  local assignments call_err eval_err 
  assigments="$(gdm_locateProject $@)" ; call_err=$?

  export GDM_DEBUG="$assigments"

  local call_status conf_was proj_root proj_conf # all set in assigments
  local errors=() ; local config_startline config_endline lock_startline lock_endline  # more set in assigments
  eval "$assigments" ; eval_err=$?

  if ((eval_err)) ; then
    echo "$(_S R)Unexpected Error in gdm.init: eval of assigments resulted in error code $eval_err$(_S)" >&2
    return 1
  fi

  local display_proj_root="current working directory"
  ! [[ "$proj_root" == "$GDM_CALLER_WD" ]] && display_proj_root="${proj_root//$GDM_CALLER_WD/.}"
  
  if ((call_err)) ; then
    if ((call_err==$GDM_ERRORS[malformed_config_file])) ; then
      echo "$(_S R)Previous project was found at $display_proj_root with errors in ${proj_conf//$GDM_CALLER_WD/.}:$(_S Y D)" >&2
      print -l $errors >&2 ; echo -n "$(_S M D)" >&2
      echo "Possible fix: make a temporaray backup ${proj_conf//$GDM_CALLER_WD/.} by renaming it, create a" >&2
      echo "              new file with gdm.init and then copy your contents from the backup to the new file.$(_S)" >&2
    else
      echo "$(_S R)Unexpected Error in gdm.init: eval of assigments resulted in error code $eval_err$(_S Y D)" >&2
      print -l $errors >&2 ; echo -n "$(_S)" >&2
    fi
    return $call_err
  fi
  gdm_exportProjVars "$assigments" || return $?
  
  if  [[ "$conf_was" == 'created' ]] ; then
    echo "$(_S G)Project initialized at $display_proj_root, creating ${proj_conf//$GDM_CALLER_WD/.}$(_S)" 
  else # [[ "$conf_was" == 'valid' ]] ; then
    echo "$(_S G)Previous project was found at $display_proj_root via valid file: ${proj_conf//$GDM_CALLER_WD/.}$(_S)" 
  fi
  return 0
}

gdm_exportProjVars() {
  local assignments eval_err 
  assigments="$1"
  local proj_root proj_conf config_startline config_endline lock_startline lock_endline # from assigments
  eval "$assigments" ; eval_err=$?
  if ((eval_err)) ; then
    echo "Unexpected Error in gdm_exportProjVars: eval of assigments resulted in error code $eval_err"
    return 1
  fi
  GDM_PROJ_ROOT="$proj_root"
  GDM_PROJ_CONF="$proj_conf"
  GDM_REQUIRE_STARTLINE=$config_startline
  GDM_REQUIRE_ENDLINE=$config_endline
  GDM_LOCK_STARTLINE=$lock_startline
  GDM_LOCK_ENDLINE=$lock_endline 
  echo "$0 sees call_status=$call_status" >&2 #TEST
  GDM_CALL_STATUS="$call_status"
}
gdm_locateProject() { 
  # gdm_locateProject looks for a project based on how GDM was executed and creates a GDM_PROJ_CONF if not found.
  #          If a GDM_PROJ_CONF is found, gdm_locateProject validates it and returns an error if:
  #            1) $conf_was==invalid  which means the config file:
  #                                a) is found in the call stack but did not directly source GDM
  #                                b) did not define functions: config config.lock  or export the variables: GDM GDM_VER.
  #                                c) --validate-version was passed and the check failed (see below)
  #                                d) --validate-script  was passed and the check failed (see below)
  #                                e) defining config config.lock as well as sourcing GDM are not done properly or in the correct order.
  #            2) $conf_was=="unknown error" (unlikely, possibly impossible)
  #          If a GDM_PROJ_CONF is found and is valid, it parses the file, assigning exported variables (see 'side effects').
  # Prerequisites:
  #           GDM_REQUIRE_CONF, GDM_CALLER_WD, GDM_EVAL_CONTEXT, and GDM_INITAL_FFTRACE must be exported with valid values and 
  #           GDM_PROJ_ROOT, GDM_PROJ_REQUIRE_LINES, GDM_PROJ_LOCK_LINES must be exported (the latter two as empty arrays)
  # Input (all optional and non-positional)
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
  #       conf_was=created|valid|invalid|"unexpected error"
  #                                    # if conf_was missing, it will be created and thus conf_was is reassigned to created, which means valid
  #                                    # if conf_was found, it only stays as such until validation, which reassigs it to valid or invalid
  #                                    # "unexpected error" is an internal error (returning 1) which indicates a bug in GDM
  #       proj_root=<fullpath>|""      # non-empty if found (via conf found or conf_was==missing), whether valid or not
  #       proj_conf=<fullpath>|""      # non-empty if found, whether valid or not
  #       errors=(<plain strings>) # error messages normally to be displayed to user, 
  #                                    # accumulating all errors found before finaly failing if nonempty
  #              Possible errors (returning $GDM_ERRORS[malformed_config_file]):
  #                    "GDM was not directly sourced by \"$conf_file\" (GDM was ${call_status//conf/\"$conf_file\"})"
  #                    "export <"GDM_VER"|"GDM> not found in \"$conf_file\""
  #                    "GDM_VER from \"$conf_file\" not compatible with '$GDM_VERSION' called ($GDM_SCRIPT)"
  #                    "GDM from \"$conf_file\" does not match location of GDM_SCRIPT called ($GDM_SCRIPT)"
  #                    "function <"config"|"config.lock"> not defined in \"$conf_file\""
  #                    "function config.lock cannot be defined before config in \"$conf_file\" at line $line_num"
  #                    "function config cannot be defined after config.lock in \"$conf_file\" at line $line_num"
  #                    "function config.lock cannot be defined after sourcing GDM in \"$conf_file\" at line $line_num"
  #                    "GDM is not sourced and/or not forwarded arguments properly in \"$conf_file\" at line $line_num"
  #                    "GDM is called again in \"$conf_file\" at line $line_num"
  #                    "function config was not properly defined in \"$conf_file\""
  #                    "function config.lock was not properly defined in \"$conf_file\""
  #                    "GDM is not properly sourced in \"$conf_file\""
  #              Possible errors (returning 1):
  #                    "Unexpected Error in gdm_locateProject: unknown call_status"
  #                    "Unexpected Error in gdm_locateProject: eval of gdm_validateConf output resulted in error code $eval_err"
  #                    "Unexpected Error in gdm_locateProject: eval of gdm_locateConfSections output resulted in error code $eval_err"
  #                    "Unexpected argument to gdm_validateConf: $arg"
  #    Sometimes Output (always if non-failing):
  #         config_startline            # line where function config is declared (before body)
  #         config_endline              # line where function config is closed (after body)
  #         lock_startline              # line where function config.lock is declared (before body)
  #         lock_endline                # line where function config.lock is closed (after body)
  # side effects: 
  #       There are no side effects but that is due to the limitation that a subshell, which is how this function should be called
  #       cannot successfully reassign an exported variable. Therefore, non-failing (output with conf_was equaling 'created' or 'valid'
  #       should normally trigger assigment of:
  #           GDM_PROJ_ROOT="$proj_root"
  #           GDM_PROJ_CONF="$proj_conf"
  #           GDM_REQUIRE_STARTLINE=$config_startline
  #           GDM_REQUIRE_ENDLINE=$config_endline
  #           GDM_LOCK_STARTLINE=$lock_startline
  #           GDM_LOCK_ENDLINE=$lock_endline
  #       (OLD VERSION TODO: delete)
  #           GDM_PROJ_REQUIRE_LINES+=("${config_start_end_lines[@]}")
  #           GDM_PROJ_LOCK_LINES+=("${lock_start_end_lines[@]}")
  # return: $GDM_ERRORS[malformed_config_file] if $conf_was==invalid ; 1 if $conf_was=="unknown error" ; else 0

  # local validate_version=false
  # local validate_script=false

  local errors=() # will accumulate errors and be output

  local traverse_parents=false
  local gdm_validateConf_flags=()

  for arg in $@ ; do 
    if   [[ "$arg" ==  --traverse-parents ]] ; then traverse_parents=true
    elif [[ "$arg" ==  --validate-version ]] ; then gdm_validateConf_flags+=("$arg")
    elif [[ "$arg" ==  --validate-sript ]] ;   then gdm_validateConf_flags+=("$arg")
    else 
      errors+=("Unexpected argument to gdm_validateConf: $arg") 
      gdm_echoVars errors
      return 1
    fi
  done
  shift $# # clear to prevent sourcing from forwarding arguments


  local sourced=false ; [[ "$GDM_EVAL_CONTEXT" == *':file' ]] && sourced=true

  local call_status="$($sourced && echo sourced || echo executed)" 
  local conf_was="unexpected error" 
  local proj_conf=""
  local conf_call_line="" # currently unsused
  local proj_root=""
  
  for i in {1..$#GDM_INITAL_FFTRACE} ; do
    if [[ "$GDM_INITAL_FFTRACE[$i]" =~ "/$GDM_REQUIRE_CONF:[0-9]+$" ]] ; then
      proj_conf="${${GDM_INITAL_FFTRACE[$i]%:*}:a}" 
      proj_root="$proj_conf:h"
      conf_call_line="${GDM_INITAL_FFTRACE[$i]##*:}"
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
    conf_was=invalid 
    errors+=("GDM was not directly sourced by \"$conf_file\" (GDM was ${call_status//conf/\"$conf_file\"})")
    ret_code=$GDM_ERRORS[malformed_config_file]
    
  elif [[ "$call_status" == *' from shell without project' ]] ; then
    conf_was=missing # okay: not an error: 'missing' signals to $GDM init

  elif [[ "$call_status" == 'sourced by conf' ]] || [[ "$call_status" == *' from shell at project '* ]] ; then
    conf_was=found # okay for now but could be invalid so next step would be to validate it

  else # This can't possibly happen but just in case...
    conf_was="unexpected error"
    errors+=("Unexpected Error in gdm_locateProject: unknown call_status")
    ret_code=1 # generic error
  fi

  if ((ret_code!=0)) ; then
    gdm_echoVars call_status conf_was proj_root proj_conf errors 
    return $ret_code
  fi
  

  local assignments call_err eval_err 

  if [[ "$conf_was" == found ]] ; then
    assignments="$(gdm_validateConf $proj_conf $gdm_validateConf_flags)" ; call_err=$? # only possible assigment is to append errors
    eval "$assignments" ; eval_err=$?
    
    if ((eval_err)) ; then
      errors+="Unexpected Error in gdm_locateProject: eval of gdm_validateConf output resulted in error code $eval_err"
      gdm_echoVars call_status conf_was proj_root proj_conf errors
      return $eval_err
    elif ((call_err)) ; then
      gdm_echoVars call_status conf_was proj_root proj_conf errors
      return $call_err
    fi 
  elif [[ "$conf_was" == missing ]] ; then
    conf_was=created
    echo "$(gdm_conf_template)" > "$proj_root/$GDM_REQUIRE_CONF" 
    chmod +x "$proj_root/$GDM_REQUIRE_CONF" 
    proj_conf="$proj_root/$GDM_REQUIRE_CONF" 
  fi

  local config_startline config_endline lock_startline lock_endline
  assignments="$(gdm_locateConfSections $proj_conf)" ; call_err=$?
  eval "$assignments" ; eval_err=$?
  
  if ((eval_err)) ; then
    errors+=("Unexpected Error in gdm_locateProject: eval of gdm_locateConfSections output resulted in error code $eval_err")
    gdm_echoVars call_status conf_was proj_root proj_conf errors config_startline config_endline lock_startline lock_endline
    return 1
  elif ((call_err)) ; then
    gdm_echoVars call_status conf_was proj_root proj_conf errors config_startline config_endline lock_startline lock_endline 
    return $call_err
  else
    [[ "$conf_was" == found ]] && conf_was=valid # why check? We don't set to valid if  "$conf_was" == created since it's always valid
    gdm_echoVars call_status conf_was proj_root proj_conf errors config_startline config_endline lock_startline lock_endline
    return 0
  fi
}

gdm_validateConf() {
  # gdm_validateConf checks proj_conf ($1) by sourcing it and checking if it does the following:
  #            define functions: config config.lock ; export the variables: GDM GDM_VER.
  #        NOTE: gdm_validateConf DOES NOT validate the sequence of sections in GDM_REQUIRE_CONF
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
  #                    "function <"config"|"config.lock"> not defined in \"$conf_file\""
  #              Possible errors (returning 1):
  #                    "Unexpected argument to gdm_validateConf: $arg"
  # return: $GDM_ERRORS[malformed_config_file] if any checks fail ; 1 if $conf_was=="unknown error" ; else 0
  local proj_conf="$1" ; shift
  local validate_version=false
  local validate_script=false

  local errors=() #output

  for arg in $@ ; do 
    if   [[ "$arg" ==  --validate-version ]] ; then validate_version=true
    elif [[ "$arg" ==  --validate-sript ]] ; then validate_script=true
    else 
      errors+=("Unexpected argument to gdm_validateConf: $arg") 
      gdm_echoVars errors
      return 1
    fi
  done
  shift $# # clear to prevent sourcing from forwarding arguments

  local backups=() # BEFORE SOURCING, WE BACKUP CURRENT DEFINITIONS
  for var (GDM_VER GDM) ; do
    eval "(( \${+$var} ))" && { backups+=("export $var=\"${(P)var}\"") ; unset $var ; }
  done
  for func (config config.lock) ; do
    if typeset -f $func >/dev/null 2>&1 ; then
      local cap="" ; autoload +X "$func" # loads an autoload function without executing it
      cap="$(whence -cx 2 "$func" 2>/dev/null)" && { backups+=("$cap") ; unfunction $func ; }
    fi
  done

  local conf_file="${proj_conf//$GDM_CALLER_WD/.}" # for displaying to user in errors

  # SOURCE AND...
  source "$proj_conf" >/dev/null 2>&1 # || errors+=("source \"$conf_file\" returned error $?")
  # ...LOOK FOR MORE ERRORS:
  for var (GDM_VER GDM) ; do
    ! eval "(( \${+$var} ))" && errors+=("export $var not found in \"$conf_file\"") 
  done
  if $validate_version && (( ${+GDM_VER} )) && ! [[ "$GDM_VER" =~ "^$GDM_VER_COMPAT.*" ]] ; then 
    errors+=("GDM_VER from \"$conf_file\" not compatible with '$GDM_VERSION' called ($GDM_SCRIPT)")
  fi
  if $validate_script && (( ${+GDM} )) && ! [[ "$GDM" == "$GDM_SCRIPT" ]] ; then 
    errors+=("GDM from \"$conf_file\" does not match location of GDM_SCRIPT called ($GDM_SCRIPT)")
  fi

  ! typeset -f config >/dev/null 2>&1 && errors+=("function 'config' not defined in \"$conf_file\"")
  ! typeset -f config.lock >/dev/null 2>&1 && errors+=("function 'config.lock' not defined in \"$conf_file\"")


  gdm_echoVars errors 

  if (($#errors)) ; then 
    for backup in $backups ; do eval "$backup" ; done # RESTORE BACKUPS
    return $GDM_ERRORS[malformed_config_file]  ;
  else
    return 0
  fi
}

gdm_locateConfSections() {
  # gdm_locateConfSections finds the line numbers where the config and config.lock functions are defined a project config
  #             file as well as verify that they, along with sourcing GDM, are done properly and in the correct order.
  # input:
  #         proj_conf                # (require as arg 1) location of existing GDM_REQUIRE_CONF
  # output: eval-able assigments of (appending to in the case of the errors array):
  #         config_startline         # line where function config is declared (before body)
  #         config_endline           # line where function config is closed (after body)
  #         lock_startline           # line where function config.lock is declared (before body)
  #         lock_endline             # line where function config.lock is closed (after body)
  #         errors=(<plain strings>) # error messages normally to be displayed to user, 
  #                                  # accumulating all errors found before finaly failing if nonempty
  #              Possible errors (returning $GDM_ERRORS[malformed_config_file]):
  #                    "function config.lock cannot be defined before config in \"$conf_file\" at line $line_num"
  #                    "function config cannot be defined after config.lock in \"$conf_file\" at line $line_num"
  #                    "function config.lock cannot be defined after sourcing GDM in \"$conf_file\" at line $line_num"
  #                    "GDM is not sourced and/or not forwarded arguments properly in \"$conf_file\" at line $line_num"
  #                    "GDM is called again in \"$conf_file\" at line $line_num"
  #                    "function config was not properly defined in \"$conf_file\""
  #                    "function config.lock was not properly defined in \"$conf_file\""
  #                    "GDM is not properly sourced in \"$conf_file\""
  # return: $GDM_ERRORS[malformed_config_file] if any checks fail ; 1 if $conf_was=="unknown error" ; else 0
  local proj_conf="$1"

  local errors=() # output
  
  gdm_funcRegex() { # be sure to double excape dots in function names!!
    if (($#)) && ! [[ "$1" =~ '^-{1,2}(end|END)$' ]] ; then
          echo '^[ ]{0,1}(function[ ]+)?'"$1"'[ ]*\([ ]*\)[ ]*{'
    else  echo '^[ ]{0,1}}([ ]+#.*)?[ ]*$'
    fi
  }
  local config_start_regex=("$(gdm_funcRegex config)")        ; local config_startline config_endline 
  local lock_start_regex=("$(gdm_funcRegex config\\.lock)") ; local lock_startline lock_endline 
  local func_end_regex=("$(gdm_funcRegex --END)")            ; local current_func=""
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
      elif ((looking_for>lock_start)) ; then 
        errors+=("function config cannot be defined after config.lock in \"$conf_file\" at line $line_num") 
      fi #else we allow some nested re-definition as odd (and not even detectable) as it may be
    elif [[ "$line" =~ "$lock_start_regex" ]] ; then 
      if ((looking_for==lock_start)) ; then  lock_startline=$line_num ; ((++looking_for))
      elif ((looking_for<=config_end)) ; then
        errors+=("function config.lock cannot be defined before config in \"$conf_file\" at line $line_num") 
      elif ((looking_for>=call_GDM)) ; then
        errors+=("function config.lock cannot be defined after sourcing GDM in \"$conf_file\" at line $line_num") 
      fi #else we allow some nested re-definition as odd (and not even detectable) as it may be
    elif [[ "$line" =~ "$func_end_regex" ]] ; then
      if   ((looking_for==config_end)) ; then config_endline=$line_num  ; ((++looking_for))
      elif ((looking_for==lock_end)) ; then lock_endline=$line_num  ; ((++looking_for))
      fi 
      
    elif [[ "$line" =~ "$call_GDM_regex" ]] ; then
      if ((looking_for==source_GDM)) ; then
        if [[ "$line" =~ "$source_GDM_regex" ]] ; then  source_gdm_line=$line_num ; ((++looking_for)) 
        else errors+=("GDM is not sourced and/or not forwarded arguments properly in \"$conf_file\" at line $line_num") 
        fi
      else errors+=("GDM is called again in \"$conf_file\" at line $line_num") 
      fi

    fi
  done <"$proj_conf"

  if   ((looking_for<=2)) ; then errors+=("function config was not properly defined in \"$conf_file\"")
  elif ((looking_for<=4)) ; then errors+=("function config.lock was not properly defined in \"$conf_file\"")
  elif ((looking_for<=5)) ; then errors+=("GDM is not properly sourced in \"$conf_file\"")
  fi


  

  gdm_echoVars config_startline config_endline lock_startline lock_endline errors 
  if (($#errors)) ; then 
    return $GDM_ERRORS[malformed_config_file]  ;
  else return 0
  fi

}

gdm_conf_template() { gdm_conf_header ; gdm_conf_body ; gdm_conf_footer ; }

gdm_conf_header() {
cat << CONFDOC
#!/usr/bin/env zsh

export GDM_REGISTRY="\$HOME/.gdm_registry"
export GDM_VER='$GDM_VERSION'
export GDM="\$GDM_REGISTRY/gdm-\$GDM_VER.zsh"

CONFDOC
}
gdm_conf_body() {
cat << CONFDOC
# Add any setup functions here

config() {
  # Example:
  # gdm require juce-framework/JUCE#develop as=juce-dev setup='rm -rf .git'
} 

CONFDOC
}
gdm_conf_footer() {
cat << CONFDOC
# DO NOT MODIFY THIS LINE OR BELOW

if ! [[ -f "$GDM" ]] ; then
  mkdir -p "\$GDM:h" && curl "https://raw.githubusercontent.com/Jeff-Russ/git-dependency-manager/main/dist/\$GDM:t" > "\$GDM" ;
fi

config.lock() {

}

((\$#)) && source "\$GDM" "\$@" 

CONFDOC
}

gdm_assembleConfSection() {
  # local assembled_conf=( "$GDM_PROJ_CONF_A[@]" "$GDM_PROJ_CONF_B[@]" "$GDM_PROJ_CONF_C[@]" "$GDM_PROJ_CONF_D[@]" "$GDM_PROJ_CONF_E[@]")
  # print -l "$assembled_conf[@]" 
}


gdm "$@" #TEST ?