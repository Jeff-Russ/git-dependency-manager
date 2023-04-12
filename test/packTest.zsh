



pack(){
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

export WORKING=(strng dq_words sq_words sq_in_dq)
export FAILING=(dq_in_sq escape_dq_in_dq)

tst() {
  unset $WORKING[@]
  unset packed
  pack packed from="$(fnEchoingVars working)"
  typeset -p packed
  echo "strng=$strng"
  echo "dq_words=$dq_words"
  echo "sq_words=$sq_words"
  echo "sq_in_dq=$sq_in_dq"
}

packTest() {
  
  receiver() {
    local assignments="$(fnEchoingVars $@)"

    eval "$assignments" # just for test unless you don't use from=
    typeset -A packed && pack packed $@ # or: pack to=packed $@

    pack packed from="$assignments"
    
    ##### RESULTS OUTPUT #############################################
    typeof packed ; echo ; typeset -p packed ; echo
    for key value in ${(kv)packed}; do
      echo -n "[$key]={$value} "
      # [[ $value == "${(P)key}" ]] && echo PASS || echo FAIL 
      # case $key in
      #   strng) [[ "$value" == "$strng" ]] && echo "$(_S G)PASS$(_S):{$strng}" || echo "FAIL:{$strng}" ; ;;
      #   dq_words) [[ "$value" == "$dq_words" ]] && echo "$(_S G)PASS$(_S):{$dq_words}" || echo "$(_S R)FAIL$(_S):{$dq_words}" ; ;;
      #   sq_words) [[ "$value" == "$sq_words" ]] && echo "$(_S G)PASS$(_S):{$sq_words}" || echo "$(_S R)FAIL$(_S):{$sq_words}" ; ;;
      #   sq_in_dq) [[ "$value" == "$sq_in_dq" ]] && echo "$(_S G)PASS$(_S):{$sq_in_dq}" || echo "$(_S R)FAIL$(_S):{$sq_in_dq}" ; ;;
      #   dq_in_sq) [[ "$value" == 'he said: "HELLO THERE"' ]] && echo "$(_S G)PASS$(_S):{$dq_in_sq}" || echo "$(_S R)FAIL$(_S):{he said: \"HELLO THERE\"}" ; ;;
      #   escape_dq_in_dq) [[ "$value" == "Hes said \"nope\" before" ]] && echo "$(_S G)PASS$(_S):{$escape_dq_in_dq}" || echo "$(_S R)FAIL$(_S):{Hes said \"nope\" before}" ; ;;
      #   *) echo "$(_S Y)ERROR$(_S):key=$key" ; ;;
      # esac
      case $key in
        strng) [[ "$value" == "$strng" ]] && echo "$(_S G)PASS$(_S):{$strng}" || echo "FAIL:{$strng}" ; ;;
        dq_words) [[ "$value" == "$dq_words" ]] && echo "$(_S G)PASS$(_S):{$dq_words}" || echo "$(_S R)FAIL$(_S):{$dq_words}" ; ;;
        sq_words) [[ "$value" == "$sq_words" ]] && echo "$(_S G)PASS$(_S):{$sq_words}" || echo "$(_S R)FAIL$(_S):{$sq_words}" ; ;;
        sq_in_dq) [[ "$value" == "$sq_in_dq" ]] && echo "$(_S G)PASS$(_S):{$sq_in_dq}" || echo "$(_S R)FAIL$(_S):{$sq_in_dq}" ; ;;
        dq_in_sq) [[ "$value" == 'he said: "HELLO THERE"' ]] && echo "$(_S G)PASS$(_S):{$dq_in_sq}" || echo "$(_S R)FAIL$(_S):{he said: \"HELLO THERE\"}" ; ;;
        escape_dq_in_dq) [[ "$value" == "Hes said \"nope\" before" ]] && echo "$(_S G)PASS$(_S):{$escape_dq_in_dq}" || echo "$(_S R)FAIL$(_S):{Hes said \"nope\" before}" ; ;;
        *) echo "$(_S Y)ERROR$(_S):key=$key" ; ;;
      esac
    done

    ##### TEST FOR SET-NESS OF PACKED VARS AS SCALARS #########################################
    echo "\nTEST FOR SET-NESS OF PACKED VARS AS SCALARS"
    for arg in $@ ; do
      echo "$arg=\"${(P)arg}\""
    done
  }

  fnEchoingVars() {
    local strng="string" ; local dq_words="we dq words" ; local sq_words='we sq words' #√
    local sq_in_dq="title says: 'INSERT TITLE'" #√?
    local dq_in_sq='he said: "HELLO THERE"'     # FAILED
    local escape_dq_in_dq="Hes said \"nope\" before"  # FAILED

    local varnames=()
    if (($#==0)) ; then varnames=(strng dq_words sq_words sq_in_dq dq_in_sq escape_dq_in_dq)
    else
      for arg in $@ ; do
        if   [[ $arg == working ]] ; then varnames+=(strng dq_words sq_words sq_in_dq)
        elif [[ $arg == failing ]] ; then varnames+=(dq_in_sq escape_dq_in_dq)
        else  varnames+=($arg) ;
        fi
      done
    fi
    gdm_echoVars --local $varnames[@]
  }


  receiver $varnames[@]
}


########## OLDER EXPERIMENTAL VERSIONS ######################################################################

pack1(){
  # LIMITATIONS:
  #  1) each variable must be a scalar: zsh does not support arrays or associatives nested in associatives
  #  2) string values set in single quotes containing double quotes will be incorrect!
  #  3) string values set in double containing escaped double quotes will be correct but 
  #     loose the double quotes entirely (but perhaps this is not pack1's fault).
  #     NOTE: string values set in double containing single quotes are fine!
  declare -A __map__

  local PACK_MODE="${PACK_MODE:=dq}" 
  
  for varname in $@ ; do
    if [[ $PACK_MODE == cap* ]] ; then
      echo "PACK_MODE=$PACK_MODE" >&2
      local val="$(echo ${(P)varname})" ;
      [[ $PACK_MODE == "cap-dq" ]] && __map__[$varname]="$val" || __map__[$varname]=$val ;
    elif [[ $PACK_MODE == dq ]] ; then
      echo "PACK_MODE=dq" >&2
      __map__[$varname]="${(P)varname}"
    fi
  done
  gdm_mapVal __map__
}

pack1Test() {
  fnEchoingVars() {
    local strng="string" ; local dq_words="we dq words" ; local sq_words='we sq words' #√
    local sq_in_dq="title says: 'INSERT TITLE'" #√?
    local dq_in_sq='he said: "HELLO THERE"'     # FAILED
    local escape_dq_in_dq="Hes said \"nope\" before"  # FAILED
    gdm_echoVars --local $@
  }
  receiver() {
    eval "$(fnEchoingVars $@)" ; eval "local -A map=$(pack1 $@)"
    typeof map ; echo ; typeset -p map ; echo
    for key value in ${(kv)map}; do
      echo -n "[$key]={$value} "
      # [[ $value == "${(P)key}" ]] && echo PASS || echo FAIL 
      case $key in
        strng) [[ "$value" == "$strng" ]] && echo "$(_S G)PASS$(_S):{$strng}" || echo "FAIL:{$strng}" ; ;;
        dq_words) [[ "$value" == "$dq_words" ]] && echo "$(_S G)PASS$(_S):{$dq_words}" || echo "$(_S R)FAIL$(_S):{$dq_words}" ; ;;
        sq_words) [[ "$value" == "$sq_words" ]] && echo "$(_S G)PASS$(_S):{$sq_words}" || echo "$(_S R)FAIL$(_S):{$sq_words}" ; ;;
        sq_in_dq) [[ "$value" == "$sq_in_dq" ]] && echo "$(_S G)PASS$(_S):{$sq_in_dq}" || echo "$(_S R)FAIL$(_S):{$sq_in_dq}" ; ;;
        dq_in_sq) [[ "$value" == 'he said: "HELLO THERE"' ]] && echo "$(_S G)PASS$(_S):{$dq_in_sq}" || echo "$(_S R)FAIL$(_S):{he said: \"HELLO THERE\"}" ; ;;
        escape_dq_in_dq) [[ "$value" == "Hes said \"nope\" before" ]] && echo "$(_S G)PASS$(_S):{$escape_dq_in_dq}" || echo "$(_S R)FAIL$(_S):{Hes said \"nope\" before}" ; ;;
        *) echo "$(_S Y)ERROR$(_S):key=$key" ; ;;
      esac
    done
  }
  local varnames=()
  if (($#==0)) ; then varnames=(strng dq_words sq_words sq_in_dq dq_in_sq escape_dq_in_dq)
  else
    for arg in $@ ; do
      if   [[ $arg == working ]] ; then varnames+=(strng dq_words sq_words sq_in_dq)
      elif [[ $arg == failing ]] ; then varnames+=(dq_in_sq escape_dq_in_dq)
      else  varnames+=($arg) ;
      fi
    done
  fi
  receiver $varnames[@]
}

# pack(){
#   # pack accepts variable names as arguments 
#   # LIMITATIONS:
#   #  1) each variable must be a scalar: zsh does not support arrays or associatives nested in associatives
#   #  2) string values set in single quotes containing double quotes will be incorrect!
#   #  3) string values set in double containing escaped double quotes will be correct but 
#   #     loose the double quotes entirely (but perhaps this is not pack's fault).
#   #     NOTE: string values set in double containing single quotes are fine!
#   local mapname="$1" ; shift

#   if ! [[ "$(gdm_typeof $mapname)" =~ 'association' ]] ; then
#     echo "ERROR in $0: $mapname is not of type association" >&2 ;return 1
#   fi
  
#   declare -A map
#   for varname in $@ ; do map[$varname]="${(P)varname}" ; done
  

 
# }


copyHashTest() { # https://stackoverflow.com/questions/19284296/how-to-assign-an-associative-array-to-another-variable-in-zsh
  declare -A original=( [another]='a value' [dq_in_sq]='he said: HELLO' )

  declare -A other
  set -A other ${(kv)original}
  typeset -p other

  echo

  declare -A copy
  local mapname=copy
  eval "set -A $copyname \${(kv)original}"
  typeset -p copy

  echo

  typeset -A new 
  new=("${(@fkv)original}")
  typeset -p new
}

