# TYPICAL USAGE:
#    . ./gdm_parseConfigTest.zsh  gdm_parseConfigResults.txt -li '*'  # or any EXISTING file name
#
# NOTE: gdm_parseConfigResults.txt must be an existing file name
# NOTE: Instead of '*', you can pass $_GDM_ARRAYS which is equivalent as it stores all array names
#       or instead of '*', you can list out just the ones you want as the trailing arguments.
#       or instead of '*', you can provide any regex pattern (each arg is $_GDM_ARRAYS(i)$arg searched)
#
# NOTE: Sourcing is optional but you may want to get arrays exported for you to print on your own like this:
#    . ./gdm_parseConfigTest.zsh ; showArray -li GDM_WORKING_LOCK     # to show in shell instead of file
#
# Or to show all that would go in the file with -li '*', try this:
#    . ./gdm_parseConfigTest.zsh ; showArray -li GDM_WORKING_LOCK


export GDM_REPO_ROOT="${GDM_REPO_ROOT:=${0:a:h:h}}"


. $GDM_REPO_ROOT/run compile as=test ; . $GDM --source 

gdm_parseConfigTest() {
  # to see all:
  #     . ./gdm_parseConfigTest.zsh  gdm_parseConfigResults.txt -li '*'   # or any EXISTING file name
  # -i shows array indices and -l shows them multiline (see showArray def for more info)
  # Sourcing is optional but you may want if didn't target all (with '*' ) so you get 
  # arrays exported for you to print on your own like this:
  #     . ./gdm_parseConfigTest.zsh ; showArray -li GDM_WORKING_LOCK  

  [[ -z $GDM_PROJ_ROOT ]] && GDM_PROJ_ROOT=$PWD ;

  setup_fn() { echo 'setup function' ; }
  
  


  GDM_PROJ_CONFIG_ARRAY=(
    'juce-framework/juce destin=juce-head'                            # config_lock[1] -> config_lock[3] -> config_lock[1]
    'juce-framework/JUCE#6.0.10 destin=invalid-tag setup="setup_fn"'  # config_lock[2] -> insert lock as -> config_lock[2]
    'juce-framework/JUCE#develop destin=juce-dev setup="setup_fn"'    # config_lock[3] -> config_lock[2] -> config_lock[3]
    'juce-framework/JUCE#6.0.0 destin=juce6 setup="setup_fn"'         # config_lock[4] -> insert lock as -> config_lock[4]
  )

  if [[ $1 == 'alt-setup' ]] ; then
    shift
    setup_fn() { echo 'Setup Function' ; }
  fi

  GDM_PROJ_LOCK_ARRAY=(
    "[destin]=juce-removed [remote_url]=https://github.com/juce-framework/juce.git [rev]='' [setup]='' [hash]=69795dc8e589a9eb5df251b6dd994859bf7b3fab [tag]=7.0.5 [branch]=master [rev_is]=branch [setup_hash]='' "
    "[destin]=juce-dev [remote_url]=https://github.com/juce-framework/juce.git [rev]=develop [setup]=setup_fn [hash]=8ed3618e12230ad8563098e1f17575239497b127 [tag]='' [branch]=develop [rev_is]=branch [setup_hash]=23beb8ce "
    "[destin]=juce-head [remote_url]=https://github.com/juce-framework/juce.git [rev]='' [setup]='' [hash]=69795dc8e589a9eb5df251b6dd994859bf7b3fab [tag]=7.0.5 [branch]=master [rev_is]=branch [setup_hash]='' "
  )


  export _GDM_ARRAYS=(
    GDM_PROJ_CONFIG_ARRAY GDM_PROJ_LOCK_ARRAY # never altered copies of the actual file's arrays
    config_destinations GDM_WORKING_CONFIG_QUICKVARS # set by iterating config
    config_i_to_lock_i gdm_unrequired_old_lock_i GDM_UNREQUIRED_LOCK_PATHS  GDM_PROJ_CONFIG_MAPTO_LOCK # set by iterating config_lock
    GDM_PROJ_REORDER_LOCK_I # set after iteration and before populating GDM_WORKING_*
    GDM_WORKING_CONFIG GDM_WORKING_LOCK  
    )

  # End result arrays: GDM_WORKING_CONFIG GDM_WORKING_LOCK GDM_WORKING_CONFIG_QUICKVARS
  # definitely needed( and keep as backup?): GDM_PROJ_CONFIG_ARRAY GDM_PROJ_LOCK_ARRAY GDM_PROJ_REORDER_LOCK_I
  # definitely need but only temp: config_i_to_lock_i config_destinations 

  # ? GDM_UNREQUIRED_LOCK_PATHS gdm_unrequired_old_lock_i GDM_PROJ_CONFIG_MAPTO_LOCK

  # unused: GDM_PROJ_OVERRIDE_CONFIG_I GDM_PROJ_LOCKED_CONFIG_I

  export _GDM_ARRAYS_UNUSED=(GDM_PROJ_OVERRIDE_CONFIG_I GDM_PROJ_LOCKED_CONFIG_I)

  gdm.parseConfig
  echo "### DONE ###\nNow try passing any array to showArray -li \$ARRAY_NAME"
  
  local arrays_to_print arg flag filename
  for arg in $@ ; do
    if [[ $arg == - ]] ; then flag=""
    elif [[ $arg == -* ]] ; then flag=$arg
    elif [[ -f $arg ]] ; then filename=$arg ;
      print  "Writing out to file ($filename)... "
      print -n > $filename
    else 
      arrays_to_print=()
      local_allMatchingIdx '_GDM_ARRAYS(i)'$arg arrays_to_print
      ! (($#arrays_to_print)) && echo "no _GDM_ARRAYS matching $arg !" >&2 
      for arrays_i in $arrays_to_print ; do
        if [[ -z $filename ]] ; then showArray $flag $_GDM_ARRAYS[$arrays_i]
        else print "  $_GDM_ARRAYS[$arrays_i] "
          showArray $flag $_GDM_ARRAYS[$arrays_i] >> $filename
        fi
      done
    fi
  done
  
}

showArray() {
  local inline=true
  local as_hash=false
  while [[ "$1" == -* ]] ; do
    if [[ $1 == -l ]] ; then inline=false
    elif [[ $1 == -i ]] ; then as_hash=true
    elif [[ $1 =~ '^-(li|il)$' ]] ; then as_hash=true ; inline=false
    fi
    shift
  done

  local arr_name="$1" 
  if ! [[ -v $arr_name ]] ; then echo $arr_name=undefined ; fi

  if ((${#${(P)arr_name}}==0)) then echo "$arr_name=()" ; return 0 ; fi

  local el_val i
  if $inline ; then # no flag or -i
    print -n "$arr_name=( "
    for i in {1..${#${(P)arr_name}}} ; do
      el_val=$(echo "${(P)${arr_name}[$i]}" | tr -d '\n') # strip newlines 
      [[ -z "$el_val" ]] || [[ "$el_val"  == *' '* ]] && el_val="\"$el_val\"" ;
      $as_hash &&  print -n "[$i]=$el_val " ||  print -n "$el_val "
    done
  else # -il and -l
    print "$arr_name=("
    for i in {1..${#${(P)arr_name}}} ; do
      el_val=$(echo "${(P)${arr_name}[$i]}" | tr -d '\n') # strip newlines 
      $as_hash && print "  [$i]=$el_val" || print "  $el_val"
    done
  fi
  print ")"
}

local_allMatchingIdx() {
  # Examples ( all using ar=(a xo xy xo a) )
  #   gdm_allMatchingIdx 'ar(ie)xo'  # echoes (in order): 2 4
  #   gdm_allMatchingIdx 'ar(Ie)xo'  # echoes (reversed): 4 2
  #   gdm_allMatchingIdx 'ar(ie)x'   # returns 1 (same for (Ie))
  #   gdm_allMatchingIdx 'ar(i)x*'   # echoes (in order): 2 3 4
  #   gdm_allMatchingIdx 'ar(I)x*'   # echoes (reversed): 4 3 2
  # Optionally, pass a variable (by name) as 2nd arg which result will be written to (as an array):
  #  gdm_allMatchingIdx 'ar(i)x*' all_matching_i # no output
  #  echo $all_matching_i # 2 3 4

  local array_name="${1%%'('*}"     # before first )
  local option="${${1#*'('}%%')'*}" # between ( and )
  local patt="${1#*')'}"            # after first )
  local reversed=false ; [[ "$option[1]" == I ]] && reversed=true ;
  local exact=false ; [[ "${option[2]:l}" == e ]] && exact=true ;
  local to_arrayname=""

  if ! [[ -z "$2" ]] ; then 
    to_arrayname="${2#*=}" 
  fi
  
  eval 'local subarr_cpy=( "${'$array_name'[@]}" )' || return 2 # $1 is array name and $2 is value to search for
  local i_matches=() 
  local left_i   # The left matching index on each subarray tested
  local real_i=0 # Initalize to 0 because we will real_i+=left_i offsets for each subarray to get real index

  while (($#subarr_cpy))  ; do
    # Get left-most matching index or... 
    $exact && left_i=$subarr_cpy[(ie)$patt] || left_i=$subarr_cpy[(i)$patt]
    ((left_i>$#subarr_cpy)) && break  # $#subarr_cpy+1 if none found so break and return.
    i_matches+=($((real_i+=$left_i))) # Match found so ccumlate left_i (offset) to real_i and append to matches
    (($#subarr_cpy==1)) && break      # If we only searched one element, break and return.
    # If not, gets slice of subarr_cpy AFTER $left_i:
    subarr_cpy[1,$left_i]=()  
  done

  $reversed && i_matches=( "${(Oa)i_matches[@]}" ) ;
  [[ -z "$to_arrayname" ]] && echo "$i_matches" || eval $to_arrayname'+=("${i_matches[@]}")' ;
  (($#i_matches==0)) && return 1 || return 0 ;
}


gdm_parseConfigTest $@