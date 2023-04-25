
gdm_expandRemoteRef() {
  # expected arg: [domain/]vendor/repo[.git][#<hash>|#<tag>|#<branch>]
  # NEW: is expanded to set output, which sets: remote_url rev rev_is hash tag branch
  #   remote_url=<full_remote_url> (from [domain/]vendor/repo[.git])   (never blank)
  #   rev=[<value after # which is after [domain/]vendor/repo[.git]]   (may be blank)
  #   rev_is="hash|tag|tag_pattern|branch"                             (never blank)
  #   hash=<full_hash>                                                 (never blank)
  #   tag=[<full_tag>]                                                 (may be blank)
  #   branch=[<branch_name>]                                           (may be blank)

  # Multiple hits are only allowed when tag_pattern is provided, which is in grep -E regex format.
  # In the case of no hits or (unallowed) multiple hits, an error is returned without output.
  # output includes as rev=$ref_by:ref_val where $ref_val is portion after '#' in input
  # and ref_by is branch tag tag_pattern or hash. When ref_by is not branch, the branch value output
  # may differ depending on when gdm_expandRemoteRef is called (tag/hash combinations don't change
  # but the hash of a branch differs depepending in the most recent commit at the time)
  # if vendor/repo#HEAD ; then rev=branch:HEAD BUT
  # if vendor/repo ; then rev=branch: even though the two are effectively the same.

  # expands remote_url hash and tag information from short remote, hash branch tag or tag pattern.
  # defaulting to HEAD (default branche's most recent hash) if only remote is provided.
  # usage:
  #   gdm_expandRemoteRef vendor/repo#<short_or_long_hash>
  #   gdm_expandRemoteRef vendor/repo#<branch>
  #   gdm_expandRemoteRef vendor/repo#<tag>
  #   gdm_expandRemoteRef vendor/repo#<tag_pattern>
  #   gdm_expandRemoteRef vendor/repo              (same as gdm_expandRemoteRef vendor/repo#HEAD)

  local outputVars=(remote_url rev rev_is hash tag branch)
  local remote_ref="${${1%#*}:l}" # we try lowercased first to avoid multiple registrations
  local remote_url

  if ! remote_url="$( gdm_gitExpandRemoteUrl "$remote_ref" )" ; then
    remote_ref="${1%#*}" # ${1%#*} is abbreviated remote_url (everything before #<hash>|#<tag>)
    if ! remote_url="$( gdm_gitExpandRemoteUrl "$remote_ref" )" || [[ -z "$remote_url" ]] ; then
      echo "$(_S R)Cannot expand Remote Url from $remote_ref$(_S)" >&2 ; return $GDM_ERRORS[cannot_expand_remote_url]
    fi
  fi
  
  local rev="${1##*#}" ;  [[ "$1" == "$rev" ]] && rev="" # ${1##*#}" is everything after #
  local provided="$rev" # backup before possibly setting to default branch (next line).

  [[ -z $rev ]] || [[ $rev == 'HEAD' ]] && rev="$(git remote show $remote_url | sed -n '/HEAD branch/s/.*: //p')" # default branch

  local t_and_b=("${(f)$(git ls-remote --sort=-version:refname -th $remote_url | grep -vE 'refs/tags/.*\^{}$')}") # 90
  local rev_is='?' ; local hits ; local ls_all_hash=("ls-remote"  "--sort=-version:refname" "--refs" "$remote_url")
  local branch='' ; local tag=''

  if   hits=("${(f)$(print -l $t_and_b | grep "refs/heads/${rev}$")}")   && (($#hits==1)) ; then rev_is="branch" ; branch="${hits[1]##*refs/heads/}"
  elif hits=("${(f)$(print -l $t_and_b | grep "refs/tags/${rev}$")}")    && (($#hits==1)) ; then rev_is="tag" ; tag="${hits[1]##*refs/tags/}"
  elif hits=("${(f)$(print -l $t_and_b | grep -E "refs/tags/${rev}$")}") && (($#hits>0)) ; then rev_is="tag_pattern" ; tag="${hits[1]##*refs/tags/}"
  elif hits=("${(f)$(git $ls_all_hash | grep "^${rev:l}")}") && (($#hits>0)) ; then rev_is="hash"  # (hashes are always lowercase)
  # try case-insensitive:
  elif hits=("${(f)$(print -l $t_and_b | grep -i "refs/heads/${rev}$")}") && (($#hits>0)) ; then rev_is="branch" ; branch="${hits[1]##*refs/heads/}"
  elif hits=("${(f)$(print -l $t_and_b | grep -i "refs/tags/${rev}$")}")  && (($#hits>0)) ; then rev_is="tag" ; tag="${hits[1]##*refs/tags/}"
  elif hits=("${(f)$(print -l $t_and_b | grep -iE "refs/tags/${rev}$")}") && (($#hits>0)) ; then rev_is="tag_pattern" ; tag="${hits[1]##*refs/tags/}"
  else 
    echo "$(_S R S)Cannot expand \"$1\". Found remote but no matches found for \"$provided\"$(_S)" >&2 ; return $GDM_ERRORS[cannot_find_revision]
  fi

  local hash="$(echo $hits[1] | awk '{ print $1 }')"  # ; local branch='' ; local tag=''

  [[ $rev_is == tag_pattern ]] && hits=("${hits[1]}") # we allow multiple hits (taking first) if rev was tag pattern
  # But other multiple hash hits are not allowed so if hits contains any other hash, return error:
  if (($#hits>1)) && (($(print -l $hits | grep -vE "^$hash" | grep "" -c)>0)) ; then  # branch tag or hash had to many matches so:

    $0.echoErr() { echo "$(_S R S)Cannot expand \"$1\". Found remote but multiple $2 matching \"$3\" found.$(_S)" >&2 ; }

    if   [[ $rev_is == 'branch' ]] ; then $0.echoErr $1 branches $provided ; return $GDM_ERRORS[cannot_find_branch]
    elif [[ $rev_is == 'tag'* ]]   ; then $0.echoErr $1 tags $provided ; return $GDM_ERRORS[cannot_find_tag]
    elif [[ $rev_is == 'hash' ]]   ; then $0.echoErr $1 hashes $provided ; return $GDM_ERRORS[cannot_find_hash]
    else  echo "$(_S R S)Cannot expand \"$1\". Found remote but no matches found for \"$provided\"$(_S)" >&2 ; return $GDM_ERRORS[cannot_find_revision]
    fi
  fi
  [[ -z $branch ]] && hits=("${(f)$(print -l $t_and_b | grep "$hash.*refs/heads/")}") && (($#hits>0)) && branch="${hits[1]##*refs/heads/}"
  [[ -z $tag ]] && hits=("${(f)$(print -l $t_and_b | grep "$hash.*refs/tags/")}") && (($#hits>0)) && tag="${hits[1]##*refs/tags/}"
  rev="$provided"
  gdm_echoVars remote_url rev rev_is hash tag branch
  return 0
}

gdm_gitExpandRemoteUrl() { 
  [[ -z "$1" ]] && return 3 # none provided
  local remote_url="$1" ; [[ "$remote_url" != *".git" ]] && remote_url="${remote_url}.git"
  if ! git ls-remote --exit-code "$remote_url" >/dev/null 2>&1 ; then
    local fwslashes=$(echo "$remote_url" | grep -o "/"  | wc -l | xargs)
    if [[ $fwslashes == 1 ]] ; then  remote_url="https://github.com/$remote_url"  # github is assumed...
    elif [[ $fwslashes == 2 ]] ; then remote_url="https://$remote_url" # incomplete url but with domain...
    else return 2 ; fi  # error: invalid or could not expand to valid url for a clonable git repository.
    if ! git ls-remote --exit-code "$remote_url" >/dev/null 2>&1 ; then return 1 ; fi # error: could not expand
  fi
  echo "$remote_url" ; return 0
}


# gdm_parseIfSetupOption() {
  # To be called in loop iterating each argument to gdm.require that may be and option to set the setup function.
  # Return: 
  #     Return is only failing if the option passed is a valid destination option flag but has an invalid value.
  #     Lack of output indicates that the option passed not a destination option.
  # Input / Output:
  # IF $1 is an install destination option and is without error, return is 0 and output is assignments of:
  #     required_path_opt   # option passed by user (their argument, up and not including first = )
  #     required_path_val   # value passed by user  (their argument, after first = )
  #     to                  # the install path that would appear after `to=` (name | abs path | relpath starting ../ or ./))
  #     required_path # complete absolute path to install requirement to
  # ELIF $1 is an install destination option with an error, return is $GDM_ERRORS[invalid_argument] and the error is output to stderr 
  # ELSE $1 is not an install detination option, return is 0 and output is empty
  # Usage: place in loop as 
  #     if ! destin_assignments="$(gdm_parseIfDesinationOption $arg)" ; then return $?
  #     elif ! [[ -z "$destin_assignments" ]] ; then
  #       local to required_path ; eval "$destin_assignments"  # then do something with them

# }


gdm_parseIfDesinationOption() {
  # To be called in loop iterating each argument to gdm.require that may be and option to set the install detination.
  # Return: 
  #     Return is only failing if the option passed is a valid destination option flag but has an invalid value.
  #     Lack of output indicates that the option passed not a destination option.
  # Input / Output:
  # IF $1 is an install destination option and is without error, return is 0 and output is assignments of:
  #     required_path_opt   # option passed by user (their argument, up and not including first = )
  #     required_path_val   # value passed by user  (their argument, after first = )
  #     to                  # the install path that would appear after `to=` (name | abs path | relpath starting ../ or ./))
  #     required_path # complete absolute path to install requirement to
  # ELIF $1 is an install destination option with an error, return is $GDM_ERRORS[invalid_destination_arg] and the error is output to stderr 
  # ELSE $1 is not an install detination option, return is 0 and output is empty

  # Usage: place in loop as 
  #     if ! destin_assignments="$(gdm_parseIfDesinationOption $arg)" ; then return $?
  #     elif ! [[ -z "$destin_assignments" ]] ; then
  #       local to required_path ; eval "$destin_assignments"  # then do something with them
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
  #     TODO: support multiple locations
  local arg="$1"
  local outputVars=(required_path_opt required_path_val to required_path) 
  local required_path_opt required_path_val to required_path

  if ! (($GDM_EXPERIMENTAL[(Ie)flexible_required_paths])) ; then # experimental mode disabled....
    if [[ "${arg:l}" =~ '^-{0,2}as[=].+' ]] ; then
      required_path_opt="as"
      required_path_val="${arg#*=}"
      if ! gdm_isNonPathStr "$required_path_val" ; then  # TODO: perhaps allow dir/subdir (just prevent starting with ../ ./ or /)
        echo "$(_S R S)Invalid destination argument: $required_path_opt=\"$required_path_val\" Value must be a directory name and not a path!$(_S)" >&2  ; return $GDM_ERRORS[invalid_destination_arg]
      fi
      to="$required_path_val"
      required_path="$GDM_PROJ_ROOT/$GDM_REQUIRED/$required_path_val"
      gdm_echoVars $outputVars
    fi
  else # flexible_required_paths experimental mode enabled....
    if [[ "$arg" =~ '^to=.+' ]] ; then # the 'to=' format is used in requirement lock...
      # so we'll convert lock form to user's long form so  next if block gets it
      required_path_opt="to"
      required_path_val="${arg#*=}"
      if gdm_isNonPathStr "$required_path_val" ;            then arg="as=$required_path_val"
      elif [[ "$required_path_val" =~ '^\/' ]] ;            then arg="to-fs-as=$required_path_val"
      elif [[ "$required_path_val" =~ '^(\.\.\/|\.\/)' ]] ; then arg="to-proj-as=$required_path_val"
      elif [[ "$required_path_val" =~ '^~\/' ]] ;           then arg="to-home-as=$required_path_val"
      fi
    fi

    if [[ "${arg:l}" =~ '^-{0,2}as[=].+' ]] ; then
      if [[ -z "$required_path_opt" ]] ; then required_path_opt=as ; required_path_val="${arg#*=}" ; fi

      if ! gdm_isNonPathStr "$required_path_val" ; then  # TODO: perhaps allow dir/subdir (just prevent starting with ../ ./ or /)
        echo "$(_S R S)Invalid argument: $required_path_opt=\"$required_path_val\" Value must be a directory name and not a path!$(_S)" >&2  ; return $GDM_ERRORS[invalid_argument]
      fi
      to="$required_path_val"
      required_path="$GDM_PROJ_ROOT/$GDM_REQUIRED/$required_path_val"
      gdm_echoVars $outputVars

    elif [[ "${arg:l}" =~ '^-{0,2}to-(proj|home|fs)-(in|as)[=].+' ]] ; then 
      if [[ -z "$required_path_opt" ]] ; then required_path_opt=${arg%%=} ; required_path_val="${arg#*=}" ; fi
      
      while [[ ${arg[1]} == - ]] ; do arg=${arg[2,-1]} ; done # trim all leading dashes

      # CHECK FOR PATH LOCATION NOTATION ERRORS:
      local notated_as="$(gdm_pathNotation $required_path_val)" # possible values:
      # 'relative to /'   'equivalent to /'   'relative to ../'  'equivalent to ../'
      # 'relative to ./'  'equivalent to ./'  'relative to name'   'empty'  (but empty is not possible due to =.+)
      if [[ "${arg:l}" == 'to-proj-'* ]] && [[ $notated_as == *' /' ]] ; then
        echo "$(_S R S)Invalid argument: $required_path_opt=\"$required_path_val\"  Value cannot be absolute path starting /(_S)" >&2 ; return $GDM_ERRORS[invalid_argument]
      elif [[ "${arg:l}" == 'to-fs-'* ]] && [[ $notated_as != *' /' ]] ; then
        echo "$(_S R S)Invalid argument: $required_path_opt=\"$required_path_val\"  Value must be absolute path starting /$(_S)" >&2 ; return $GDM_ERRORS[invalid_argument]
      elif [[ "${arg:l}" == 'to-home-'* ]] && [[ $notated_as != *' /' ]] ; then
        echo "$(_S R S)Invalid argument: $required_path_opt=\"$required_path_val\"  Value must be absolute path starting /$(_S)" >&2 ; return $GDM_ERRORS[invalid_argument]
      fi # there are other checks we could do like making sure not installing as / or ./ but that'll get ironed out later

      # SET OUTPUT VARIABLE: required_path
      local val_target="$required_path_val" ; [[ "${arg:l}" =~ '^to-(proj|fs)-in' ]] && val_target+="/$repo_name"

      if ! required_path="$(abspath $val_target $GDM_PROJ_ROOT 2>&1)" ; then
        echo "$(_S R S)Invalid argument: $required_path_opt=\"$required_path_val\"  $required_path$(_S)" >&2 ; return $GDM_ERRORS[invalid_argument]
      fi

      # CHECK FOR PATH LOCATION ERRORS:
      if [[ -f $val_target ]] || [[ -f $required_path ]] ; then
        echo "$(_S R S)Invalid argument: $required_path_opt=\"$required_path_val\" (path resolves to or includes an existing file) $(_S)" >&2 ; return $GDM_ERRORS[invalid_argument]
      fi
      local target_relto_proj="$(gdm_dirA_relto_B $required_path $GDM_PROJ_ROOT t p)" 
      local target_relto_req="$(gdm_dirA_relto_B $required_path $GDM_PROJ_ROOT/$GDM_REQUIRED t r)"
      if [[ "$target_relto_proj" == 't is p' ]] ; then # possible values:  "t contains p"  "t is contained by p"  "t is p"  "t has no relation to p" 
        echo "$(_S R S)Invalid argument: $required_path_opt=\"$required_path_val\" Value cannot be project root$(_S)" >&2 ; return $GDM_ERRORS[invalid_argument]
      elif [[ "$target_relto_proj" == 't is contained by p' ]] && [[ "${arg:l}" == 'to-fs-'* ]] ; then 
        echo "$(_S R S)Invalid argument: $required_path_opt=\"$required_path_val\" Value cannot be within the project root$(_S)" >&2 ; return $GDM_ERRORS[invalid_argument]
      elif [[ "$target_relto_req" == 't is r' ]] ; then # possible values:  "t contains r"  "t is contained by r"  "t is r"  "t has no relation to p" 
        echo "$(_S R S)Invalid argument: $required_path_opt=\"$required_path_val\" Value cannot be project's $GDM_REQUIRED)$(_S)" >&2 ; return $GDM_ERRORS[invalid_argument]
      elif [[ "$target_relto_req" == 't is contained by r' ]] ; then 
        echo "$(_S R S)Invalid argument: $required_path_opt=\"$required_path_val\" Value cannot be within project's $GDM_REQUIRED)$(_S)" >&2 ; return $GDM_ERRORS[invalid_argument]
      fi

      # SET OUTPUT VARIABLE: to
      local to
      if [[ "${arg:l}" == 'to-fs-'* ]] ; then to="$required_path"
      else # set to to normalized relative path
        if ! to="$(relpath $required_path $GDM_PROJ_ROOT 2>&1)" ; then 
          echo "$(_S R S)Invalid argument: $arg $to$(_S)" >&2 ; return $GDM_ERRORS[invalid_argument]
        fi
      fi
      
      gdm_echoVars $outputVars
      
    fi
  fi
  return 0
}


# TODO: perhaps allow dir/subdir (just prevent starting with ../ ./ or /)
gdm_isNonPathStr() {  # used in  helpers: gdm.parseRequirement  
  # if string contains only . and / characters or it contains any /, it's a path so it fails
  # (whether it exists or not) This also fails if passed string with * or ~ because path expansion
  [[ "$1" =~ '^[.]*$' ]] || test "${1//\//}" != "$1" && return 1 || return 0
}

gdm_pathNotation() {
  # possible outputs:
  #     "relative to /"    "equivalent to /" 
  #     "relative to ../"  "equivalent to ../"
  #     "relative to ./"   "equivalent to ./"
  #     "relative to ~/"   "equivalent to ~/"
  #     "relative to name" "empty"
  if [[ "$1" == '/'* ]] ; then 
    [[ "$1" =~ '^[\/]+$' ]] && echo "equivalent to /" || echo "relative to /"
  elif [[ "$1" == '..'* ]] && [[ "$1" != '...'* ]] ; then
    if [[ "$1" =~ '^\.\.[\/]*$' ]] ;        then echo "equivalent to ../"
    elif [[ "$1" =~ '^\.\.[\/]+[^\/]+' ]] ; then echo "relative to ../" 
    else                                         echo "relative to name"
    fi
  elif [[ "$1" == '.'* ]] ; then
    [[ "$1" =~ '^\.[\/]*$' ]] && echo "equivalent to ./" || echo "relative to ./"
  elif [[ "$1" == '~'* ]] ; then 
    [[ "$1" =~ '^~[\/]*$' ]] && echo "equivalent to ~/" || echo "relative to ~/"
  elif ! [[ -z "$1" ]] ; then  echo "relative to name"
  else echo 'empty'
  fi
}

gdm_multiArgError() { echo "$(_S R S)$1 has multiple $2 specified! $(_S)" >&2 ; return $GDM_ERRORS[invalid_argument] ; }

