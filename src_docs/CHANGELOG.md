# GDM Changes List

## Current Commit

IMPORTANT: Each completed (checked with [x]) item in this **Current Commit** list is a change made in the current commit: subsequent commits must have them deleted from this list and added to the top of the **Past Commits** list

- [ ] Changes to  `2-gdm.init.zsh` :
  - [x] prevent `$GDM_REQUIRED/` from not being within `$PROJ_ROOT/` but allow it to not be direct child directory.
  - [ ] For cleanness: combine all function but `gdm.init` found in `2-gdm.init.zsh` into the one function called `gdm_loadProj` (keep `gdm.init` generally as it is and both it and `2-gdm.init.zsh` will continue to require not being run in subshell, which shouldn't be a problem).
- [ ] Lack of a setup option should default to a setup that removes the original `.git/` and does nothing else. If user provides a setup, do not remove the original `.git/`, thus `setup=:` can be used to retain `.git/`.
- [ ] Have `gdm.require` gather all parsed requirements, check against `config_lock` and currently installed requirement (via scanning them) prior to processing any new or pre-existing require call.
- [ ] Prior to executing setup, create a `$regis_parent_dir/${regis_id}.git` and place copy of original `.git/` in it.
- [ ] Simplify `gdm_parseRequirement` output to only essential variables.
- [ ] Add some new operations or sub-operations to GDM:
  - [ ] `$GMD registry --show-unrequired`  show registers without required instances
  - [ ] `$GMD registry --rm-unrequired`   remove registers without required instances
  - [ ] `$GDM required --list` list (per line) `$destin_instance vendor/reponame#$rev setup=$setup` for each installed requirement.
  - [ ] `$GDM required --info $destin_instance` show contents of manifest for installed requirement.
- [ ] Mention in some documentation that setup function can be used to export the destination path to env vars. 


## Past Commits

This list is in reverse order: Items on top are changed made in most recent to the current commit (but not the current commit).

#### commit -m `Make gdm_parseRequirement output complete requirement details, etc`

- Move resolution of clashing short hashes from `gdm.require` to  `gdm_parseRequirement` 
- Finish moving `gdm_parseRequirement` functions to `gdm_parseRequirement-helpers.zsh`
- ~~Add destination option relative to HOME directory.~~ This plan has been cancelled (or postponed?)
- ~~RETRACT~~ (or RESTRICT) FEATURE: Only allow require install directly in `$GDM_REQUIRED/` (remove all destination options but `as`)
- OR RESTRICT: temporarily or permanently have removed destination options available via enabling some experimental mode.
