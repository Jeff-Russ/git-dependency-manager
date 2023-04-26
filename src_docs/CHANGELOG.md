# GDM Changes List

## Current Commit

IMPORTANT: Each completed (checked with [x]) item in this **Current Commit** list is a change made in the current commit: subsequent commits must have them deleted from this list and added to the top of the **Past Commits** list

#### Always register by full `hash`, do not validate `tag` value.

- [x] Always register by full `hash`
  - [x] `regis_prefix` (the first part of `register_id`) should always be the full `hash` (the second part remains `"_$setup_hash"` if applicable) because this is the only thing that does not change (a `tag` or head of a `branch` can change `hash`). This is to prepare for a future change: if a locked requirement is being installed, it is installed by the `remote_url`, full `hash`, and `setup` (if applicable) ignoring everything else.
  - [x] Since we are changing the way we register, it no longer makes sense to embed the tag into the manifest file name either, so these should just be `$hash[_$setup_hash].gdm_manifest`. 
  - [x] Manifest should also be validated to contain what's needed to install a locked requirement: so no `tag` or `branch` and yes to `remote_url` `hash` `setup_hash` and maybe `register_path` (we shouldn't put the value of `$GDM_REGISTRY` in the manifest but we'll make that change later). Determining what `rev_is` value were if referencing a  `branch`, or `tag` for a given requirement can still be done via comparing to the `config` entry.  Those value can change in relation to the full `hash` but we aren't concerned with them aside from the time a new requirement is being installed. 
  - [x] `gdm_validateInstance` will need to be updated to reflect new, leaner format of manifest files and we should only fail if the `hash` or `setup` is different when installing a locked requirement from the registry or when verifying a previously installed requirement that is locked. 
- [ ] Finish a `gdm.parseConfig` function within `gdm.project` to sort out `config` and `config_lock` before requiring.
- [ ] To gdm.require:
  - [ ] implement config/config_lock to (when called via config or directly in user shell):
    - [ ] add to config_lock when upon first requiring
    - [ ] prevent requirements that have the same required_path as a previous requirement found on FS or in config/config_lock 
    - [ ] add to both config and config lock newly required only if they don't override require paths of different requirements.
- [ ] gdm_echoAndExec
  - [ ] BUG: `gdm.require  juce-framework/juce#master`  outputs `cp -al "$GDM_REGISTRY/github.com/juce-framework/juce/7.0.5" "$GDM_REGISTRYd/juce"` via `gdm_echoAndExec`
- [ ] To gdm.register:
  - [ ] Directly executing `gdm.require` from within a project will register to the default value of `GDM_REGISTRY` even if the project the project's config bypasses this. Keep this behavior?? 
- [ ] Lack of a setup option should default to a setup that removes the original `.git/` and does nothing else. If user provides a setup, do not remove the original `.git/`, thus `setup=:` can be used to retain `.git/`.
- [ ] Prior to executing setup, create a `$regis_parent_dir/${regis_id}.git` and place copy of original `.git/` in it.
- [ ] Have `gdm.require` gather all parsed requirements, check against `config_lock` and currently installed requirement (via scanning them) prior to processing any new or pre-existing require call.
- [ ] Changes to  `2-gdm.init.zsh` :
  - [ ] Consolidate into two functions: `gdm.init` and `gdm.loadProject`
- [ ] Add some new operations or sub-operations to GDM:
  - [ ] `$GMD unrequire [destination option | all but destination option | entire requirement ]`
  - [ ] `$GMD registry --show-unrequired`  show registers without required instances
  - [ ] `$GMD registry --rm-unrequired`   remove registers without required instances
  - [ ] `$GDM required --list` list (per line) `$destin_instance vendor/reponame#$rev setup=$setup` for each installed requirement.
  - [ ] `$GDM required --info $destin_instance` show contents of manifest for installed requirement.
  - [ ] `$GDM project --mv $to` to help move a project that has requirements outside project root (with warning prompts) (and update `proj_paths_lock` once it is implemented)
- [ ] Mention in some documentation that setup function can be used to export the destination path to env vars. 




## Past Commits

This list is in reverse order: Items on top are changed made in most recent to the current commit (but not the current commit).

#### Continue project awareness with parseConfig + various other minor changes

* For testing add a `--source` option to bypass blocking of sourcing.
* Create an `gdm_ask` helper: we'll probably need it later to verify certain actions with users.
* In `gdm.parseRequirement`, change default `to` value to use same capitalization used by user in specifying repository.
* Modify `gdm_validateInstance` to output (stdout) each `${mode}_manifest_requirement_mismatch` 
* Update calls to  `gdm_validateInstance`  to `show_output` from `git diff` and `*_manifest_requirement_mismatch`
* Modify `gdm_validateInstance`  (and `GDM_ERRORS`) to  look for errors in a more better sequence: generally putting more recoverable errors first (and minor errors last) but also checking for errors which would better explain other errors first.

#### rename a lot, start project awareness in gdm.require: call gdm.project and define pack function

* Renames: destin_instance -> required_path, regis_instance -> register_path, previously_registered -> prev_registered, previous_regis_error -> prev_registration_error, regis_id -> register_id, regis_manifest -> register_manifest, regis_snapshot -> register_snapshot, regis_parent_dir -> register_parent, 2-gdm.init.zsh -> 2-gdm.project.zsh gdm.loadProject() ->  gdm.project()  (and more in GDM_ERRORS as see in comment in `1-gdm.zsh`)
* Start to add project awareness: ensure gdm.project is/has been called 
* Make a pack function to help in comparing large sets of variables

#### General cleanup, notably: gdm_parseRequirement and gdm.require in/out

Simplify `gdm_parseRequirement` output to only essential variables (remove: regis_prefix regis_suffix )

#### merge `gdm_exportFromProjVars` function into `gdm.loadProject` function

* For cleanliness in `2-gdm.init.zsh`: ~~combine all function but `gdm.init` found therein into the one function called `gdm.loadProject` (keep `gdm.init` generally as it is and both it and `2-gdm.init.zsh` will continue to require not being run in subshell, which shouldn't be a problem).~~ merge `gdm_exportFromProjVars` into `gdm.loadProject` 

#### Error if \$GDM_REQUIRED is not within PROJ_ROOT (unless experimental)

* Changes to  `2-gdm.init.zsh` :
  * prevent `$GDM_REQUIRED/` from not being within `$PROJ_ROOT/` but allow it to not be direct child directory.

#### commit -m `Make gdm_parseRequirement output complete requirement details, etc`

- Move resolution of clashing short hashes from `gdm.require` to  `gdm_parseRequirement` 
- Finish moving `gdm_parseRequirement` functions to `gdm_parseRequirement-helpers.zsh`
- ~~Add destination option relative to HOME directory.~~ This plan has been cancelled (or postponed?)
- ~~RETRACT~~ (or RESTRICT) FEATURE: Only allow require install directly in `$GDM_REQUIRED/` (remove all destination options but `as`)
- OR RESTRICT: temporarily or permanently have removed destination options available via enabling some experimental mode.
