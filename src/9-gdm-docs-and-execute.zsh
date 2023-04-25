######## HELP DOCS ################################################################################

gdm_require_register_helpdoc() {

cat << 'CONFDOC'
Typical Usage for `require` and `register` Operations:

    $GDM <Operation> <Repo Ident.>#<Rev> [<InstallLoc.Opt>] [setup=<executable>]

  The above applies to entries in the `config` array but, since each of the
  array's elements are passed as parameters to `$GDM require`, each starts with 
  the Repository Identifier.

The Repository Identifier and Revision Selection

    [domain/]vendor/repo[.git][#<hash>|#<tag or tag_pattern>|#<branch>] 

  This is the only ordered parameter and must preceed the unordered options.
  Examples:

    <vendor>/<repo>       This respository identifier will default to GitHub, and
                          expand to https://github.com/vendor/repo.git (which is a 
                          format that this argument could have been provided as). 
                          Omitting a revision selection is equivalent to providing 
                          the default branch name (typically main or master) which 
                          resolves to the most recent commit on the branch at the 
                          time of requiring. 

    <vendo>/<repo>#3.1.2  The value after # is the revision selection, which could 
                          be a tag value/pattern, a hash or a branch name. If the 
                          value is a tag, it will be inferred as such. Tag revision 
                          selections will resolve to a single version just as 
                          specifying a full hash would do and, as such, neither 	
                          would normally resolve differently dependent on time of 
                          requiring. 

    <vendor>/<repo>#2a3fb If value after # is a hash (long or abbreviated), it will
                          be inferred as such. If abbreviated, an error will occur if
                          more than one hash exist starting with the abbreviation.

    <vendor>/<repo>#dev   If value after # is a branch name, it will be inferred as 
                          such and will resolve to the most recent commit on the 
                          branch at the time of requiring. 

Install Location Option

    [ as=<name> | to-proj-as=<relpath> | to-fs-as=<abspath> | 
      to-proj-in=<relpath> | to-fs-in=<abspath> ] 

  When the <Operation> is `require`, choose one of the the following options to 
  define an instance's install location for a given required vendor/repo#revision
  or let the default take hold, which is to install as a directory whose name is 
  the repository name, placed directly in the \$GDM_REQUIRED directory. Thus
  `as=<repo-name>` is the default Install Location Option. 

  Examples:

    as=name                   Install as custom directory name to \$GDM_REQUIRED.

    to-proj-as=./parent/name  Install AS custom directory name, provided as
                              a path relative to the project root. The relative path  
                              must start with ./ a directory name or ../ and not /

    to-proj-in=./parent       Install IN a custom parent directory, provided as
                              a path relative to the project root. The relative 
                              path  must start with ./ a directory name or ../
                              and not /

    to-fs-as=/parent/name     Install AS custom directory name, provided as
                              an absolute path starting with / whose location is 
                              not contained by the project root or \$GDM_REQUIRED

    to-fs-in=/parent          Install IN a custom parent directory, provided as
                              an absolute path starting with / whose location is 
                              not contained by the project root or \$GDM_REQUIRED

  Comments and Considerations:

  Options above ending with `-as` define the path to the installed directory, including 
  the installed directory's name whereas those ending with `-in` define only path up to 
  but not including the name of the directory being installed, defaulting this directory 
  name to the repository name. So `to-proj-in` and `to-fs-in` are essentially shortcuts 
  to `to-proj-as` and  `to-fs-as` where the values have `/<repo-name>` appended to them. 
  The `-in` options are offered as convenience.

  If projects are shared, one should prefer paths that are within the project or within 
  the parent of the project directory as colabertors may not have similar file systems. 

  Two requirements within a project cannot resolve to the same absolute path (this would 
  produce an error) but two different project with requirements resolving to the same 
  absolute path can, so long as all other parameters of their requirements are identical. 

  TBC: 

  Allow a single require statement to install to multiple locations. At this time, 
  this is only possible via multiple require statements.
CONFDOC
}



######## FILE TEMPLATES ###########################################################################

gdm_conf_template() { gdm_conf_header ; gdm_conf_body ; gdm_conf_footer ; }

gdm_conf_header() {
cat << CONFDOC
#!/usr/bin/env zsh

export GDM_REGISTRY="\$HOME/.gdm_registry"
export GDM_VER='$GDM_VERSION'
export GDM="\$GDM_REGISTRY/gdm-\$GDM_VER.zsh"

CONFDOC
}
gdm_conf_body() {
cat << 'CONFDOC'
# Add any setup functions here

export config=(
  # Example:
  # gdm require juce-framework/JUCE#develop as=juce-dev setup='rm -rf .git'
)

CONFDOC
}
gdm_conf_footer() {
cat << 'CONFDOC'
# DO NOT MODIFY THIS LINE OR BELOW
if ! [[ -f "$GDM" ]] ; then
  mkdir -p "$GDM:h" && curl "https://raw.githubusercontent.com/Jeff-Russ/git-dependency-manager/main/dist/$GDM:t" > "$GDM" ;
fi
export config_lock=()
(($#)) && { source "$GDM" "$@" ; return $? ; }
return 0

CONFDOC
}

######## EXECUTE ##################################################################################
SOURCE_GDM=false # Test mode: allow sourcing by not unsetting/unfunctioning everything after call
if [[ "$1" == --source ]] ; then SOURCE_GDM=true ; shift ; fi

gdm "$@" 

if ! $SOURCE_GDM ; then 
  # Prevent calling of any functions directly without executing the GDM_SCRIPT and prevent stale env vars
  unfunction -m gdm "gdm.*" "gdm_*" ; unset -m "GDM_*" ;
fi
