
# NOTE: GDM_CONFIG_LOCK_KEYS=(destin remote_url rev setup hash tag branch rev_is setup_hash) 
# Output associative array variable keys from gdm.parseRequirement --QUICKLOCK (called in "QUICK LOCK mode"):
export GDM_REQUIREMENT_QUICKLOCKKEYS=( required_path destin remote_url rev setup hash tag branch rev_is setup_hash  #<- all but required_path are GDM_CONFIG_LOCK_KEYS
          register_parent register_id path_in_registry register_path register_manifest register_snapshot lock_entry)
#       required_path destin remote_url rev setup
#       hash tag branch rev_is setup_hash lock_entry register_parent register_id path_in_registry register_path register_manifest register_snapshot 

# Output variables from gdm.parseRequirement --IS_LOCK (called in "LOCK mode"):
export GDM_REQUIREMENT_LOCKVARS=( "${GDM_REQUIREMENT_QUICKLOCKKEYS[@]}" prev_registered prev_registration_error)
#       required_path destin remote_url rev setup
#       hash tag branch rev_is setup_hash lock_entry register_parent register_id path_in_registry register_path register_manifest register_snapshot 
#       prev_registered prev_registration_error

# Output variables from gdm.parseRequirement (called in "NORMAL mode"):
export GDM_REQUIREMENT_VARS=( "${GDM_REQUIREMENT_LOCKVARS[@]}" repo_identifier remote_ref ) # (the full set)
#       required_path destin remote_url rev setup
#       hash tag branch rev_is setup_hash lock_entry register_parent register_id path_in_registry register_path register_manifest register_snapshot 
#       repo_identifier remote_ref 
#       prev_registered prev_registration_error

# Output variables from gdm.parseRequirement --QUICK (called in "QUICK mode"):
export GDM_REQUIREMENT_QUICKVARS=( destin remote_url rev setup required_path repo_identifier remote_ref )
#       required_path destin remote_url rev setup
#       repo_identifier remote_ref  


#NOTE: gdm.parseRequirement will give different results for different values of GDM_REGISTRY and, 
# since GDM_REGISTRY can be bypassed in a project's GDM_REQUIRE_CONF, gdm.parseRequirement should have
# the project loaded before being run.

gdm.parseRequirement() {
  # gdm.parseRequirement (in the default --NORMAL mode) parses argument for require or register and outputs complete details on the 
  # requirement, along with information on previous registration, if found. It does not check for any installations beside the registration.
  #   Passing --QUICK-PARSE (aka --QUICK) or the related mode --QUICK_LOCK (aka --IS_LOCK --QUICK-PARSE) as first arguments makes the function 
  #     execute faster by skipping analysis of the specified revision and skipping the search for a previous registration and validation of it.
  #   Passing --IS_LOCK (aka --LOCK) or the related mode --QUICK_LOCK (aka --IS_LOCK --QUICK-PARSE) as first arguments makes the function 
  #     expect the input requirement to be a single argument: a string that is an entry in the config_lock array
  # INPUT for LOCK modes is a stated previously and non-LOCK modes is same arguments as expected by gdm.require:
  #     [https://][<domain>/]<vendor>/<repo>[.git][#<hash|tag|branch>] [setup=<function>|<script_path>|cmd>] [destin=<dir name to install>]
  #      (1st arg is referred to here as $repo_identifier and the remaining are unordered)


  # OUTPUT: is a string assigning the following:                           BLANK? SET BY/FROM
  #   For all modes:
  #     required_path=<full abs path to location where required>          never  destin
  #     destin=<name>|<normalized relpath>|<normalized abspath>           never  parseRequirement (interpreted as unique key for a requirement)
  #     remote_url=<expanded from repo_identifier, usualy lowercased)     never  expandRemoteRef 
  #     rev=[<revision specfied after # in repo_identifier]               maybe  expandRemoteRef (currently unused. Planned for lock?)
  #     setup=[<executable value provided>]                               maybe  parseRequirement
  #   For NORMAL and QUICK modes only (non *LOCK modes):
  #     repo_identifier
  #     remote_ref
  #  For all but (normal) QUICK mode:
  #     hash=<full_hash (lowercased) from repo_identifier>                never  expandRemoteRef
  #     tag=[<full_tag not lowercased>]                                   maybe  expandRemoteRef
  #     branch=[<branch_name not lowercased>]                             maybe  expandRemoteRef
  #     rev_is=hash|tag|tag_pattern|branch                                never  expandRemoteRef (currently unused. Planned for lock.)
  #     setup_hash=[hash of setup if passed]                              maybe  parseRequirement
  #     lock_entry
  #     register_parent=$GDM_REGISTRY/domain/vendor/repo                  never  parseRequirement
  #     register_id=$regis_prefix$regis_suffix                            never  parseRequirement
  #     path_in_registry=domain/vendor/repo/$register_id                  never  
  #     register_path=$register_parent/$regis_prefix$regis_suffix         never  parseRequirement 
  #     register_manifest=<full abs path to manifest file in registry>    no     parseRequirement
  #     register_snapshot=<full abs path to manifest file in registry>    no     parseRequirement
  #   For NORMAL and LOCK modes only (non QUICK modes):
  #     prev_registered=true|false                                        never  parseRequirement
  #     prev_registration_error=<GDM_ERRORS value>                        maybe NEW: if not previously registered, there is no error
  #
  # ERROR REASON (all returns are keys in GDM_ERRORS)
  #         Return:                 Applicable modes:                    Cause:               
  #     invalid_argument          NORMAL, QUICK, LOCK, QUICK_LOCK    no arguments received
  #     invalid_argument          LOCK, QUICK_LOCK                   lock entry empty,  missing keys or fails eval
  #     invalid_argument          NORMAL, QUICK                      unknown option
  #     multiple_setups_args      NORMAL, QUICK                      (self explanitory)
  #     invalid_setup             NORMAL, QUICK                      setup: is script outside proj_root or unloadable, not a script/function, can't be hashed
  #     invalid_destination_arg   NORMAL, QUICK                      (see comments in gdm_expandDestination definition)
  #     cannot_expand_remote_url  NORMAL, QUICK                      NORMAL: gdm_expandRemoteRef failed QUICK: gdm_gitExpandRemoteUrl failed
  #     cannot_find_revision      NORMAL                             from gdm_expandRemoteRef's return
  #     cannot_find_branch        NORMAL                             from gdm_expandRemoteRef's return
  #     cannot_find_tag           NORMAL                             from gdm_expandRemoteRef's return
  #     cannot_find_hash          NORMAL                             from gdm_expandRemoteRef's return


  #NOTE ON PERFORMANCE: The biggest time hogs are gdm_expandRemoteRef and gdm_validateInstance

  #################### get flag arguments & get oriented ##################################
  
  local is_lock=false # The requirement passed to this function is an entry from config_lock
  local quick_parse=false # Bypasses gdm_expandRemoteRef and gdm_validateInstance

  while [[ "$1" =~ '^--.+' ]] ; do
    arg="${1:u}"
    if [[ "$arg" =~ '^--QUICK[-_]?LOCK' ]] ; then quick_parse=true ; is_lock=true
    elif [[ "$arg" =~ '^--QUICK([-_]PARSE)?' ]] ; then quick_parse=true # must come after quicklock check
    elif [[ "$arg" =~ '^--(IS[-_])?LOCK' ]] ; then is_lock=true 
    elif [[ "$arg" =~ '^--NORMAL' ]] ; then quick_parse=false ; is_lock=false 
    fi
    shift
  done

  if ! (($#)) ; then echo "$(_S Y)$0 received no arguments! $(_S)" >&2  ; return $GDM_ERRORS[invalid_argument] ; fi

  local outputVars
  if $is_lock ; then
    if $quick_parse ; then  outputVars=("${GDM_REQUIREMENT_QUICKLOCKKEYS[@]}") # $is_lock && $quick_parse "QUICK LOCK mode"
      # echo "$0 QUICK LOCK mode" >&2 ; print -l "  "${^@}  >&2 #TEST
    else                    outputVars=("${GDM_REQUIREMENT_LOCKVARS[@]}")      # $is_lock && ! $quick_parse "LOCK mode"
      # echo "$0 LOCK mode" >&2 ; print -l "  "${^@}  >&2 #TEST
    fi
  elif $quick_parse ; then  outputVars=("${GDM_REQUIREMENT_QUICKVARS[@]}")         # ! $is_lock && $quick_parse "QUICK mode"
    # echo "$0 QUICK mode" >&2 ; print -l "  "${^@}  >&2 #TEST
  else                      outputVars=("${GDM_REQUIREMENT_VARS[@]}")               # ! $is_lock && ! $quick_parse "NORMAL mode"
    # echo "$0 NORMAL mode" >&2 ; print -l "  "${^@}  >&2 #TEST
  fi
  local $outputVars # declare all output vars (even though we may not use all) 
  #NOTE: do we need to reset any $outputVars??

  # TODO: this is unsafe: GDM_PROJ_ROOT should always be non-empty if called from project:
  [[ -z "$GDM_PROJ_ROOT" ]] && GDM_PROJ_ROOT="$PWD" #NOTE: this must come before call to gdm_expandRemoteRef

  
  if ! $is_lock ; then ############ NORMAL + QUICK modes: expand arguments #################################################
    # OUTPUT VARS SET HERE: repo_identifier setup destin required_path remote_ref rev remote_url 
    # AND, IF NORMAL mode: rev_is hash tag branch (NON-OUTPUT: regis_prefix regis_suffix)

    repo_identifier="$1" ; shift # [domain/]vendor/repo[.git][#<hash>|#<tag>|#<branch>]
    
    if ! $quick_parse ; then #------------------------- NORMAL mode: gdm_expandRemoteRef ------------------------------
      # OUTPUT VARS SET HERE: remote_ref rev remote_url rev_is hash tag branch (non-output vars: regis_prefix)
      local requirement  # assigns: remote_ref rev remote_url rev_is hash tag branch
      ! requirement="$(gdm_expandRemoteRef "$repo_identifier")" && return $? 
      #NOTE: $? from gdm_expandRemoteRef: cannot_expand_remote_url cannot_find_(revision|branch|tag|hash)
      eval "$requirement" ; # all requirement vars are set but rev, branch, tag may be empty.
      local regis_prefix=$hash
    
    
    else #------------------------------------------- QUICK MODE: gdm_gitExpandRemoteUrl ------------------------------
      # OUTPUT VARS SET HERE: remote_ref rev remote_url
      # (Since we don't parse rev, we get no: rev_is hash tag branch) (and without hash we have no: regis_prefix )
      remote_ref="${repo_identifier%#*}"
      rev="${repo_identifier##*#}" ; [[ "$rev" ==  "$remote_ref" ]] && rev=""
      if ! remote_url="$( gdm_gitExpandRemoteUrl "$remote_ref" )" || [[ -z "$remote_url" ]] ; then
        return $GDM_ERRORS[cannot_expand_remote_url]
      fi
    fi

    #------------------------------------- NORMAL + QUICK modes: Parse & Process Arguments ----------------------------
    # OUTPUT VARS SET HERE: setup destin -> required_path 
    # AND, IF NORMAL MODE : lock_entry setup_hash (from non-output: regis_suffix)
    # NOTE: can't set lock_entry if QUICK mode because we lack setup_hash
    # POSSIBLE ERRORS: multiple_setups_args
    for arg in $@ ; do
      # Parse if setup argument:
      if [[ "${arg:l}" =~ '^-{0,2}(s|setup)[=].+' ]] ; then
        if ! [[ -z "$setup" ]] ; then gdm_multiArgError "$1" '`setup` arguments' ; return $multiple_setups_args ; fi
        setup="${arg#*=}" 
        if ! $quick_parse ; then
          setup_hash=$(gdm_setupToHash "$setup") || return $? # $GDM_ERRORS[invalid_setup] (previously also return 1 for $0.strToHash failure)
          local regis_suffix="-$setup_hash"
        fi
      # Parse if destin argument:
      elif [[ "${arg:l}" =~ '^-{0,2}d(est|estin|estination|ir|irectory)?=.+' ]] ; then
        #NOTE: outputVars from gdm_expandDestination are destin destin_relto required_path. All already local except:
        local destin_relto #TODO: This should one day maybe be in our outputVars but for now we only allow destin_relto='GDM_REQUIRED
        destin="${arg#*=}" #NOTE: this may be modified (standardized) by gdm_expandDestination
        local assignments
        assignments="$(gdm_expandDestination $destin)" || return $? # always 0 or $GDM_ERRORS[invalid_destination_arg]
        eval "$assignments" # sets: destin destin_relto required_path
      # ERROR if else:
      else echo "$(_S R S)Invalid argument: $arg$(_S)" >&2 ; return $GDM_ERRORS[invalid_argument] 
      fi
    done
    if [[ -z "$required_path" ]] ; then # default required path destination:
      # destin="${remote_url:t:r}" # note that: repo_name="${remote_url:t:r}"
      #NOTE: Changed default `destin` value was changed to use same capitalization used by user in specifying repository.
      destin="${${repo_identifier%#*}:t:r}"
      required_path="$GDM_PROJ_ROOT/$GDM_REQUIRED/$destin" # set to repo name, within required dir
    fi

    if ! $quick_parse ; then #------------- NORMAL mode: setup_hash lock_entry (non-output: regis_suffix) -------------
      # NOTE: can't set lock_entry if QUICK mode because we lack setup_hash
      lock_entry="$(gdm_varsToMapBody $GDM_CONFIG_LOCK_KEYS)"
    
    else ################ RETURN for QUICK MODE ############################################################################
      gdm_echoVars $outputVars 
      return 0
    fi

  
  else ################## LOCK + QUICK LOCK modes: parse lock_entry to get variables ########################################
    # OUTPUT VARS SET HERE (parens are GDM_CONFIG_LOCK_KEYS): 
    #                 (destin remote_url rev setup hash rev_is tag branch setup_hash) lock_entry destin->required_path
    # (non-output vars: regis_prefix regis_suffix)
    lock_entry="$1" # /Should/ be the body of an associative array (stuff between parens) with $GDM_CONFIG_LOCK_KEYS

    if [[ -z "$lock_entry" ]] ; then 
      echo "$(_S R S)$0 got an empty lock argument! Does config_lock have an empty element? If so, delete it! $(_S)" >&2  ; return $GDM_ERRORS[invalid_argument] 
    fi
    # unset $GDM_CONFIG_LOCK_KEYS # unset so we don't get stale values
    # local $GDM_CONFIG_LOCK_KEYS

    local assigments_or_stderr # or an error
    if ! assigments_or_stderr="$(gdm_echoMapBodyToVars --require="$GDM_CONFIG_LOCK_KEYS" $lock_entry 2>&1)" ; then
      echo "$(_S R S)The following config_lock element is is invalid:\n$(_S)  $lock_entry\n$(_S R S)$assigments_or_stderr$(_S)" >&2 ; return $GDM_ERRORS[invalid_argument] 
    fi
    # echo "assigments_or_stderr is:\n$assigments_or_stderr" && return #TEST

    local eval_err
    eval "$assigments_or_stderr" ; eval_err=$? # eval should assign all GDM_CONFIG_LOCK_KEYS
    if ((eval_err)) ; then 
      echo "$(_S R S)The following config_lock element could not be evaluated:\n$(_S)  $lock_entry\n$(_S R S)$assigments_or_stderr$(_S)"  >&2 ; return $GDM_ERRORS[invalid_argument] 
    fi

    required_path="$GDM_PROJ_ROOT/$GDM_REQUIRED/$destin" 
    local regis_prefix="$hash"
    local regis_suffix="" ;  ! [[ -z "$setup_hash" ]] && regis_suffix="-$setup_hash"
  fi

  #################### NORMAL + LOCK + QUICK LOCK modes: Assemble Paths  ###################################################
  # OUTPUT VARS SET HERE: register_id register_parent path_in_registry register_path register_manifest register_snapshot
  # (non-output vars: domain_vendor_repo)
  register_id="$regis_prefix$regis_suffix"
  local domain_vendor_repo="${${remote_url#*//}:r}"
  register_parent="$GDM_REGISTRY/$domain_vendor_repo" # set to $GDM_REGISTRY/domain/vendor/repo
  #TODO: maybe we should output the above without $GDM_REGISTRY/ and maybe rename this variable to repo_register
  # Why? It should be added to config_lock and we don't want GDM_REGISTRY there since it's customizable 
  #UPDATE: Done, but not just parent, the register_path without $GDM_REGISTRY and as a separate variable called path_in_registry
  path_in_registry="$domain_vendor_repo/$register_id"
  register_path="$register_parent/$register_id" 
  register_manifest="$register_path/$register_id.$GDM_MANIF_EXT"
  register_snapshot="$register_path.$GDM_SNAP_EXT"

  
  if ! $quick_parse ; then  #### NORMAL + LOCK modes: PREVIOUSLY REGISTERED ? VALIDATE IT ##################################
  # OUTPUT VARS SET HERE: prev_registered prev_registration_error
    prev_registered=false
    if [[ -d "$register_path" ]] ; then
      echo "##  gdm_validateInstance" >&2 #TEST 
      prev_registered=true #TODO: keep this as true even if register is invalid?
      local manif_valid_assigns="$(gdm_echoVars --local $GDM_MANIF_VALIDATABLES)" 
      gdm_validateInstance --register $register_manifest $register_path $register_snapshot "$manif_valid_assigns" $GDM_MANIF_VALIDATABLES #FUNCTION CALL: gdm_validateInstance
      prev_registration_error=$?
    fi
  fi

  if $is_lock && $quick_parse ; then #### RETURN for QUICK_LOCK mode (output is hash body) #################################
    for varname in $outputVars ; do print -n "[$varname]=$(gdm_quote $varname) " ; done
    return 0
  fi

  ####################### RETURN for NORMAL + LOCK modes ###################################################################
  gdm_echoVars $outputVars 
  return 0

}

