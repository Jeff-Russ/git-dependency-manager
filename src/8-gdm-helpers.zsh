gdm_dirA_relto_B() { #( whether either exist or not) checks if 
  # 'dirA contains B' OR 'dirA is contained by B' OR 'dirA is B' OR "dirA has no relation to B"
  # Recomended if arg paths don't exist: pass args though absolute function first
  local dirA B
  local dirA='dirA' ; ! [[ -z "$3" ]] && dirA="$3"
  local B='B'       ; ! [[ -z "$4" ]] && B="$4"
  if [[ "${2:a}" == "${1:a}" ]] ; then echo "$dirA is $B"
  elif [[ "${2:a}" == "${1:a}"* ]] ; then echo "$dirA contains $B"
  elif [[ "${1:a}" == "${2:a}"* ]] ; then echo "$dirA is contained by $B"
  else echo "$dirA has no relation to $B"
  fi
}

gdm_mvSubdirsTo() {
  # Description
  #   Moves subdirectories with a given name at any depth within some directory to another, 
  #   creating any intermediary directories if needed. By default any subdirectory matching the provided
  #   name of any depth will be moved. This can be changed by passing find options: -mindepth -maxdepth.
  # Usage
  #  gdm_mvSubdirsTo <current_parent_dir> <subdir_name> <new_parent_dir> 
  #    where options for find command with integers (which preceed integer arguments) can be passed anywhere
  #    and additional find option may be passed after the final required argument: <new_parent_dir>.
  local cur_parent subdir_name new_parent
  local ordered_argvars=(cur_parent subdir_name new_parent) ; local next_argvar_i=1
  local find_flags_w_n=( -mindepth -maxdepth -depth -links -inum -Bmin) local find_args=()
  local arg_i=1
  while ((arg_i<=$#@)) ; do
    if ((arg_i<$#@)) && [[ "$@[((arg_i+1))]" =~ '^[0-9]$' ]] && (($find_flags_w_n[(Ie)$@[$arg_i]])) ; then
      find_args+=("$@[$arg_i]" "$@[((arg_i+1))]") ; ((arg_i+=1)) # an extra increment
    elif ((next_argvar_i<=$#ordered_argvars)) ; then
      eval "$ordered_argvars[$next_argvar_i]=\"$@[$arg_i]\"" ; ((next_argvar_i++))
    else find_args+=("$@[$arg_i]") # interpret args beyond required as args for find
    fi
    ((arg_i++))
  done

  local subdirs_rel_parent=("${(@f)$(cd "$cur_parent" && find . -type d $find_args -name "$subdir_name")}")
  subdirs_rel_parent=($subdirs_rel_parent) # remove empty element

  for i in {1..$#subdirs_rel_parent} ; do
    if ! [[ -z "$subdirs_rel_parent[$i]" ]] ; then
      local intermediary_path="${subdirs_rel_parent[$i]:h}"
      if ! [[ -z "$intermediary_path" ]] ; then
        mkdir -p "$new_parent/$intermediary_path"
        mv "$cur_parent/$subdirs_rel_parent[$i]" "$new_parent/$intermediary_path"
      else
        mv "$cur_parent/$subdirs_rel_parent[$i]" "$new_parent" 
      fi
    fi
  done
}

gdm_getInode() {
  local cap
  if [[ -d "$1" ]] ; then cap="$(ls -id $1)" || return $?
  else                    cap="$(ls -i $1)"  || return $?
  fi
  echo $cap | awk '{print $1;}' || return $?
}

gdm_hardLinkCount() { echo $(($(ls -liUT "$1" | awk '{print $3}')-1)) ; }

function _S() { # S for STYLE
  # EXAMPLES: echo -e "$(_S R E)red italics$(_S)" ; echo -e "$(_S R E)ERROR: $(_S E)just italics\! $(_S)"
  # [S]trong(bold), [D]im, [E]mphasis(italic), [U]nderline, [F]Flash(blink). [6]?, 
  # [I]nvertFG/BG-colors, [R]ed, [G]reen, [Y]ellow, [G]reen, [B]lue, [M]agenta, [C]yan
  declare -A cLU=( [S]=1 [D]=2 [E]=3 [U]=4 [F]=5 [6]=6 [I]=7 [R]=31 [G]=32 [Y]=33 [B]=34 [M]=35 [C]=36 ) # codeLookUp
  local seq="\e[0m"
  [ $# -eq 0 ] && print "$seq" && return 0;
  seq="${seq}\e["
  for var in "$@" ; do seq="${seq}${cLU[$var]};" ; done
  print "${seq[1,-2]}m" # remove last ; and append m
}

gdm_ask () {
  if [ "$1" = "--help" ] ; then
    ask --help
    return 0
  fi
  while true ; do
    local prmpt="y/n" ; local deflt= ; local reply= 
    if [ "${2:-}" = "Y" ] ; then prmpt="Y/n" ; deflt="Y" 
    elif [ "${2:-}" = "N" ] ; then prmpt="y/N" ;  deflt="N" 
    fi
    read -k "reply?$1 [$prmpt] " < /dev/tty
    if [[ $reply = *[$' \t\n']* ]]
    then reply=$deflt 
    else printf "\n"
    fi
    case "$reply" in
      (Y* | y*) return 0 ;;
      (N* | n*) return 1 ;;
      (*) printf "Invalid reply!\n" ;;
    esac
  done
}

gdm_typeof() {
  if [[ -z "$1" ]] || [[ "$1" == --help ]] ; then
    cat << 'USAGEDOC'
    gdm_typeof accepts a string which could be something executable, a file, variable, reserved word or hash
    and outputs what it is. The output could be:
      'executable:builtin'
      'executable:command'
      'executable:function' 
      'executable:file'
      'file'                 # not executable but still could be source(able) code of some sort
      'hashed'               # assumed to not be executable
      'reserved'             # assumed to not be executable
      'variable:scalar'*     
      'variable:array'*
      'variable:association'*
                              # (no output) indicates input is not any of the above
    NOTE that there are more variable types than those listed above (as hinted at with the * wildcard)
    Beside the 'file' 'hashed' and 'reserved' outputs, 
      all executable types are prepended with 'executable:' and 
      all that are variables with 'variable:scalar' 
    Checks for non-variable types are performed first and the checks for variable are performed, even if the first check
    had a result. Therefore it is possible to have MORE THAN ONE RESULT, such as 'executable:function variable:scalar-export'
USAGEDOC
    if [[ "$1" == --help ]] ; then return 0 ; else return 1 ; fi
  fi

  local result=""
	local cap="$(whence -w "$1" 2>/dev/null)"  # `-w` show if alias,  builtin,  command,  function, hashed, reserved or none
  local whenceType="$(echo "$cap" | awk '{print $NF}')"
  case $whenceType in
    function|builtin) 
      result="executable:$whenceType"
      ;;
    command)
      if [[ -f "$1" ]] && [[ -x "$1" ]] ; then result="executable:file" ; else result="executable:command" ; fi
      ;;
    alias)
      local verbose first_word_of_alias_val
      verbose="$(whence -v "$1")"
      first_word_of_alias_val="$(echo  ${verbose#* alias for } | head -n1 | awk '{print $1;}')"
      if [[ "$first_word_of_alias_val" == "$verbose" ]] ; then result=alias
      elif [[ "$(gdm_typeof $first_word_of_alias_val 2>/dev/null)" =~ ^'executable' ]] ; then result='executable:alias'
      else result=alias
      fi
      ;;
    *)  # hashed, reserved or none
      if [[ "$whenceType" == 'none' ]] ; then
        if [[ -f "$1" ]] ; then 
          if [[ -x "$1" ]] ; then result='executable:file' ; else result='file' ; fi
        fi
      else result="$whenceType"
      fi
      ;; 
  esac

  if eval "(( \${+$1} ))" 2>/dev/null ; then  # if a variable... get type
    # the following two lines are, if we knew the var was called var, equiv to: print -rl -- ${(t)var}
    local operand='${(t)'"$1"'}'
    local vartype="$(eval "print -rl -- $operand" 2>/dev/null)"
    if ! [[ -z "$vartype" ]] ; then
      if [[ -z "$result" ]] ; then result="variable:$vartype"
      else result="$result variable:$vartype"
      fi
    fi
  fi
  [[ -z "$result" ]] && return 1
  echo "$result"
  return 0
}

gdm_quote() {
  # takes one string variable name and outputs how to quote it as one of the following:
  # "none" "double" "escaped double" "single" "escaped single"
  # or... if none worked, just returns 1 without outputs
  local varname="$1"
  if [[ -z "${(P)varname}" ]] ; then print -n "'${(P)varname}'" ; return 1 ; fi # single quotes for empty
  
  local arr=()
  eval "arr=(${(P)varname})" ; if (($#arr==1)) ; then
    print -n "${(P)varname}" ;
    # echo "\n$varname gets no quotes" >&2 #TEST
    return 0 ; fi # no quotes
  eval "arr=(\"${(P)varname}\")" ; if (($#arr==1)) ; then
    print -n "\"${(P)varname}\"" ;
    # echo "\n$varname gets escaped double" >&2 #TEST
    return 0 ; fi # escaped double
  eval "arr=('${(P)varname}')" ;   if (($#arr==1)) ; then
    print -n "'${(P)varname}'" ;
    # echo "\n$varname gets single" >&2 #TEST
    return 0 ; fi # single
  eval 'arr=("'${(P)varname}'")' ; if (($#arr==1)) ; then
    print -n '"'${(P)varname}'"' ;
    # echo "\n$varname gets double" >&2 #TEST
    return 0 ; fi # double
  eval "arr=(\'${(P)varname}\')" ; if (($#arr==1)) ; then
    print -n "\'${(P)varname}\'" ;
    # echo "\n$varname gets escaped single" >&2 #TEST
    return 0 ; fi # escaped single
  # echo "still here!!" >&2
  return 1
}

gdm_varsToMapBody() {
  # Input:  each arg should be a variable name
  # Output: the body of an associative array (stuff between parens), assigning each
  #         variable name (as associative key) to each variable name's value (as associative value.)
  # Usage: 
  #       eval "declare -A hash=( $(gdm_varsToMapBody var1 var3 var3) )"
  #  or
  #       local mapbody="$(gdm_varsToMapBody var1 var3 var3)"
  #       eval "declare -A hash=( \"$mapbody\" )"  # this seem to require the \" \"
  ! (($#)) && return 0 ;
  # print -n "( "
  for varname in $@ ; do print -n "[$varname]=$(gdm_quote $varname) " ; done
  # print -n ")"
}

gdm_arrayLacksDups() {
  # accepts an array name and returns number of duplicates, so if array=(a a b b b c)
  # gdm_arrayLacksDups array    # would return 3 (the 1 extra a + 2 extra b)
  eval 'actualsize=$#'$1
  eval 'setsize=${#${(u)'$1'}}'
  return $((actualsize-setsize))
}


gdm_echoMapBodyToVars() {
  # Input: The body of an associative array (stuff between parens, i.e. the output from gdm_varsToMapBody)
  # Output: A string assigning variables, each named as the key in the associative array, to their values.
  # LIMITATIONS: This function expects all associative array values to be scalars. Keys must also be valid variable names.
  # Options: Each flag option should be passed before the main input (body of an associative array)
  #         --local               # declares each as local
  #         --suffix=*            # sets string to place between each assignment (default is --suffix=" ; \n")
  #         --require="key1 key2"
  #         --require="$an_array" # Makes the function fail unless all required keys are found.
  #         --allow-any=false     # Makes the function fail if any keys beside required are found
  #         --allow-any=true
  #         --allow-any           # Allows any key beside required
  #         --allow="key3 key4"
  #         --allow="$an_array"   # Makes the function fail if any key beside allow (and required, if provided) is found.

  local decl=""
  local suffix=" ; \n"
  local required=() # array of required keys/variables
  local allow_any=true  # true means allow any key. false mean only allow required and allowed.
  local allowed=() # array of allowed keys/variables

  while [[ "$1" =~ '^--local(=true)?$' ]] || [[ "$1" =~ '^--(suffix=.+|require=.+|allow-any|allow=.+)' ]] ; do
    if [[ "$1" == '--local'* ]] ; then decl="local "
    elif  [[ "$1" =~ '^--suffix=.+$' ]] ; then suffix="${1#*=}" 
    elif [[ "$1" =~ '^--require=.+$' ]] ; then eval "required=( ${1#*=} )"
    elif [[ "$1" =~ '^--allow-any(=true)?$' ]] ; then allow_any=true
    elif [[ "$1" =~ '^--allow-any=false$' ]] ; then allow_any=false
    elif [[ "$1" =~ '^--allow=.+$' ]] ; then eval "allowed=( ${1#*=} )"
    fi
    shift
  done
  
  if ! (($#)) ; then echo "$(_S Y)WARNING: $0 received no arguments! $(_S)" >&2 ; return 1 ; fi

  local map_body="$1" ; shift
  # echo "map_body=$map_body" >&2 #TEST
  if ! eval "declare -A temp_map=( $map_body )" ; then return 2 ; fi

  if (($#required)) ; then
    local missing=()
    for key in $required ; do ! [[ $temp_map[(Ie)$key] ]] && missing+=($key) ; done
    if (($#missing)) ; then echo "The following are keys are required weren't found: $missing" >&2 ; return 3 ; fi
  fi
  if ! $allow_any ; then
    local not_allowed=()
    allowed+=($required[@])
    for key in "${(@k)temp_map}"; do ! (($allowed[(Ie)$key])) && not_allowed+=($key) ; done
    if (($#not_allowed)) ; then echo "The following are keys are not allowed: $not_allowed" >&2 ; return 4 ; fi
  fi

  for key val in "${(@kv)temp_map}" ; do print -n -- "$decl$key=$(gdm_quote val)$suffix" ; done
  unset temp_map # or maybe keep it? it seem to carry up to caller's scope
}

gdm_mapBody() { # (currently not used)
  ! (($#)) && return 0 ;
  local hash_name="$1"
  # print -n "( "
  eval "for key val in \"\${(@kv)$hash_name}\"; do print -n \"[\$key]=\$(gdm_quote val) \" ; done"
  # print -n ")"
}


gdm_echoVars() {
  # gdm_echoVars accepts the the following, outputing the following by default:
  # variable names
  #    "<name>=\"<value>\" ; \n"                             # for each that is a scalar
  #    "typeset <flags> <name>=([k1]=v [k2]='v 2' ...) ; \n" # for each hashes (associative)
  #    "<name>=("v1" "v 2" ...) ; \n"                        # for each array
  # args that begin with '#' or those that contain <valid_varname>=<somevalue>
  #    "$arg\n"              # to output comments direct assignments of variable to some other value
  # gdm_echoVars accepts the following option applying to all subsequent arguments:
  #    --local
  #    --local=true   # prepends 'local ' for scalars, arrays, and sets <flags> to -A for hashes no effect on assignments
  #    --local=false  # resets to default (no prepending, <flags> as detected for hashes)
  #    --append-array
  #    --append-array=true   # assign arrays with +=( Note: this will force --local to false for arrays
  #    --append-array=false  # resets to default: assigning with =(
  #    --append-array|--append-array=true|--append-array=false    # same but for  hashes (associative)
  #    --suffix=" ; \n"     # This is the default, as seen appended to out of each variable but can be bypassed:
  #    --suffix=" ; "       # This would output inline assignments (does not apply to comments which always have newline)
  #    --suffix=" "         # BEWARE: these would eval to an error but it suitable for parameterizing and forwarding to commands

  local append_array=false
  local append_hash=false
  local decl=""
  local suffix=" ; \n"

  local output=""
  
  local argnum=0
  for arg in $@ ; do ((argnum++))
    if ((argnum==$#)) && [[ "$suffix[-2]" == '\' ]] && [[ "$suffix[-1]" == "n" ]] ; then suffix="$suffix[1,-3]" ; fi
    
    # options:
    if   [[ "$arg" =~ '^--local(=true)?$' ]] ; then decl="local " 
    elif [[ "$arg" == --local=false ]] ;       then previx=""
    elif [[ "$arg" =~ '^--append-array(=true)?$' ]] ; then append_array=true # overrides --local
    elif [[ "$arg" == --append-array=false ]] ;       then append_array=false
    elif [[ "$arg" =~ '^--append-hash(=true)?$' ]] ; then append_hash=true # overrides --local
    elif [[ "$arg" == --append-hash=false ]] ;       then append_hash=false
    elif [[ "$arg" =~ '^--suffix=.+$' ]] ; then suffix="${arg#*=}" 

    # custom bypasses:
    elif [[ "$arg" =~ '^[ ]*#' ]] ; then  echo "$arg" # echo comment with newline

    elif [[ "$arg" =~ '^[a-zA-Z_]+[a-zA-Z0-9_]*([+])?=' ]] ; then echo "$arg$suffix" # custom variable name with assignment
    #TODO: or this?
    # elif [[ "$arg" =~ '^[a-zA-Z_]+[a-zA-Z0-9_]*([+])?=' ]] ; then echo "$arg" # custom variable name with assignment

    # arg is a variable name so echo it according to options
    elif [[ -n "${(P)arg+set}" ]] ; then  
      local varname="$arg"

      if [[ "$(gdm_typeof $varname)" =~ 'array' ]] ; then
        if $append_array ; then output+="$varname+=($(print -- \"${^${(P)varname}}\"))$suffix"
        else output+="$decl$varname=($(print -- \"${^${(P)varname}}\"))$suffix" 
        fi
      
      elif [[ "$(gdm_typeof $varname)" =~ 'association' ]] ; then
        if $append_hash ; then output+="$varname+=$(gdm_mapVal $varname) ; "
        elif [[ -z "$decl" ]] ; then output+="$(typeset -p $varname)$suffix"
        else output+="declare -A $varname=$(gdm_mapVal $varname)$suffix"
        fi

      else

        output+="$decl${varname}=\"${(P)varname}\"$suffix"
      fi

    # Another custom bypass
    elif [[ "$arg" =~ '^[a-zA-Z_]+[a-zA-Z0-9_]$' ]] ; then output+="$decl$arg=\"\"$suffix"  # just an (unset) variable name

    else echo "Warning: $0 was passed something it does not recognize:\"$arg\"" >&2 # perhaps a bad idea
    fi
  done
  print -n "$output"
}

gdm_echoAndExec() {
  local err_code err_cap 
  local newline_patt="$(echo '.*'; echo '.*')"
  local abbreviate=true
  if [[ "$1" == '--abbreviate=false' ]] ; then 
    abbreviate=false ; shift
  elif  [[ "$1" == '--abbreviate=true' ]] || [[ "$1" == '--abbreviate' ]] ; then 
    abbreviate=true ; shift
  fi
  local cmd="$@"
  if $abbreviate ; then 
    local append="" ; [[ "$cmd" =~ "$newline_patt$" ]] && append="#..."
    print -- "$(_S B)$(echo "${cmd//$GDM_REGISTRY/\$GDM_REGISTRY}" | head -1)$(_S)$append" >&2 
  else
    print -- "$(_S B)${cmd//$GDM_REGISTRY/\$GDM_REGISTRY}" >&2 
  fi
  #TODO: FIX BUG IN ABOVE WHEN cmd='cp -al "/Users/jeffreyruss/.shell_extensions/GIT_REPO_DEPS/git-dependency-manager/test/gdm_require/github.com/juce-framework/juce/221d1aa_setup-fa175323" "/Users/jeffreyruss/.shell_extensions/GIT_REPO_DEPS/git-dependency-manager/test/gdm_required/juce"'
  
  err_cap="$(eval "$@" 1>/dev/null 2>&1)" ; err_code=$?
  if ((err_code)) ; then echo "$err_cap$(_S R S)Terminating due to previous command returning error code $err_code$(_S)" >&2 ; return $err_code ; fi
}

gdm_mapDecl() { local result ; result="$(typeset -p "$1")" || return $? ; } # unused

# $1 is name of associative array, $1 is key found in it
gdm_keyOfMapWithVal() { local evalable="\${(k)$1[(r)$2]}" ; eval "echo $evalable" || return $? ; }

gdm_mapVal() { echo -n "(${"$(typeset -p "$1" 2>/dev/null)"#*'=('}" ; } # prepend ( to the value after =(


gdm_pack(){
  # pack assigns key/value pairs to an associative array from any number of variable's names/values
  # pack accepts the name of a map (an associative array, optionally prepended with to= -to= or --to=) as first argument 
  # (which, if it is not set, is declared by pack as a global variable) followed by either:
  #     variable names as additional args OR      NOTE: these variables must be set in pack's caller (local is okay) 
  #     as string assigning variables to values   NOTE: evaled in pack but as local so not assigned in caller's scope 
  # USAGE 
  #   FROM VARIABLE NAMES:
  #    local assignments="$(fnEchoingVars $varnames[@])" 
  #    eval $assignments                                # NECESSARY or pack won't have values!
  #    typeset -A packed                                # Skip this and you'll have: typeset -g -A packed
  #    pack packed $varnames[@] 
  #   FROM VARIABLE ASSIGNMENTS STRING:
  #    typeset -A packed                                # Skip this and you'll have: typeset -g -A packed
  #    pack packed from="$(fnEchoingVars $varnames[@])"
  # LIMITATIONS:
  #  1) each variable must be a scalar: zsh does not support arrays or associatives nested in associatives
  #  2) string values set in single quotes containing double quotes will be incorrect!
  #  3) string values set in double containing escaped double quotes will be correct but 
  #     loose the double quotes entirely (but perhaps this is not pack's fault).
  #     NOTE: string values set in double containing single quotes are fine!
  local mapname="${1#*=}" ; shift
  ! [[ "$(gdm_typeof $mapname)" =~ 'association' ]] && typeset -gA $mapname
  local varnames=()
  if [[ "$1" =~ '^[-]{0,2}from=.+' ]] ; then
    # MODE: pack from assignments string: we'll eval it and grab out variable names to use as keys
    local evalable_assignments="${1#*=}"
    local _lines=("${(@f)$(echo $evalable_assignments)}");
    local linenum=0
    for line in $_lines ; do ((linenum++))
      local statements=(${(s/;/)line})
      for statement in $statements ; do
        local varname="${${statement%%=*}##* }"  # (unnamed is) statement before first = and varname is unnamed after last space
        if ! [[ -z "$varname" ]] ;  then
          [[ "$statement"  =~ '^( *local | *declare | *typeset)' ]] && eval "$statement" || eval "local $statement"
          varnames+=("$varname") # varname could be unset in this scope but it will be set to "" with stderr later in this func
        fi
      done
    done
  else varnames=($@) # MODE: passed variable names: We'll (hopefully) have access to their values
  fi

  local subs_eq_vals=()
  for varname in $varnames ; do
    ! [[ -v $varname ]] && echo "$(_S Y)WARNING: $0 cannot determine value of $varname$(_S)" >&2 
    subs_eq_vals+=("[$varname]=\"${(P)varname}\" ;")
  done
  eval "$(print -l $mapname${^subs_eq_vals})"
}


gdm_unpack() {
  if (($#<3)) ; then echo "$0 requires at least 3 args: name of associative array, --get.*, --all-a|<key>..." >&2 ; return 3 ; fi

  # local map_decl="$(typeset -p "$1")" ; shift #old
  local map_decl ; ! map_decl="$(typeset -p "$1")" 2>/dev/null && map_decl="$1" ; shift #new
  
  local valdelim='=('
  local map ; eval "${$(echo "${map_decl%%$valdelim*}" | xargs)% *} map$valdelim${map_decl#*$valdelim}"
  local prepend=""
  if [[ "$1" == '--get' ]] ; then 
  elif [[ "$1" =~ '^(--get-local|--local)$' ]] ; then prepend="local " ; 
  elif [[ "$1" =~ '^--local=.+' ]] ; then prepend="local ${1[9,-1]}" ; 
  elif [[ "$1" == '--get' ]] ; then prepend="" ;
  elif [[ "$1" =~ '^--get=.+' ]] ; then prepend="${1[7,-1]}" ;
  else echo "$0 got invalid 2nd arg: \"$1\"" >&2 ; return 2
  fi
  # echo "prepend is \"$prepend\""
  shift
  if [[ "$1" =~ '^(-a|--all)$' ]] ; then
    for k v in ${(kv)map} ; do echo "$prepend$k=\"$v\"" ; done
  else for k in $@ ; do  echo "$prepend$k=\"$map[$k]\"" ; done
  fi
}

# ! which validpath 2>/dev/null 1>&2 && 
# function validpath() {
#   local path_segs=( ${(s:/:)wd} ) 
#   while [[ -d "$nonexist" ]] && ((i<=$#path_segs)) ; do nonexist+="/${path_segs[$((i++))]}" ;
# }

# ! which showErroneousNonDirInPath 2>/dev/null 1>&2 && #TODO: uncomment this line


# ! which abspath 2>/dev/null 1>&2 && #TODO: uncomment this line
function abspath(){ 
  if [[ -z "$1" ]] || (($#>2)) || [[ "$1" == --help ]] ; then
    print "abspath outputs an absolute path from \$1, relative path (which need not exist)" >&2
    print "        that is relative to a path \$2 (which also need not exist).\nUsage:" >&2
    print "  abspath \$relpath [\$wd_of_relpath] # where the 2nd argument defaults to \$PWD\nCaveats:" >&2
    print "  If the second argument is a relative path, it is assumed to be relative to \$PWD." >&2
    print "Error Conditions (returning 1 with stderr similar to that from mkdir: 'Error: WD|WD contains|path contains \$location: Not a directory' ):"
    print "  1) Either argument resolves to a path containing any parent segments existing as non-directories" >&2
    print "  2) The second argument resolves to a path containing any parent segments which cannot be modified" >&2
    [[ "$1" != --help ]] && return 1 || return 0
  fi

  local target="$1"
  local wd="${2:a}" # local wd="$2" ; [[ "${wd[-1]}" == '/' ]] && wd="${2[1,-2]}"

  function showErroneousNonDirInAbsPath() {
    # Example: showErroneousNonDirInPath /User/person/FILE/place # returns 1 with stdout: /User/person/FILE
    # IF (abs path, existing or not) argument contains any parent segments existing as non-directories:
    #   returns 1 with stdout (NOT stderr) of path up to and including the non-directory part
    # Else, no output and return is 0. 
    [[ -e "$1" ]] && return 0
    local target="$1" 
    while [[ "$target" != / ]] && ! [[ -e "$target" ]] ; do target="$target:h" ; done
    [[ -d "$target" ]] && return 0
    print "$target" ; return 1
  }

  local result non_dir

  if [[ -z "$wd" ]] || [[ "$wd" == "$PWD" ]] || [[ "$wd" == '/' ]]  ; then
    result="${target:a}" # make absolute path via $PWD or /
    
  elif [[ -e "$wd" ]] ; then
    ! [[ -d "$wd" ]] && { print "Error: WD $wd: Not a directory" >&2 ; return 1 ; }
    result="(cd $wd && print ${target:a})" || return $? # output absolute path from path relative to existing path
  else
    # else make absolute path from a path relative to a non-existing working dir by temporarily creating the working dir
    local path_segs=( ${(s:/:)wd} )    # split by '/' delimiter (lack of quotes around expansion prevents empty elements).
    local nonexist="/${path_segs[1]}"  # This will be the top (containing) directory to not exist i.e. the one to delete when 
    local i=2                          # cleaning up. Additional segments beyond nonexist, if any, won't exist either.
    while [[ -d "$nonexist" ]] && ((i<=$#path_segs)) ; do nonexist+="/${path_segs[$((i++))]}" ; done # accum up to non-existent segment
    [[ -e "$nonexist" ]] && { print "Error: WD contains $nonexist: Not a directory" >&2 ; return 1 ; }
    mkdir -p "$wd" || return $?            # Make temp directory(s). This will fail if, for example, making the path effectively adds a new user $HOME
    result="(cd $wd && print ${target:a})" # Make absolute path from path relative to temp path
    rm -rf "$nonexist"                     # Clean up temp directory(s) by removing them.
  fi

  if ! non_dir="$(showErroneousNonDirInAbsPath $result)" ; then
    print "Error: path contains $non_dir: Not a directory" >&2 ; return 1 ;
  else
    print "$result"
    return 0
  fi
}


# ! which relpath 2>/dev/null 1>&2 &&  #TODO: uncomment this line
function relpath(){
  # based on: https://stackoverflow.com/a/14914070
  # NOTE: requires abspath and, as such, errors output the same stderr with same return of 1
  if [[ -z "$1" ]] || (($#>2)) || [[ "$1" == --help ]] ; then
    echo "$0 requires one or two arguments: a path string to be converted to a path" >&2
    echo "relative to the second argument or relative to \$PWD if no second argument given." >&2
    [[ "$1" != --help ]] && return 1 || return 0
  fi

  local target="$1"
  local current="$2"
  if [[ -z "$current" ]] ; then current="$PWD"
  elif [[ -e "$current" ]] ; then current="${current:a}"
  else
    # non-existent absolute path from current assuming current is relative to $PWD:
    if ! current="$(abspath $current 2>&1)" ; then print $current >&2 ; return 1 ; fi # (current is stderr if abspath fails)
    # non-existent absolute path from target assuming current is relative non-existent current:
    if ! target="$(abspath $target $current 2>&1)" ; then print $target >&2 ; return 1 ; fi # (current is stderr if abspath fails)
  fi

  local appendix=${target#/} # set appendix is target without any leading /
  local relative=''

  while appendix=${target#$current/} # (do always) appendix is set to target w/o any $current/ prepended to it
    [[ $current != '/' ]] && [[ $appendix = $target ]] ; do 
    if [[ $current = $appendix ]]; then
      relative=${relative:-.} # if relative is null, set it to '.'
      print ${relative#/} # relative without any leading /
      return 0
    fi
    current=${current%/*} # remove the last /* from current
    relative="$relative${relative:+/}.." # append to relative: '/' but only if relative is non-null + '..'
  done
  relative+=${relative:+${appendix:+/}}${appendix#/} # append to relative: '/' if relative AND appendix are non-null + $appendix w/o any leading /
  print $relative
}


gdm_autoRename() {
  # gdm_autoRename to automatically prevent any overwrites in renaming or moving a file or directory
  #                by automatically generating a new name, without output of the new name if non-failing.
  # Usage:
  #    gdm_autoRename [--mv|--cp] $dir_or_file [$rename_tmpl] [$rename_numered_tmpl]
  # Args:
  #    --mv | --cp          (optional) defaults to --mv (rename) whereas --cp renames, keeping original
  #    $dir_or_file         (required) existing file or directory as a relative or absolute path
  #    $rename_tmpl         (optional) string template which can reference the original filename (w/o ext) as $name
  #    $rename_numered_tmpl (optional) extra template used when first results in existing file which also 
  #                         can reverence the original (w/o ext) as $name but also MUST reference $n, which 
  #                         will be incremented until resulting string does not exist in the filesyatem
  # Examples:
  #    gdm_autoRename --mv item.ext
  #    gdm_autoRename item.ext
  #                                       item.ext (a file or directory) is renamed (moved) to 
  #                                       item-backup.ext or, if that exists, item-backup-2.ext or, 
  #                                       if that exists, item-backup-3.ext etc
  #    gdm_autoRename --cp item.ext 
  #                                       Same as previous but original is kept 
  #    gdm_autoRename --mv item.ext '$name.bak'
  #    gdm_autoRename item.ext '$name.bak'
  #                                      Renamed to item.bak.ext or, if that exists, item.bak-2.ext, etc
  #    gdm_autoRename --cp item.ext '$name.bak'
  #                                      Same as previous but original is kept
  #    gdm_autoRename --mv item.ext '${name}_bak' '${name}_bak($n)'
  #    gdm_autoRename item.ext '${name}_bak' '${name}_bak($n)'
  #                                      Renamed to item_bak.ext or, if that exists, item_bak(2).ext, etc
  #    gdm_autoRename --cp item.ext '${name}_bak' '${name}_bak($n)'
  #                                      Same as previous but original is kept

  local mode=mv
  while [[ "$1" =~ '^--(mv|cp)$' ]] ; do mode="${1[3,-1]}" ; shift ; done

  ! [[ -e "$1" ]] && return 1
  local fullpath="${1:a}" 
  local parent="${fullpath:h}" ; [[ "$parent[-1]" != '/' ]] && parent="$parent/"
  local name="${fullpath:t:r}" ; 
  local ext="" ; ! [[ -z "${fullpath:e}" ]] && ext=".${fullpath:e}"

  if [[ -z "$2" ]] ; then  # default is to append (before ext)  "-backup" or, if that exists, "-backup-2", then "-backup-3"
    $0.append_tmpl() { ((n<2)) && echo "$parent$name-backup$ext" || echo "$parent$name-backup-$n$ext" ; }

  else # custom renaming template(s) provided
    local tmpl_a="$2"  # a template string referencing the original filename (w/o ext) as $name
    if [[ -z "$3" ]] ; then
      $0.append_tmpl() { ((n<2)) && eval "echo \"$parent$tmpl_a$ext\"" || eval "echo \"$parent$tmpl_a-$n$ext\"" ; }
    else
      local tmpl_b="$3" # a second template string used when first one fails, referencing $n (and also $name as before)
      $0.append_tmpl() { ((n<2)) && eval "echo \"$parent$tmpl_a$ext\"" || eval "echo \"$parent$tmpl_b$ext\"" ; }
    fi
  fi

  local n=1 ; local newpath="$($0.append_tmpl)" # Determine new name using template and, if exists, apply...
  while [[ -e $newpath ]] ; do ((n++)) ; newpath="$($0.append_tmpl)" ; done # incremented n until not existing
  
  local ret=0
  # mv|cp $fullpath/*(DN) $newpath/ # alternative for dirs,
  if [[ "$mode" == mv ]] ; then  mv -f "$fullpath" "$newpath" ; ret=$? # mv files or dirs
  elif [[ -d "$fullpath" ]] ; then cp -rf "$fullpath" "$newpath" ; ret=$? # cp dir
  else cp "$fullpath" "$newpath" ; ret=$? # cp file
  fi
  ((ret==0)) && echo "$newpath"
  return $ret
}
