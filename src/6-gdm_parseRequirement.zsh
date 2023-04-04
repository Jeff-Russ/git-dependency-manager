

gdm_parseRequirement() {
  # expected args: [domain/]vendor/repo[.git][#<hash>|#<tag or tag_patt>|#<branch>] [setup] [to=<path>|as=<dir_name>]
  #                which are the same arguments as expected by gdm.require
  #                 (1st arg is referred to here as $repo_identifier)
  # output sets: remote_url rev rev_is hash tag branch to setup_hash regis_parent_dir regis_prefix regis_suffix regis_instance destin_instance
  #              which are the following (only line's value will be in \"\" and ending with semicolons):
  #   remote_url=<expanded from repo_identifier, usualy lowercased)  (never blank)
  #   rev=[<revision specfied after # in repo_identifier]            (may be blank)
  #   rev_is=hash|tag|tag_pattern|branch                             (never blank)
  #   hash=<full_hash (lowercased) from repo_identifier>             (never blank)
  #   tag=[<full_tag not lowercased>]                                (may be blank)
  #   branch=[<branch_name not lowercased>]                          (may be blank)
  #   to=<name>|<normalized relpath>|<normalized abspath>            (never blank)
  #   setup=[<executable value provided>]                            (may be blank)
  #   setup_hash=[hash of setup if passed]                           (may be blank)
  #   regis_parent_dir=$GDM_REGISTRY/domain/vendor/repo              (never blank)
  #   regis_prefix=<tag if found>|<estim. short hash if no tag>      (never blank)
  #   regis_suffix=_setup-<setup hash>"                              (never blank)
  #   regis_instance=$regis_parent_dir/$regis_prefix$regis_suffix    (never blank)
  #   destin_instance=<full abs path to location where required>     (never blank)
  # NOTE "<estim. short hash if no tag>" is estimate that may need elongation (not done in this function)

  [[ -z "$PROJ_ROOT" ]] && PROJ_ROOT="$PWD" ; # TODO: this is unsafe: PROJ_ROOT should always be non-empty if called from project

  local repo_identifier="$1" # [domain/]vendor/repo[.git][#<hash>|#<tag>|#<branch>]
  local requirement  
  ! requirement="$(gdm_expandRemoteRef "$repo_identifier")" && return $?

  local remote_url rev rev_is hash tag branch # these are gdm_expandRemoteRef vars:
  eval "$requirement" ; # all requirement vars are set but rev, branch, tag may be empty.

  local repo_name="${remote_url:t:r}"

  local setup="" ; # setup function/command/script as provided by caller (value after 'setup=')

  # Destination Options: 
  # Choosing one of the following options to define an install location 
  # for a given required repository/version. TODO: Choosing more than one will result 
  # in more than one installation of the same repository/version. Providing none of 
  # the following options defaults to installing a directory whose name is the 
  # repository name, placed in the \$GDM_REQUIRED directory. This is equivalent to 
  # providing `-as=<repo_name>`. Options ending with `-as` define the path to the 
  # installed directory, including the installed directory's name and those ending with 
  # `-in` define the path to the parent directory where the installation, which will be 
  # given the default name that is the repository name. 
  # Examples:
  # as=name                   Install as custom directory name to \$GDM_REQUIRED.

  # to-proj-as=./parent/name  Install as custom directory name, provided as
  #                           a path relative to the project root. The relative path  
  #                           must start with ./ a directory name or ../ and not /

  # to-fs-as=/parent/name     Install as custom directory name, provided as
  #                           an absolute path starting with / whose location is 
  #                           not contained by the project root.

  # to-proj-in=./parent       Install in a custom parent directory, provided as
  #                           a path relative to the project root. The relative path  
  #                           must start with ./ a directory name or ../ and not /

  # to-fs-in=/parent          Install in a custom parent directory, provided as
  #                           an absolute path starting with / whose location is 
  #                           not contained by the project root.
  # These are temporarily arrays to detect erroneous double assignment but TODO: support multiple locations
  local to_locks=()  # "<name>|<relpath>|<abspath>"
  local destin_instances=() # absolute path version of the previous array

  local destin_assignments=""

  shift
  for arg in $@ ; do

    if ! destin_assignments="$(gdm_parseIfDesinationOption $arg >&2)" ; then 
      return $GDM_ERRORS[invalid_argument]
    elif ! [[ -z "$destin_assignments" ]] ; then
      local to_lock abs_target ; eval "$destin_assignments" 
      to_locks+=("$to_lock")
      destin_instances+=("$abs_target")

    elif [[ "${arg:l}" =~ '^-{0,2}(s|setup)[=].+' ]] ; then
      if ! [[ -z "$setup" ]] ; then gdm_multiArgError "$1" '`setup` arguments' ; return $? ; fi
      setup="${arg#*=}" 
      
    else 
      echo "$(_S R S)Invalid argument: $arg$(_S)" >&2 ; return $GDM_ERRORS[invalid_argument]
    fi
  done
  
  if (($#destin_instances>1)) ; then echo "$(_S R S)$1 has multiple \`to\` and/or \`as\` to_locks specified!$(_S)" >&2 ; return $GDM_ERRORS[invalid_argument]
  elif (($#destin_instances==0)) ; then
    to_locks+=("$repo_name")
    destin_instances+=("$PROJ_ROOT/$GDM_REQUIRED/$repo_name") # set to repo name, within required dir
  fi
  local to="${to_locks[1]}"
  local destin_instance="${destin_instances[1]}"

  local regis_parent_dir="$GDM_REGISTRY/${${remote_url#*//}:r}"
  local regis_prefix="$tag" ; [[ -z "$regis_prefix" ]] && regis_prefix=$hash[1,$GDM_MIN_HASH_LEN] 
  [[ -z "$regis_prefix" ]] && return 64

  ###### get value and type of setup command ##################################

  local regis_suffix="" # empty unless there is a setup, in which case it will be: _setup-<setup_hash>
  # registry_id="${regis_prefix}${regis_suffix}" which is <tag>|<shorthash>[_setup-<setup_hash>]
  # $regis_parent_dir/${registry_id}/ was/will the repo+checkout 
  # $regis_parent_dir/${registry_id}.$GDM_ARCH_EXT is this archive of repo+checkout  
  # $regis_parent_dir/${registry_id}.$GDM_TRACK_EXT is the inode tracker
  local setup_hash=""
  if ! [[ -z "$setup" ]] ; then
    # $setup and $hash are the only variables output by $0 so the only job here is to 
    # resolve value of $setup to something that doesn't change and form a $hash from it
    # 
    
    # elif setup is a function, we use it's source (whence -cx 2 $setup) as a string to form the hash
    # else we simply $hash the value of $setup as is
    
    local setup_val=""

    if [[ -f "${setup:a}" ]] ; then 
      # setup is SCRIPT: we use the cat value to form the hash
      local setup_a="${setup:a}" # we resolve to full path so we can call from anywhere
      ! [[ -x "$setup_a" ]] && chmod +x "$setup_a"
      if ! setup_val="$(cat "$setup_a" 2>/dev/null)" ; then echo "$(_S R S)$setup (setup script) cannot be read!$(_S)" >&2 ; return 1 ; fi
    elif typeset -f "$setup" >/dev/null 2>&1 ; then
      # setup is FUNCTION: we use it's source code as a string to form the hash
      autoload +X "$setup"  # loads an autoload function without executing it so we can call whence -c on it and see source
      if ! setup_val="$(whence -cx 2 "$setup" 2>/dev/null)" ; then echo "$(_S R S)$setup (setup function) cannot be read!$(_S)" >&2 ; return 1 ; fi
    else
      setup_val="$setup" # and hope for the best when we actually run it!
    fi
    $0.strToHash() { crc32 <(echo "$1") ; }
    if ! setup_hash=$($0.strToHash "$setup_val") ; then echo "$(_S R S)$setup (setup) cannot be hashed!$(_S)" >&2 ; return 1 ; fi

    regis_suffix="_setup-$setup_hash"
  fi

  regis_parent_dir="$GDM_REGISTRY/${${remote_url#*//}:r}"
  regis_instance="$regis_parent_dir/$regis_prefix$regis_suffix"

  gdm_echoVars remote_url rev rev_is hash tag branch to setup setup_hash regis_parent_dir regis_prefix regis_suffix regis_instance destin_instance
}

