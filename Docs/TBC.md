# GDM Changes List

## Current Commit

IMPORTANT: Each completed (checked with [x]) item in this **Current Commit** list is a change made in the current commit: subsequent commits must have them deleted from this list and added to the top of the **Past Commits** list

- [x] Move resolution of clashing short hashes from `gdm.require` to  `gdm_parseRequirement` 
- [x] Finish moving `gdm_parseRequirement` functions to `gdm_parseRequirement-helpers.zsh`
- [ ] Lack of a setup option should default to a setup that removes the original `.git/` and does nothing else.
- [ ] If user provides a setup, do not remove the original `.git/`, thus `setup=:` can be used to retain `.git/`.
- [ ] Prior to executing setup, create a `$regis_parent_dir/${regis_id}.git` and place copy of original `.git/` in it.
- [ ] ~~Add destination option relative to HOME directory.~~ This plan has been cancelled (or postponed?)
  - [x] ~~RETRACT~~ (or RESTRICT) FEATURE: Only allow require install directly in `$GDM_REQUIRED/` (remove all destination options but `as`) 
  - [x] OR RESTRICT: temporarily or permanently have removed destination options available via enabling some experimental mode.
  - [ ] prevent `$GDM_REQUIRED/` from not being within `$PROJ_ROOT/` but allow it to not be direct child directory.
- [ ] Mention in some documentation that setup function can be used to export the destination path to env vars. 
- [ ] Simplify `gdm_parseRequirement` output to only essential variables.
- [ ] Have `gdm.require` gather all parsed requirements, check against `config_lock` and currently installed requirement (via scanning them) prior to processing any new or pre-existing require call.
- [ ] Add some new operations or sub-operations to GDM:
  - [ ] `$GMD registry --show-unrequired`  show registers without required instances
  - [ ] `$GMD registry --rm-unrequired`   remove registers without required instances
  - [ ] `$GDM required --list` list (per line) `$destin_instance vendor/reponame#$rev setup=$setup` for each installed requirement.
  - [ ] `$GDM required --info $destin_instance` show contents of manifest for installed requirement.


## Past Commits

This list is in reverse order: Items on top are changed made in most recent to the current commit (but not the current commit).
