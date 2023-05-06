export GDM_CALL_EVAL_CONTEXT="$ZSH_EVAL_CONTEXT" 
export GDM_CALL_FFTRACE=("${funcfiletrace[@]}") 
export GDM_CALLER_WD="$PWD"
export GDM_CALL_ARGS=() # Will be set in gdm() BEFORE anything here is called. Includes operation arg

export GDM_PROJ_VARS="" # archive of local var assignments used to assign each other GDM_PROJ_* var
export GDM_PROJ_CALL_STATUS=""
export GDM_PROJ_ROOT=""        # full absolute path of project root directory
export GDM_PROJ_CONF_FILE="" # full absolute file path
export GDM_PROJ_CONF_WAS=""  # created|valid|invalid|"unexpected error" or 'missing' but not for long if --init

export GDM_PROJ_CONF_FILE_SECTIONS=(  # contents of file in chunks where replaceable portion (conf and conf_lock arrays) are chunks
  '' # [1] (readonly) is all lines before conf array
  '' # [2] (REPLACABLE) is all lines where conf array is declared+defined
  '' # [3] (readonly) is all lines after conf array and before conf_lock
  '' # [4] (REPLACABLE) is all lines where conf_lock array is declared+defined
  '' # [5] (readonly) is all remaining lines
) 

export GDM_PROJ_CONFIG_ARRAY=()
export GDM_PROJ_LOCK_ARRAY=()
export GDM_PROJ_CONFIG_IDX=0 # should be incremented as index of both GDM_PROJ_CONFIG_ARRAY and GDM_PROJ_LOCK_ARRAY (at once)
#NOTE GDM_CALL_ARGS (as a string) is basically GDM_PROJ_CONFIG_ARRAY[$GDM_PROJ_CONFIG_IDX] when GDM_PROJ_CONFIG_IDX==0

export GDM_PROJ_CONFIG_I_TO_LOCK_I=() # Each index is a GDM_PROJ_CONFIG_ARRAY index and each value is:
# 1) the corresponding index in GDM_PROJ_LOCK_ARRAY with the same `destin` value
#   but it could also be:
# 2) the `destin` value if there is no corresponding index in GDM_PROJ_LOCK_ARRAY with the same `destin` value
# 3) a key in GDM_ERRORS (*_destination_arg, destination_already_required_to), indicating the conf requirement has an error.
# NOTE that the absence of an error doesn't mean there won't be one found later when the requirement is passed to gdm.require.

export GDM_PROJ_DROP_LOCK_I=() # values are indices in GDM_PROJ_LOCK_ARRAY with `destin` values not targeted by 
# any requirement in config (GDM_PROJ_CONFIG_ARRAY). Note that the indexes in GDM_PROJ_DROP_LOCK_I is unimportant. 
# GDM_PROJ_DROP_LOCK_I is basically a list of the elements no longer needed in conf_lock since they are not longer required.

export GDM_PROJ_OVERRIDE_CONFIG_I=()  #TODO: (implement this) If non-empty, stores the GDM_PROJ_LOCK_ARRAY indices that GDM_CALL_ARGS is modifying. 
                                      #TODO: This is an array because we'll have operations like `unrequire` that work many.

export GDM_PROJ_LOCKED_CONFIG_I=()  #TODO: (implement this)  If non-empty, stores the GDM_PROJ_LOCK_ARRAY indices that should resolve to the
                                    #  hash in the corresponding GDM_PROJ_LOCK_ARRAY (to be looked up with GDM_PROJ_CONFIG_I_TO_LOCK_I)
                                    # because the original requirement referred to a revision that may resolve to a different 
                                    # hash depending on time of requiring, which was previously locked in by config_lock. 
                                    # These should be verified against the locked hash and, if missing, installed by the lock hash.


gdm.init() {
  # gdm.init initializes a new project by creating GDM_REQUIRE_CONF if it is not found (always at WD)
  #             if --traverse-parents is not provided) and, if project is found, validates the GDM_REQUIRE_CONF
  #             If GDM_REQUIRE_CONF is valid this function runs gdm_exportFromProjVars 
  # IMPORTANT: do not execute gdm.init in a subshell as would be the case when capturing output. Exports would fail!
  # (for additional details, see commments for gdm_locateProject)
  gdm.project --init $@ #-> gdm.init calls gdm.project
  return $?
}

# 71 lines:
gdm.project() {
  # gdm.project main usage for users is: gdm.project init
  #          Whether called with (--)?init or not, if gdm.project successfully finds a valid project, 
  #          establishes the caller project details by assigning exported variables pertaining to it
  #          by calling gdm_exportFromProjVars (see gdm_exportFromProjVars  for details).
  #          When (--)?init is passed (as 1st arg only) to gdm.project, as is done when called  by gdm.init,
  #             it will initialize a  new project by creating GDM_REQUIRE_CONF if it is not found (always at WD 
  #             if (--)?traverse(-parents)? is not provided) 
  #           But can  also be called elsewhere without --init to skip creating of a new GDM_REQUIRE_CONF
  #             and just perform the part that establishes the caller project details via calling gdm_exportFromProjVars
  # IMPORTANT: do not execute gdm.project in a subshell as would be the case when capturing output. Exports would fail!
  # PRECONDITIONS: GDM_CALL_EVAL_CONTEXT GDM_CALL_FFTRACE and GDM_CALLER_WD must be set each time GDM or any function therein
  # is called by user: stale values cause big problems!
  # (for additional details, see commments for gdm_locateProject)
  local assignments call_err eval_err 

  echo "$(_S M)$0$(_S)" #TEST
  # echo "$(_S G)HERE$(_S)" #TEST

  assigments="$(gdm_locateProject $@)" ; call_err=$? #-> gdm.project calls gdm_locateProject
  # NOTE: locateProject will return $GDM_ERRORS[no_project_found] if "$config_was"=='missing' 
  # all locals below are set in or appended in assigments:
  local call_status config_was proj_root proj_conf 
  local errors=() ; local config_startline config_endline lock_startline lock_endline 
  eval "$assigments" ; eval_err=$?

  # echo "gdm_locateProject returned $call_err ($(gdm.error $call_err))" #TEST

  if ((eval_err)) ; then
    echo "$(_S R)Unexpected Error: eval of assigments from gdm_locateProject resulted in error code $eval_err$(_S)" >&2
    return 1
  fi
  
  local display_proj_root="current working directory"
  ! [[ "$proj_root" == "$GDM_CALLER_WD" ]] && display_proj_root="${proj_root//$GDM_CALLER_WD/.}"
  
  local prev_project="Project" ; [[ "$1" =~ '^[-]{0,2}init(ialize)?$' ]] && prev_project="Previous project" # for output

  if ((call_err)) ; then
    if ((call_err==$GDM_ERRORS[malformed_config_file])) ; then
      echo "$(_S R)$prev_project project was found at $display_proj_root with errors in ${proj_conf//$GDM_CALLER_WD/.}:$(_S Y D)" >&2
      print -l $errors >&2 ; echo -n "$(_S M D)" >&2
      echo "Possible fix: make a temporaray backup ${proj_conf//$GDM_CALLER_WD/.} by renaming it, create a" >&2
      echo "              new file with \`\$GDM init\` and then copy your contents from the backup to the new file.$(_S)" >&2
    elif ((call_err==$GDM_ERRORS[no_project_found])) ; then
      errors+=("No project was found! Run \`\$GDM init\` to create one.")
      echo "$(_S Y)No project was found! $(_S) Run \`\$GDM init\` to create one." >&2 
    else
      echo "$(_S R)Unexpected Error: gdm_locateProject returned error code $call_err$(_S Y D)" >&2
      print -l $errors >&2 ; echo -n "$(_S)" >&2
    fi
  fi
  # Set (exported) archive of archive of (local) vars for debugging/informational purposes
  GDM_PROJ_VARS="$(gdm_echoVars --local call_status proj_root proj_conf config_was config_startline config_endline lock_startline lock_endline errors)"

  ((call_err)) && return $call_err

  ##### PPROJECT IS VALID SO EXPORT PROJECT VARABLESS #############################################
  GDM_PROJ_CALL_STATUS="$call_status"
  GDM_PROJ_ROOT="$proj_root"
  GDM_PROJ_CONF_FILE="$proj_conf"
  GDM_PROJ_CONF_WAS="$config_was"
  shift $# # clear to prevent sourcing from forwarding arguments
  source "$GDM_PROJ_CONF_FILE"
  GDM_PROJ_CONFIG_ARRAY=("${config[@]}")
  GDM_PROJ_LOCK_ARRAY=("${config_lock[@]}")


  gdm.parseConfig

  local line_num=0 ;
  while IFS= read -r line  || [ -n "$line" ] ; do 
    ((++line_num))
    if   ((line_num<config_startline)) ; then GDM_PROJ_CONF_FILE_SECTIONS[1]="$GDM_PROJ_CONF_FILE_SECTIONS[1]${line}\n" 
    elif ((line_num<=config_endline)) ; then GDM_PROJ_CONF_FILE_SECTIONS[2]="$GDM_PROJ_CONF_FILE_SECTIONS[2]${line}\n" # conf
    elif ((line_num<lock_startline)) ; then GDM_PROJ_CONF_FILE_SECTIONS[3]="$GDM_PROJ_CONF_FILE_SECTIONS[3]${line}\n"
    elif ((line_num<=lock_endline)) ; then GDM_PROJ_CONF_FILE_SECTIONS[4]="$GDM_PROJ_CONF_FILE_SECTIONS[4]${line}\n" # conf_lock
    else                                  GDM_PROJ_CONF_FILE_SECTIONS[5]="$GDM_PROJ_CONF_FILE_SECTIONS[5]${line}\n"
    fi
  done <"$GDM_PROJ_CONF_FILE"



  if [[ "$config_was" == 'created' ]] ; then
    echo "$(_S G)Project initialized at $display_proj_root, creating ${proj_conf//$GDM_CALLER_WD/.}$(_S)" 
  else # [[ "$config_was" == 'valid' ]] ; then
    echo "$(_S G)$prev_project was found at $display_proj_root via valid file: ${proj_conf//$GDM_CALLER_WD/.}$(_S)" 
  fi

  return 0
}


gdm_locateProject() { 
  # gdm_locateProject looks for a project based on how GDM was executed and, 
  #                   if GDM_PROJ_CONF_FILE if not found and --init is passed, creates it.
  #          If a GDM_PROJ_CONF_FILE is found, gdm_locateProject validates it and returns an error if:
  #            1) $config_was==invalid  which means the config file:
  #                                a) is found in the call stack but did not directly source GDM
  #                                b) did not export arrays: config config_lock  or export the strings: GDM GDM_VER.
  #                                c) --validate-version was passed and the check failed (see below)
  #                                d) --validate-script  was passed and the check failed (see below)
  #                                e) exporting config config_lock as well as sourcing GDM are not done properly or in the correct order.
  #            2) $config_was=="unknown error" (unlikely, possibly impossible)
  #          If a GDM_PROJ_CONF_FILE is found and is valid, it parses the file, assigning exported variables (see 'side effects').
  # Prerequisites (below doesn't list exports always required):
  #      must be exported with valid values:
  #           GDM_REQUIRE_CONF, GDM_CALLER_WD. GDM_CALL_EVAL_CONTEXT, GDM_CALL_FFTRACE
  #      must be exported (the last two as empty arrays):
  #           GDM_PROJ_ROOT, GDM_PROJ_REQUIRE_LINES, GDM_PROJ_LOCK_LINES 
  # Input (all optional and non-positional)
  #       --init              # if GDM_PROJ_CONF_FILE is missing, create it.
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
  #              returning $GDM_ERRORS[invalid_GDM_REQUIRED_path] (does not happen experimental mode is enabled)
  #                   errors+=("GDM_REQUIRED=$GDM_REQUIRED is not within GDM_PROJ_ROOT=$proj_root ($reqdir_relto_proj)")
  #              returning $GDM_ERRORS[malformed_config_file] 
  #                   errors+=("GDM was not directly sourced by \"$conf_file\" (GDM was ${call_status//conf/\"$conf_file\"})")
  #              returning 1 (Unexpected errors):
  #                   errors+=("Unexpected argument to $0: $arg")
  #                   errors+=("Unexpected Error in gdm_locateProject: unknown call_status")
  #                   errors+=("Unexpected Error in gdm_locateProject: eval of gdm_validateConf output resulted in error code $eval_err")
  #                   errors+=("Unexpected Error in gdm_locateProject: eval of gdm_locateConfSections output resulted in error code $eval_err")
  #              returning  $call_err from gdm_locateConfSections
  #                   see comments on error codes and error messages for gdm_locateConfSections
  #    Sometimes Output (always if non-failing): 
  #         config_startline            # line where config array is exported
  #         config_endline              # line where config array is closed
  #         lock_startline              # line where exported config_lock array is declared
  #         lock_endline                # line where exported config_lock array is closed
  # side effects: 
  #       There are no side effects but that is due to the limitation that a subshell, which is how this function should be called
  #       cannot successfully reassign an exported variable. Therefore, non-failing (output with config_was equaling 'created' or 'valid'
  #       should normally trigger assigment of:
  #           GDM_PROJ_ROOT="$proj_root"
  #           GDM_PROJ_CONF_FILE="$proj_conf"
  #           GDM_PROJ_CONFIG_STARTLINE=$config_startline
  #           GDM_PROJ_CONFIG_ENDLINE=$config_endline
  #           GDM_PROJ_LOCK_STARTLINE=$lock_startline
  #           GDM_PROJ_LOCK_ENDLINE=$lock_endline
  # returns $GDM_ERRORS[malformed_config_file] if $config_was==invalid ; 1 if $config_was=="unknown error" ; else 0

  # local validate_version=false
  # local validate_script=false

  local errors=() # will accumulate errors and be output

  ##### PARSE FLAG ARGUMENTS ######################################################################
  local init=false
  local traverse_parents=false
  local gdm_validateConf_flags=()
  for arg in $@ ; do 
    if   [[ "$arg" =~ '^[-]{0,2}init$' ]] ; then init=true
    elif [[ "$arg" =~ '^[-]{0,2}traverse(-parents)?$' ]] ; then traverse_parents=true
    elif [[ "$arg" =~ '^[-]{0,2}validate-ver(sion)?$' ]] ; then gdm_validateConf_flags+=("$arg")
    elif [[ "$arg" =~ '^[-]{0,2}validate-script$' ]] ; then gdm_validateConf_flags+=("$arg")
    else 
      errors+=("Unexpected argument to $0: $arg") 
      gdm_echoVars --append-array errors
      return 1
    fi
  done
  shift $# # clear to prevent sourcing from forwarding arguments

  ##### FIND proj_root proj_conf BY DETERMINING call_status  ######################################
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
  

  ##### ENFORCE VALID GDM_REQUIRED VALUE ##########################################################
  if  ! (($GDM_EXPERIMENTAL[(Ie)any_required_path])) ; then # If experimental mode disabled....
    # ERROR IF GDM_REQUIRED IS NOT WITHIN proj_root
    local reqdir_relto_proj="$(gdm_dirA_relto_B $proj_root/$GDM_REQUIRED $proj_root GDM_REQUIRED GDM_PROJ_ROOT)" 
    # possible values:  *" is contained by "*   *" contains "*   *" is "*   *" has no relation to "*  (first * is GDM_REQUIRED) 
    if [[ "$reqdir_relto_proj" != "GDM_REQUIRED is contained by GDM_PROJ_ROOT" ]] ; then 
      conf_was="" # remove default value "unexpected error" as we are returning before having properly set conf_was
      errors+=("GDM_REQUIRED=$GDM_REQUIRED is not within GDM_PROJ_ROOT=$proj_root ($reqdir_relto_proj)")
      gdm_echoVars --append-array call_status config_was proj_root proj_conf errors
      return $GDM_ERRORS[invalid_GDM_REQUIRED_path]
    fi
  fi

  ##### SET config_was AND ECHO ERROR AND RETURN IF CONF DIDN'T SOURCE GDM  #######################
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
    errors+=("Unexpected Error in gdm_locateProject: unknown call_status")
    ret_code=1 # generic error
  fi
  if ((ret_code!=0)) ; then
    gdm_echoVars --append-array call_status config_was proj_root proj_conf errors
    return $ret_code
  fi
  local assignments call_err eval_err 
  if [[ "$config_was" == found ]] ; then
    assignments="$(gdm_validateConf $proj_conf $gdm_validateConf_flags)" ; call_err=$? #-> gdm_locateProject calls gdm_validateConf
    # NOTE: only possible assigment is to append errors
    eval "$assignments" ; eval_err=$?
    if ((eval_err)) ; then
      errors+=("Unexpected Error in gdm_locateProject: eval of gdm_validateConf output resulted in error code $eval_err")
      gdm_echoVars --append-array call_status config_was proj_root proj_conf errors
      return 1
    elif ((call_err)) ; then
      gdm_echoVars --append-array call_status config_was proj_root proj_conf errors
      return $call_err
    fi 
  elif [[ "$config_was" == missing ]] ; then
    if $init ; then
      config_was=created
      echo "$(gdm_conf_template)" > "$proj_root/$GDM_REQUIRE_CONF"  #-> gdm_locateProject calls gdm_conf_template
      chmod +x "$proj_root/$GDM_REQUIRE_CONF" 
      proj_conf="$proj_root/$GDM_REQUIRE_CONF" 
      source "$proj_conf"
    else
      gdm_echoVars --append-array call_status config_was proj_root proj_conf errors 
      return $GDM_ERRORS[no_project_found]
    fi
  fi

  ##### RUN gdm_locateConfSections AND POSSIBLY ECHO ERRORS BEFORE RETURN #########################
  local config_startline config_endline lock_startline lock_endline
  assignments="$(gdm_locateConfSections $proj_conf)" ; call_err=$?  #-> gdm_locateProject calls gdm_locateConfSections
  eval "$assignments" ; eval_err=$?
  if ((eval_err)) ; then
    errors+=("Unexpected Error in gdm_locateProject: eval of gdm_locateConfSections output resulted in error code $eval_err")
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


gdm_validateConf() {
  # gdm_validateConf checks proj_conf ($1) by sourcing it and checking if it does the following:
  #            export arrays: config config_lock ; export the variables: GDM GDM_VER.
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
  #              returning $GDM_ERRORS[malformed_config_file]
  #                    errors+=("export GDM_VER (string) not found in \"$conf_file\"") 
  #                    errors+=("GDM_VER from \"$conf_file\" not compatible with '$GDM_VERSION' called ($GDM_SCRIPT)")
  #                    errors+=("export GDM (string) not found in \"$conf_file\"") 
  #                    errors+=("GDM from \"$conf_file\" does not match location of GDM_SCRIPT called ($GDM_SCRIPT)")
  #                    errors+=("export config (array) not found in \"$conf_file\"")
  #              returning 1 (Unexpected errors):
  #                    errors+=("Unexpected argument to gdm_validateConf: $arg") 
  # return: $GDM_ERRORS[malformed_config_file] if any checks fail ; 1 if $config_was=="unknown error" ; else 0
  local proj_conf="$1" ;
  [[ -z "$proj_conf" ]] && { echo "$0 usage:\n $0 ./$GDM_REQUIRE_CONF" >&2 ; return 1 ; }
  local validate_version=false
  local validate_script=false
  shift
  local errors=() #output

  for arg in $@ ; do 
    if   [[ "$arg" =~ '^[-]{0,2}validate-version$' ]] ; then validate_version=true
    elif [[ "$arg" =~ '^[-]{0,2}validate-script$' ]] ; then validate_script=true
    else 
      errors+=("Unexpected argument to gdm_validateConf: $arg") 
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


gdm_locateConfSections() {
  # gdm_locateConfSections finds the line numbers where the config and config_lock arrays are exported a project config
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
  #              Possible errors (cumulative, all returning $GDM_ERRORS[malformed_config_file]):
  #                    errors+=("config array cannot be exported after config_lock in \"$conf_file\" at line $line_num") 
  #                    errors+=("exported config_lock array cannot be defined before config in \"$conf_file\" at line $line_num")
  #                    errors+=("exported config_lock array cannot be defined after sourcing GDM in \"$conf_file\" at line $line_num") 
  #                    errors+=("GDM is not sourced and/or not forwarded arguments properly in \"$conf_file\" at line $line_num")
  #                    errors+=("GDM is called in \"$conf_file\" at line $source_gdm_line then called again at line $line_num") 
  #                    errors+=("config array was not properly exported in \"$conf_file\"")
  #                    errors+=("config_lock array was not properly exported in \"$conf_file\"")
  #                    errors+=("GDM is not properly sourced in \"$conf_file\"")
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

gdm.parseConfig() {
  # Constructs GDM_PROJ_CONFIG_I_TO_LOCK_I (and GDM_PROJ_DROP_LOCK_I)

  GDM_PROJ_CONFIG_I_TO_LOCK_I=()
  GDM_PROJ_DROP_LOCK_I=()      #TODO: (implement this) 
  GDM_PROJ_LOCKED_CONFIG_I=()  #TODO: (implement this) 

  local destin required_path # ...but we only really need `destin`
  local repo_identifier

  for conf_i in {1..$#GDM_PROJ_CONFIG_ARRAY} ; do
    # test with req='juce-framework/JUCE#develop destin=juce-dev setup="rm -rf .git"' ; eval "local args=($req)"
    eval "local args=( $GDM_PROJ_CONFIG_ARRAY[$conf_i] )"

    # TODO: redo with a function call: maybe even a call to parseRequirement, which we can give some shorter execution
    #--- Find `destin` value --------------------------------------------------------------------------
    repo_identifier="$args[1]" ; 
    args=("${(@)args:1}") # remove first arg
    for arg in $args[@] ; do
      if ! destin_assignments="$(gdm_parseIfDesinationOption $arg 2>/dev/null )" ; then
        GDM_PROJ_CONFIG_I_TO_LOCK_I[$conf_i]="invalid_destination_arg"
      elif ! [[ -z "$destin_assignments" ]] ; then
        if ! [[ -z "$required_path" ]] ; then
          GDM_PROJ_CONFIG_I_TO_LOCK_I[$conf_i]="multiple_destination_args"
        else
          eval "$destin_assignments"
          if (($GDM_PROJ_CONFIG_I_TO_LOCK_I[(Ie)$destin])) ; then
            GDM_PROJ_CONFIG_I_TO_LOCK_I[$conf_i]="destination_already_required_to"
          else
            GDM_PROJ_CONFIG_I_TO_LOCK_I[$conf_i]="$destin"
          fi
        fi
        break
      fi
    done
    # Default `destin` value (use same capitalization used by user in specifying repository):
    [[ -z "$GDM_PROJ_CONFIG_I_TO_LOCK_I[$conf_i]" ]] && GDM_PROJ_CONFIG_I_TO_LOCK_I[$conf_i]="${${repo_identifier%#*}:t:r}" 
  done

  #TODO we no longer have GDM_CONFIG_LOCKVARS, now it's GDM_CONFIG_LOCK_KEYS
  # # avoid re-declaring any local (since that seems to cause output in zsh):
  # for var_name in $GDM_CONFIG_LOCKVARS ; do ! [[ -v $var_name ]] && local $var_name ; done
  # local conf_i

  # for lock_i in {1..$#GDM_PROJ_LOCK_ARRAY} ; do    
  #   eval "$GDM_PROJ_LOCK_ARRAY[$lock_i]" # sets `destin` since `destin` is in $GDM_CONFIG_LOCKVARS
  #   conf_i=$(($GDM_PROJ_CONFIG_I_TO_LOCK_I[(Ie)$destin])) # index of $destin in conf, or 0 if not found
  #   if ((conf_i!=0)) ; then GDM_PROJ_CONFIG_I_TO_LOCK_I[$conf_i]=$lock_i
  #   else GDM_PROJ_DROP_LOCK_I+=($lock_i)
  #   fi
  # done
}

# for debugging:
gdm.echoProjVars() {
  typeset -m 'GDM_CALL*'
  typeset -m 'GDM_PROJ*'
  # echo $GDM_PROJ_VARS
}


gdm.update_conf() {
  local proj_conf="$1" ; [[ -z "$proj_conf" ]] && proj_conf="$GDM_PROJ_CONF_FILE"
  if [[ -z "$proj_conf" ]] ; then # shouldn't ever actually happen
    echo "$(_S R)Cannot write to project configuration file as it's path is not found!" >&2 
    return $GDM_ERRORS[unexpected_error]
  fi
  $0.write_array() { # needs outer scope's $proj_conf
    local array_name="$1" ; shift
    echo "export $array_name=(" >> "$proj_conf"
    for elem in $@ ; do
      local has_single=false ; [[ "$elem" =~ "(^'|[^\\]')" ]] && has_single=true
      local has_double=false ; [[ "$elem" =~ '(^"|[^\\]")' ]] && has_double=true

      if $has_single && ! $has_double ; then
        echo "  \"$elem\"" >> "$proj_conf"
      else
        echo "  '$elem'" >> "$proj_conf"
        if $has_single && $has_double ; then
          echo "$(_S Y)WARNING: The following array element written to $proj_conf has both unescaped single and double quotes and may need correction:$(_S)\n '$elem'" >&2 
        fi
      fi
    done
    echo ")" >> "$proj_conf"
  }
  echo "${GDM_PROJ_CONF_FILE_SECTIONS[1]}" > "$proj_conf"
  $0.write_array config "${GDM_PROJ_CONFIG_ARRAY[@]}"
  echo "${GDM_PROJ_CONF_FILE_SECTIONS[3]}" >> "$proj_conf"
  $0.write_array config_lock "${GDM_PROJ_LOCK_ARRAY[@]}"
  echo "${GDM_PROJ_CONF_FILE_SECTIONS[5]}" >> "$proj_conf"
}
