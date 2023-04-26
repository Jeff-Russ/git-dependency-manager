
export GDM_REQUIREMENT_VARS=(remote_url rev setup required_path_opt required_path_val rev_is hash tag branch to setup_hash register_parent  
  register_id register_path required_path register_manifest register_snapshot prev_registered prev_registration_error)

#NOTE: gdm.parseRequirement will give different results for different values of GDM_REGISTRY and, 
# since GDM_REGISTRY can be bypassed in a project's GDM_REQUIRE_CONF, gdm.parseRequirement should have
# the project loaded before being run.

gdm.parseRequirement() {
  # gdm.parseRequirement parse argument for require or register and outputs complete details on the requirement, along
  # with information on previous registration, if found. It does not check for any installations beside the registration.

  # Input is the following arguments (same arguments as expected by gdm.require, optionally prepended with flags)
  #     --(dis)?allow-unlinked [https://][<domain>/]<vendor>/<repo>[.git][#<hash|tag|branch>] [setup=<function>|<script_path>|cmd>] [<required_path_opt flag>=<required_path_val>]
  #  (1st arg is referred to here as $repo_identifier)
  # Output:
  #                                                                  BLANK? SETBY
  #   remote_url=<expanded from repo_identifier, usualy lowercased)     never  expandRemoteRef 
  #   rev=[<revision specfied after # in repo_identifier]               maybe  expandRemoteRef (currently unused)
  #   rev_is=hash|tag|tag_pattern|branch                                never  expandRemoteRef (currently unused)
  #   hash=<full_hash (lowercased) from repo_identifier>                never  expandRemoteRef
  #   tag=[<full_tag not lowercased>]                                   maybe  expandRemoteRef
  #   branch=[<branch_name not lowercased>]                             maybe  expandRemoteRef
  #   required_path_opt=to|as|to-proj-as|to-fs-as|to-proj-in|to-fs-in   maybe  parseIfDesinationOption (currently unused)
  #   required_path_val=<value provided by user with required_path_opt> maybe  parseIfDesinationOption (currently unused)
  #   to=<name>|<normalized relpath>|<normalized abspath>               never  parseRequirement (currently unused)
  #   required_path=<full abs path to location where required>          never  parseRequirement
  #   setup_hash=[hash of setup if passed]                              maybe  parseRequirement
  #   setup=[<executable value provided>]                               maybe  parseRequirement
  #   register_parent=$GDM_REGISTRY/domain/vendor/repo                  never  parseRequirement
  #   register_id=$regis_prefix$regis_suffix                            never  parseRequirement
  #   register_path=$register_parent/$regis_prefix$regis_suffix         never  parseRequirement 
  #   register_manifest=<full abs path to manifest file in registry>    no     parseRequirement
  #   register_snapshot=<full abs path to manifest file in registry>    no     parseRequirement
  #   prev_registered=true|false                                        never  parseRequirement
  #   prev_registration_error=<GDM_ERRORS value>                        maybe NEW: if not previously registered, there is no error

  ################################# get flag arguments ##################################
  local unlinked_regis_flag="" # default will be to allow register to be the only instance
  while [[ "$1" =~ '^--.+' ]] ; do
    if  [[ "$1" =~ '^--(dis)?allow-unlinked[^=]*$' ]] ; then 
      ! [[ -z "$unlinked_regis_flag" ]] && echo "$(_S Y B)WARNING: $0 got multiple allow-unlinked option flags!$(_S)" >&2 ;
      unlinked_regis_flag="$1" ; 
    else echo "$(_S Y B)WARNING: $0 got unknown flag: $1$(_S)" >&2 
    fi
    shift # Even with ERROR (or WARNING, keep gobbling args so we have a proper "$1"
  done
  # [[ -z "$unlinked_regis_flag" ]] && unlinked_regis_flag="--allow-unlinked" # set default to allow it

  local outputVars=("${GDM_REQUIREMENT_VARS[@]}")

  local invalid_argument=$GDM_ERRORS[invalid_argument] # To make code a bit cleaner

  if ! (($#)) ; then echo "$(_S Y)$0 received no arguments!$(_S)" >&2  ; return $invalid_argument ; fi
  
  ############################ expand repo_identifier argument ##########################
  # TODO: this is unsafe: GDM_PROJ_ROOT should always be non-empty if called from project:
  [[ -z "$GDM_PROJ_ROOT" ]] && GDM_PROJ_ROOT="$PWD" #NOTE: this must come before call to gdm_expandRemoteRef
  local repo_identifier="$1" ; shift # [domain/]vendor/repo[.git][#<hash>|#<tag>|#<branch>]
  local requirement  
  ! requirement="$(gdm_expandRemoteRef "$repo_identifier")" && return $?
  local remote_url rev rev_is hash tag branch # <- these are what output of gdm_expandRemoteRef assigns
  eval "$requirement" ; # all requirement vars are set but rev, branch, tag may be empty.
  
  ################# get setup and required path destination arguments #############################
  local setup
  local required_path_opt required_path_val to required_path destin_assignments # from gdm_parseIfDesinationOption

  for arg in $@ ; do
    if [[ "${arg:l}" =~ '^-{0,2}(s|setup)[=].+' ]] ; then
      if ! [[ -z "$setup" ]] ; then gdm_multiArgError "$1" '`setup` arguments' ; return $multiple_setups_args ; fi
      setup="${arg#*=}" 
    elif ! destin_assignments="$(gdm_parseIfDesinationOption $arg $destination_found)" ; then # don't add >&2
      return $invalid_destination_arg # (All gdm_parseIfDesinationOption errors are $GDM_ERRORS[invalid_argument] with stderr)
    elif ! [[ -z "$destin_assignments" ]] ; then
      if ! [[ -z "$required_path" ]] ; then gdm_multiArgError "$1" 'detination options' ; return $multiple_destination_args ; fi
      eval "$destin_assignments" # assigns: required_path_opt required_path_val to required_path 
    else echo "$(_S R S)Invalid argument: $arg$(_S)" >&2 ; return $invalid_argument
    fi
  done

  if [[ -z "$required_path" ]] ; then # default required path destination:
    # to="${remote_url:t:r}" # note that: repo_name="${remote_url:t:r}"
    #NOTE: Changed default `to` value was changed to use same capitalization used by user in specifying repository.
    to="${${repo_identifier%#*}:t:r}"
    required_path="$GDM_PROJ_ROOT/$GDM_REQUIRED/$to" # set to repo name, within required dir
    # required_path_opt required_path_val are left empty as user did not provide any.
  fi
  
  ###### set regis_suffix: get value and type of setup command and hash it #################################
  local regis_suffix="" # empty unless there is a setup, in which case it will be: _<setup_hash>
  local setup_hash=""
  if ! [[ -z "$setup" ]] ; then
    # Here we resolve value of $setup to something that doesn't change and then form a $hash from that
    local setup_val="" # this is cat of file if setup is script, source of function if typeset -f "$setup" else just setup copied
    if [[ -f "${setup:a}" ]] ; then 
      # setup is SCRIPT: we use the cat value to form the hash
      local setup_a="${setup:a}" # we resolve to full path so we can call from anywhere
      ! [[ -x "$setup_a" ]] && chmod +x "$setup_a"
      if ! setup_val="$(cat "$setup_a" 2>/dev/null)" ; then echo "$(_S R S)$setup (setup script) cannot be read!$(_S)" >&2 ; return 1 ; fi
    elif typeset -f "$setup" >/dev/null 2>&1 ; then
      # setup is FUNCTION: we use it's source code as a string to form the hash
      autoload +X "$setup"  # loads an autoload function without executing it so we can call whence -c on it and see source
      if ! setup_val="$(whence -cx 2 "$setup" 2>/dev/null)" ; then echo "$(_S R S)$setup (setup function) cannot be read!$(_S)" >&2 ; return 1 ; fi
    else setup_val="$setup" # and hope for the best when we actually run it!
    fi
    $0.strToHash() { crc32 <(echo "$1") ; }
    if ! setup_hash=$($0.strToHash "$setup_val") ; then echo "$(_S R S)$setup (setup) cannot be hashed!$(_S)" >&2 ; return 1 ; fi
    regis_suffix="_$setup_hash"
  fi

  ###### set regis_prefix to full hash and assemble paths  ############################################################

  local register_parent="$GDM_REGISTRY/${${remote_url#*//}:r}" # set to $GDM_REGISTRY/domain/vendor/repo
  #TODO: maybe we should output the above without $GDM_REGISTRY/ and maybe rename this variable to repo_register
  # Why? It should be added to config_lock and we don't want GDM_REGISTRY there since it's customizable 

  local regis_prefix=$hash

  local register_id="$regis_prefix$regis_suffix"
  local register_path="$register_parent/$register_id" 

  local register_manifest="$register_path/$register_id.$GDM_MANIF_EXT"
  local register_snapshot="$register_path.$GDM_SNAP_EXT"


  #### SEARCH FOR & VALIDATE PREVIOUS REGISTER OR MARK AS NOT PREVIOUSLY REGISTERED ##################################

  local prev_registered=false
  local prev_registration_error

  if [[ -d "$register_path" ]] ; then
    prev_registered=true #TODO: keep this as true even if register is invalid?
    local manif_valid_assigns="$(gdm_echoVars --local $GDM_MANIF_VALIDATABLES)" 
    gdm_validateInstance --register $unlinked_regis_flag $register_manifest $register_path $register_snapshot "$manif_valid_assigns" $GDM_MANIF_VALIDATABLES #FUNCTION CALL: gdm_validateInstance
    prev_registration_error=$?
  fi

  gdm_echoVars $outputVars 
  return 0

}

