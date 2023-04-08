
export GDM_REQUIREMENT_VARS=(remote_url rev setup destin_option destin_value rev_is hash tag branch setup_hash to regis_parent_dir regis_prefix regis_suffix 
  regis_id regis_instance destin_instance regis_manifest regis_snapshot previously_registered previous_regis_error)

gdm_parseRequirement() {
  # gdm_parseRequirement parse argument for require or register and outputs complete details on the requirement, along
  # with information on previous registration, if found. It does not check for any installations beside the registration.

  # Input is the following arguments (same arguments as expected by gdm.require, optionally prepended with flags)
  #     [<flags>] [https://][<domain>/]<vendor>/<repo>[.git][#<hash|tag|branch>] [setup=<function>|<script_path>|cmd>] [<destin-flag>=<path>|<dirname>]
  #  (1st arg (after flags) is referred to here as $repo_identifier)
  # Destination Options: 
  #   Choosing one of the following options to define an install location 
  #   for a given required repository/version. TODO: Choosing more than one will result 
  #   in more than one installation of the same repository/version. Providing none of 
  #   the following options defaults to installing a directory whose name is the 
  #   repository name, placed in the \$GDM_REQUIRED directory. This is equivalent to 
  #   providing `-as=<repo_name>`. Options ending with `-as` define the path to the 
  #   installed directory, including the installed directory's name and those ending with 
  #   `-in` define the path to the parent directory where the installation, which will be 
  #   given the default name that is the repository name. 
  #  Examples:
  #     as=name                   Install as custom directory name to \$GDM_REQUIRED.
  #     to-proj-as=./parent/name  Install as custom directory name, provided as
  #                               a path relative to the project root. The relative path  
  #                               must start with ./ a directory name or ../ and not /
  #     to-fs-as=/parent/name     Install as custom directory name, provided as
  #                               an absolute path starting with / whose location is 
  #                               not contained by the project root.
  #     to-proj-in=./parent       Install in a custom parent directory, provided as
  #                               a path relative to the project root. The relative path  
  #                               must start with ./ a directory name or ../ and not /
  #     to-fs-in=/parent          Install in a custom parent directory, provided as
  #                               an absolute path starting with / whose location is 
  #                               not contained by the project root.
  #     These are temporarily arrays to detect erroneous double assignment but TODO: support multiple locations
  # orginal gdm_parseRequirement output sets: 
  #     remote_url rev rev_is hash tag branch 
  #     to destin_option       (to is more recently added, destin_option was too but we won't need it I think)
  #     setup setup_hash regis_parent_dir regis_prefix regis_suffix regis_instance destin_instance 
  #  more output from?
  #     regis_manifest regis_snapshot previously_registered   REMOVING: register_created
  # of the above, the following need to be passed on to gdm_register sometime after the call to this function (if registering)
  #     remote_url hash setup regis_manifest regis_instance regis_snapshot regis_parent_dir regis_id destin_instance
  #  which are the following (only line's value will be in \"\" and ending with semicolons):
  #   keep?                                                            BLANK? SETBY
  #   Y remote_url=<expanded from repo_identifier, usualy lowercased)  never  expandRemoteRef 
  #     rev=[<revision specfied after # in repo_identifier]            maybe  expandRemoteRef
  #     rev_is=hash|tag|tag_pattern|branch                             never  expandRemoteRef
  #   Y hash=<full_hash (lowercased) from repo_identifier>             never  expandRemoteRef
  #     tag=[<full_tag not lowercased>]                                maybe  expandRemoteRef
  #     branch=[<branch_name not lowercased>]                          maybe  expandRemoteRef
  #   ? to=<name>|<normalized relpath>|<normalized abspath>            never  parseRequirement
  #   ? destin_option=to|as|to-proj-as|to-fs-as|to-proj-in|to-fs-in    maybe  parseIfDesinationOption
  #   ? destin_value=<value provided by user with destin_option>       maybe  parseIfDesinationOption
  #   Y setup=[<executable value provided>]                            maybe  parseRequirement
  #   N setup_hash=[hash of setup if passed]                           maybe  parseRequirement
  #   Y regis_parent_dir=$GDM_REGISTRY/domain/vendor/repo              never  parseRequirement
  #   N regis_prefix=<tag if found>|<estim. short hash if no tag>      never  parseRequirement
  #   N regis_suffix=_setup-<setup hash>                               never  parseRequirement
  #   Y regis_id=$regis_prefix$regis_suffix                            never  parseRequirement
  #   Y regis_instance=$regis_parent_dir/$regis_prefix$regis_suffix    never  parseRequirement (previously gdm.register)
  #   Y destin_instance=<full abs path to location where required>     never  parseRequirement
  #   Y regis_manifest=<full abs path to manifest file in registry>    maybe 
  #   Y regis_snapshot=<full abs path to manifest file in registry>    
  #   Y previously_registered=true|false                               never
  #   Y previous_regis_error=<GDM_ERRORS value>                        maybe NEW: if not previously registered, there is no error

  local outputVars=("${GDM_REQUIREMENT_VARS[@]}")
  local invalid_argument=$GDM_ERRORS[invalid_argument] # To make code a bit cleaner

  if ! (($#)) ; then echo "$(_S Y)$0 received no arguments!$(_S)" >&2  ; return $invalid_argument ; fi

  ################################# get flag arguments ##################################
  local lone_regis_flag="" # default will be to allow registry to be the only instance
  while [[ "$1" =~ '^--' ]] ; do
    if  [[ "$1" =~ '^--(force-re-register|force)$' ]] ; then shift # ignore as this doesn't concern this function
    elif  [[ "$1" =~ '^--(dis)?allow-lone[^=]*$' ]] ; then 
      ! [[ -z "$lone_regis_flag" ]] && lone_regis_flag=ERROR || lone_regis_flag="$1" 
      shift ; # Even with ERROR (multiple redundant flags), keep gobbling args so we have an error messages with proper "$1"
    elif [[ "$1" =~ '^--dry-run$' ]] ; then shift  # ignore as this doesn't concern this function
    # possibly add more options here, later on
    else break 
    fi
  done
  [[ -z "$lone_regis_flag" ]] && lone_regis_flag="--allow-lone" # set default to allow it
  if [[ "$lone_regis_flag" == ERROR ]] ; then echo "$(_S R S)$1 has multiple allow-lone options specified!$(_S)" >&2 ; return $invalid_argument ; fi
  
  ############################ expand repo_identifier argument ##########################
  # TODO: this is unsafe: PROJ_ROOT should always be non-empty if called from project:
  [[ -z "$PROJ_ROOT" ]] && PROJ_ROOT="$PWD" #NOTE: this must come before call to gdm_expandRemoteRef
  local repo_identifier="$1" ; shift # [domain/]vendor/repo[.git][#<hash>|#<tag>|#<branch>]
  local requirement  
  ! requirement="$(gdm_expandRemoteRef "$repo_identifier")" && return $?
  local remote_url rev rev_is hash tag branch # <- these are what output of gdm_expandRemoteRef assigns
  eval "$requirement" ; # all requirement vars are set but rev, branch, tag may be empty.

  
  ####################### get setup and destination arguments ###########################
  local setup destin_option destin_value to destin_instance 
  for arg in $@ ; do
    if [[ "${arg:l}" =~ '^-{0,2}(s|setup)[=].+' ]] ; then
      if ! [[ -z "$setup" ]] ; then gdm_multiArgError "$1" '`setup` arguments' ; return $? ; fi
      setup="${arg#*=}" 
    elif ! destin_assignments="$(gdm_parseIfDesinationOption $arg)" ; then # don't add >&2
      return $invalid_argument # (All gdm_parseIfDesinationOption errors are $GDM_ERRORS[invalid_argument] with stderr)
    elif ! [[ -z "$destin_assignments" ]] ; then
      if ! [[ -z "$destin_instance" ]] ; then
        echo "$(_S R S)$repo_identifier has multiple destinations specified! (got $arg) $(_S)" >&2 ; return $invalid_argument
      fi
      eval "$destin_assignments" # assigns: destin_option destin_value to destin_instance 
    else echo "$(_S R S)Invalid argument: $arg$(_S)" >&2 ; return $invalid_argument
    fi
  done
  if [[ -z "$destin_instance" ]] ; then # default destination:
    to="${remote_url:t:r}" # note that: repo_name="${remote_url:t:r}"
    destin_instance="$PROJ_ROOT/$GDM_REQUIRED/${remote_url:t:r}" # set to repo name, within required dir
    # destin_option destin_value are left empty as user did not provide any.
  fi
  
  ###### set regis_suffix: get value and type of setup command and hash it #################################
  local regis_suffix="" # empty unless there is a setup, in which case it will be: _setup-<setup_hash>
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
    regis_suffix="_setup-$setup_hash"
  fi

  

  local regis_parent_dir="$GDM_REGISTRY/${${remote_url#*//}:r}" # set to $GDM_REGISTRY/domain/vendor/repo
  local regis_prefix="$tag" ; [[ -z "$regis_prefix" ]] && regis_prefix=$hash[1,$GDM_MIN_HASH_LEN] 
  # NOTE: when regis_prefix is a hash, it is an estimate that may need elongation (done later in this function)
  # [[ -z "$regis_prefix" ]] && return 64 #TODO: what was this??

  local regis_instance="$regis_parent_dir/$regis_prefix$regis_suffix" #TODO: this is first assignment yet no local so I added it

  local manifest_found=false
  local regis_id="$regis_prefix$regis_suffix"

  if [[ -d "$regis_parent_dir" ]] ; then
    # Expand Hash to be long enough to not clash 
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

  regis_instance="$regis_parent_dir/$regis_id" #TODO: this was commented (was previously local). Problem to uncomment?? 
  local regis_manifest="$regis_instance/$regis_id.$GDM_MANIF_EXT"
  local regis_snapshot="$regis_instance.$GDM_SNAP_EXT"

  local previously_registered=false
  local previous_regis_error

  if $manifest_found ; then
    previously_registered=true
    local manif_valid_assigns="$(gdm_echoVars $GDM_MANIF_VALIDATABLES)" 

    gdm_validateInstance $lone_regis_flag $regis_manifest $regis_instance $regis_snapshot "$manif_valid_assigns" $GDM_MANIF_VALIDATABLES #FUNCTION CALL: gdm_validateInstance
    previous_regis_error=$?
  
  elif [[ -d "$regis_instance" ]] ; then
    previously_registered=true #TODO: add this? (it was left false here before and I think true was flag indicating VALID regis )
    previous_regis_error=$GDM_ERRORS[manifest_missing]
  else
    previously_registered=false 
  fi

  gdm_echoVars $outputVars 
  return 0

}

