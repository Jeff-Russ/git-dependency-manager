export GDM_WORKING_CONFIG=()
export GDM_WORKING_LOCK=()

export GDM_PROJ_CONFIG_MAPTO_LOCK=() # Each index is a GDM_PROJ_CONFIG_ARRAY index and each value is:
# 1) the corresponding index in GDM_PROJ_LOCK_ARRAY with the same `destin` value
#   but it could also be:
# 2) the `destin` value if there is no corresponding index in GDM_PROJ_LOCK_ARRAY with the same `destin` value
# 3) a key in GDM_ERRORS (*_destination_arg, destination_already_required_to), indicating the conf requirement has an error.
# NOTE that the absence of an error doesn't mean there won't be one found later when the requirement is passed to gdm.require.

export GDM_WORKING_CONFIG_QUICKVARS=() # Will contain all GDM_WORKING_CONFIG_QUICKVARS assignments gleaned from each config entry
# The GDM_WORKING_CONFIG_QUICKVARS are:      destin remote_url rev setup   required_path repo_identifier remote_ref
# for reference, GDM_CONFIG_LOCK_KEYS are: destin remote_url rev setup   hash tag branch rev_is setup_hash
# and GDM_REQUIREMENT_QUICKLOCKKEYS are all GDM_CONFIG_LOCK_KEYS,
# plus: required_path register_parent register_id path_in_registry register_path register_manifest register_snapshot lock_entry

export GDM_UNREQUIRED_LOCK_PATHS=() # NEW: Indexes of locks with detinations that were presumuably in config but now are not.
# OLD: values are indices in GDM_PROJ_LOCK_ARRAY with `destin` values not targeted by ny requirement in 
#      aconfig (GDM_PROJ_CONFIG_ARRAY). Note that the indexes in GDM_UNREQUIRED_LOCK_PATHS is unimportant. GDM_UNREQUIRED_LOCK_PATHS
#      is basically a list of the elements no longer needed in conf_lock since they are not longer required.

# export GDM_PROJ_OVERRIDE_CONFIG_I=()  #TODO: (implement this) If non-empty, stores the GDM_PROJ_LOCK_ARRAY indices that the caller is modifying. 
#                                       #TODO: This is an array because we'll have operations like `unrequire` that work many.

# export GDM_PROJ_LOCKED_CONFIG_I=()  #TODO: (implement this)  If non-empty, stores the GDM_PROJ_LOCK_ARRAY indices that should resolve to the
#                                     #  hash in the corresponding GDM_PROJ_LOCK_ARRAY (to be looked up with GDM_PROJ_CONFIG_MAPTO_LOCK)
#                                     # because the original requirement referred to a revision that may resolve to a different 
#                                     # hash depending on time of requiring, which was previously locked in by config_lock. 
#                                     # These should be verified against the locked hash and, if missing, installed by the lock hash.

export GDM_PROJ_CONFIG_MAPTO_LOCK=() # Will contain each corresponding entry in config_lock's index with same $destin or 0 if not found (see ***),
  # and, for each non-zero, is followed by a space and two stats:  ' MATCH MISSING'|' MATCH EXISTS'|' MISMATCH MISSING'|' MISMATCH EXISTS'
  #    ' MATCH '* means (quick) requirements match between config<>config_lock and ' MISMATCH'* measn it does not.
  #  The second half refers to the $required_path directory:
  #    *' MISSING' means $required_path does not exist, and *' EXISTS' means it does (but not whether it is valid or not).
  #  Later on ' MATCH EXISTS' can become ' MATCH INSTALLED' which means it is installed AND valid. 
  # 'MISMATCH EXISTS' will not trigger validation of the $required_path since most likely $required_path matches the outdated
  #   config_lock requirement and not the config requirement. 
  
  # *** (CANCELLED PLAN) GDM_PROJ_CONFIG_MAPTO_LOCK+=('1+$#') uses single quotes so it can be appended with an array name and then used as an append index to that array, i.e:
  #     eval 'local next_i=$(('$GDM_PROJ_CONFIG_MAPTO_LOCK[-1]'config))' ; config[$next_i]=appendme
  #  OR
  #     eval 'config[$(('$GDM_PROJ_CONFIG_MAPTO_LOCK[-1]'config))]=appendme'

export GDM_PROJ_REORDER_LOCK_I=() # GDM_PROJ_LOCK_ARRAY will be reorded to match the order of GDM_PROJ_CONFIG_ARRAY then with any 
# elements not matching any GDM_PROJ_CONFIG_ARRAY placed at the end. GDM_PROJ_REORDER_LOCK_I's indices are the old GDM_PROJ_LOCK_ARRAY
# and GDM_PROJ_REORDER_LOCK_I values are the new indices found there after resorting. GDM_PROJ_REORDER_LOCK_I may contain zeros, one 
# for each element in GDM_PROJ_CONFIG_ARRAY not found in GDM_PROJ_LOCK_ARRAY, which are blank elements inserted in GDM_PROJ_LOCK_ARRAY
# just after sorting... to eventually be populated with the requirements in GDM_PROJ_CONFIG_ARRAY as they are fullfilled. 


gdm.parseConfig() {
  # Constructs GDM_PROJ_CONFIG_MAPTO_LOCK GDM_WORKING_CONFIG_QUICKVARS and GDM_UNREQUIRED_LOCK_PATHS
  #NOTE: gdm.parseConfig handles it's own stderr output
  #NOTE: requires GDM_PROJ_ROOT to be set and valid
  
  # GDM_PROJ_LOCKED_CONFIG_I=()  #TODO: (implement this) 

  

  ###### Interate config and set: GDM_WORKING_CONFIG_QUICKVARS -> config_destinations #################################
  GDM_WORKING_CONFIG_QUICKVARS=() 
  local config_destinations=() # Each config entry's $destin value. which we'll use to set config_i in each 
  # GDM_PROJ_CONFIG_MAPTO_LOCK (temporary, used to set config_i_to_lock_i, which is used to  
  # recorder GDM_PROJ_LOCK_ARRAY, which is written out to config_lock before final return)
  local config_i parse_err parse_err_reason overridden_conf_i
  for config_i in {1..$#GDM_PROJ_CONFIG_ARRAY} ; do
    parse_err=0
    #---- Get QUICKVARS for the config requirement -----------------------------------------------#
    echo -n "  config[$config_i]... " #TEST
    eval "local args=( $GDM_PROJ_CONFIG_ARRAY[$config_i] )" || parse_err=$GDM_ERRORS[invalid_config_entry]
    if ! ((parse_err)) ; then 
      GDM_WORKING_CONFIG_QUICKVARS[$config_i]="$(gdm.parseRequirement --quick "${args[@]}")" ; parse_err=$?
    fi
    # Fail for two reasons ...
    if ((parse_err)) ; then # 1) ...We cannot parse the config entry or ...
      parse_err_reason="${(k)GDM_ERRORS[(r)$parse_err]}" 
      [[ -z "$parse_err_reason" ]] && parse_err_reason="unexpected_error"
      echo "$(_S R)ERROR in ${GDM_PROJ_CONF_FILE//$GDM_CALLER_WD/.} parsing config[$config_i], shown below. Reason: $parse_err_reason$(_S)" >&2 
      echo "  $GDM_PROJ_CONFIG_ARRAY[$config_i]" >&2 
      return $GDM_ERRORS[$parse_err_reason]
    fi

    #---- read destin from QUICKVARS for the config requirement ----------------------------------#
    unset $GDM_REQUIREMENT_QUICKVARS ; local $GDM_REQUIREMENT_QUICKVARS ; eval "$GDM_WORKING_CONFIG_QUICKVARS[$config_i]" 
    overridden_conf_i=$config_destinations[(Ie)$destin]  #NOTE: (Ie) finds last or 0 to fail and (ie)) finds first or $#+1 to fail

    if ((overridden_conf_i)) ; then # ... 2) redundant destination: already targeted in a previous config entry.
      echo -n "$(_S R)ERROR in ${GDM_PROJ_CONF_FILE//$GDM_CALLER_WD/.} parsing config[$config_i], shown below.$(_S)" >&2 
      echo "Reason: destination_already_required_to in config[$overridden_conf_i]" >&2 
      echo "  $GDM_PROJ_CONFIG_ARRAY[$config_i]" >&2 
      return $GDM_ERRORS[destination_already_required_to]
    fi

    #-------------- RECORD RESULT (config destination and initiaize config_i_to_lock_i) --------------------#
    echo "destin=$destin" #TEST
    config_destinations[$config_i]="$destin"
  done
  unset $GDM_REQUIREMENT_QUICKVARS 

  ###### Interate config_lock and set: config_i_to_lock_i gdm_unrequired_old_lock_i ###################################
  # and gdm_unrequired_old_lock_i GDM_UNREQUIRED_LOCK_PATHS GDM_PROJ_CONFIG_MAPTO_LOCK
  GDM_UNREQUIRED_LOCK_PATHS=()
  GDM_PROJ_CONFIG_MAPTO_LOCK=()  
  local lock_i req_match required_path_is ; 
  #TODO:remove exports from these two:
  local  config_i_to_lock_i=("${GDM_PROJ_CONFIG_ARRAY[@]/*/0}") # Initalize all to 0 with size of config.
  # We will overwrite with a valid lock_i for each if find. Any invalid lock_i (i.e. out of bounds or '') 
  # will result in an empty element inserted when resorting with gdm_arrayReorderIdx. 
  # We want this because we want to make a space for a config entry to be recorded to, if successful.
  export gdm_unrequired_old_lock_i=()  # these are effectively the second part of config_i_to_lock_i but we 
  # have to collect them separarely and append later since we won't know what index they go until we're done.

  for lock_i in {1..$#GDM_PROJ_LOCK_ARRAY} ; do
    # local lock_entry_hash 
    eval "declare -A lock_entry_hash=( $GDM_PROJ_LOCK_ARRAY[$lock_i] )" 
    echo -n "  config_lock[$lock_i]... " #TEST

    config_i=$(($config_destinations[(Ie)$lock_entry_hash[destin]])) 
    # NOTE: (Ie) finds last or 0 to fail (and (ie) finds first or $#+1 to fail)
    # NOTE: Since we failed for any redundant $destin value in config, we can be sure that the above has, at most, one match
    #       but we cannot be sure that config_lock has no redundant $destin values at this point in time, and if so
    #       one may match in terms of requirement and others may not. We want the one that does match to by mapped to from 
    #       GDM_PROJ_CONFIG_MAPTO_LOCK, if it exists.

    if ((config_i)) ; then  # config_i is not zero (zero means no match found)
      echo "found at config[$config_i]" #TEST
      unset $GDM_REQUIREMENT_QUICKVARS ; local $GDM_REQUIREMENT_QUICKVARS ; eval "$GDM_WORKING_CONFIG_QUICKVARS[$config_i]" 

      #---- check out what is at the required_path -----------------------------------------------#
      required_path_is=""
      if [[ -e "$required_path" ]] ; then
        if [[ -d "$required_path" ]] ; then 
          [[ -z "$(ls -A "$required_path")" ]] && required_path_is=EMPTY_DIR || required_path_is=DIR ;
        else required_path_is=FILE # but really this just means non-directory file type
        fi
      else required_path_is=MISSING
      fi

      #---- check for differing requirements -----------------------------------------------------#
      req_match="___"
      # urls and git branch names and git hashes are not case sensitive: different casings give 
      # the same result with both with them (requests and git commands) as well as in GDM 
      # requirement vars. Git tags are an odd case because the user can specify a tag directly or 
      # by pattern and get the same tag  but hopefully, we assume a change in the way the tag is 
      # specified means the user wants to update. Setups, however include many case-senstive
      # aspects as well as generate different setup hashes 
      [[ "${remote_url:l}" != "${lock_entry_hash[remote_url]:l}" ]] && req_match[1]="U" 
      if [[ "${rev:l}" != "${lock_entry_hash[rev]:l}" ]] ; then 
        echo "    rev mismatch: '${rev:l}' != '${lock_entry_hash[rev]:l}'" #TEST
        req_match[2]="R" 
      fi
      if [[ "$setup" != "$lock_entry_hash[setup]" ]] ; then
        echo "    setup mismatch: '$setup' != '$lock_entry_hash[setup]'"  #TEST
        req_match[3]="S" 
      fi
      if [[ $req_match == '___' ]] ; then req_match=MATCH ; fi

      #-------------------- RECORD RESULT AND CLEAN UP -----------------------------------------------------#
      config_i_to_lock_i[$config_i]=$lock_i 
      GDM_PROJ_CONFIG_MAPTO_LOCK[$config_i]="required_path_is=$required_path_is ; req_match=$req_match ;"
      unset $GDM_REQUIREMENT_QUICKVARS 
    
    else
      echo " not found in config." #TEST

      required_path="$GDM_PROJ_ROOT/$GDM_REQUIRED/$lock_entry_hash[destin]" # expand destin to required_path

      required_path_is=""
      if [[ -e "$required_path" ]] ; then
        if [[ -d "$required_path" ]] ; then 
          [[ -z "$(ls -A "$required_path")" ]] && required_path_is=EMPTY_DIR || required_path_is=DIR ;
        else required_path_is=FILE # but really this just means non-directory file type
        fi
      else required_path_is=MISSING
      fi

      #-------------------- RECORD RESULT ------------------------------------------------------------------#
      gdm_unrequired_old_lock_i+=($lock_i)
      GDM_UNREQUIRED_LOCK_PATHS+=( "lock_i=$lock_i ; required_path=\"$required_path\" required_path_is=$required_path_is ; " )

      # TODO: If any GDM_UNREQUIRED_LOCK_PATHS installed, remove from GDM_PROJ_CONFIG_ARRAY
      #      else, maybe ask user or just leave it and add a key [status]=NOT_IN_CONFIG or something??
    fi
    unset lock_entry_hash
    
    
  done
  unset $GDM_REQUIREMENT_QUICKVARS 

  ###### Create copies as GDM_WORKING_CONFIG and GDM_WORKING_LOCK (synchronized to the former) ########################
  # GDM_WORKING_CONFIG is a straight copy of config but the later is a rearranged version of config_lock.
  # If config_lock has no destin+requirement not found in config, the two working arrays will be equal size.
  # But it does, they will be pushed to the end of GDM_WORKING_LOCK, beyond the last index of config.
  # For each index of GDM_WORKING_CONFIG, the same index on GDM_WORKING_LOCK will either match destin+requirement
  # or be empty, indicating there is no match.
  # THE PURPOSE OF THIS: for a given index < $#config, GDM_WORKING_CONFIG and GDM_WORKING_LOCK are aligned.
  # So the general working idea is: anything done to one array's element should be reflected in the other at the same index.


  GDM_WORKING_CONFIG=( "${GDM_PROJ_CONFIG_ARRAY[@]}" )

  #Reorder GDM_PROJ_LOCK_ARRAY to be in same order as GDM_PROJ_CONFIG_ARRAY (moving GDM_UNREQUIRED_LOCK_PATHS to end)
  GDM_PROJ_REORDER_LOCK_I=( "${config_i_to_lock_i[@]}"  "${gdm_unrequired_old_lock_i[@]}" )


  gdm_arrayReorderIdx GDM_PROJ_LOCK_ARRAY --to=GDM_WORKING_LOCK --allow-empty --all-to-one GDM_PROJ_REORDER_LOCK_I || {
    echo "gdm_arrayReorderIdx FAILED!!" >&2 #TEST for now. later have it always work or return from function with error
  }

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
  $0.write_array config "${GDM_WORKING_CONFIG[@]}"
  echo "${GDM_PROJ_CONF_FILE_SECTIONS[3]}" >> "$proj_conf"
  $0.write_array config_lock "${GDM_WORKING_LOCK[@]}"
  echo "${GDM_PROJ_CONF_FILE_SECTIONS[5]}" >> "$proj_conf"
}



# for debugging:
gdm.echoProjVars() {
  typeset -m 'GDM_CALL*'
  typeset -m 'GDM_PROJ*'
  # echo $GDM_PROJ_VARS
}
