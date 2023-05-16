# GDM Changes List

## Current Commit

IMPORTANT: Each completed (checked with [x]) item in this **Current Commit** list is a change made in the current commit: subsequent commits must have them deleted from this list and added to the top of the **Past Commits** list

#### Refine gdm.parseConfig, define gdm_expandDestination, create tests

- [x] create `gdm_expandDestination` (with test runner) for the following reasons:
  - [x] TASK COMPLETED: To be used by `gdm.parseRequirement` and add some forward compatibility for more flexible destination options.
    - [x] TASK COMPLETED: Define (really just as a comment, but also as part of `gdm_expandDestination`) some more `GDM_EXPERIMENTAL` modes for more flexible destination options.

  - [ ] TASK TBC: To called directly to expand a `lock_entry[destin]` to get the full `required_path`. Why? If a `config_lock` entry refers `destin`/requirement  not in `config`, we can confidently just remove it if there is nothing at the full `required_path`.

- [x] Refine `gdm.parseConfig` further (still by no means complete) and create a test runner for it. 
- [ ] `export GDM_REQUIRED_PATH` ...Instead of using `$GDM_PROJ_ROOT/$GDM_REQUIRED` everywhere (which fails if `GDM_REQUIRED` starts with `~/` or is a full path which, we don't allow by default but is allowed if `GDM_EXPERIMENTAL` contains `any_GDM_REQUIRED_path`), do this only once (respecting the presence of `any_GDM_REQUIRED_path`) and save it to `$GDM_REQUIRED_PATH`.
- [ ] `config`/`config_lock` functionality
  - [ ] In `gdm_validateInstance`: (See what needs changing)
  - [ ] In `gdm.project`:
    - [ ] (By call to `gdm.parseConfig`) Gather all parsed requirements, check against `config_lock` and currently installed requirement (via scanning them) prior to processing any new or pre-existing require call.
  - [ ] `gdm.main` and (and maybe `gdm.require`)  should know which of the following scenarios it is requiring under:
    - [ ] (see `Implementation_Notes.md` once I un-gitignore it!)
- [ ] Finish implementation of `gdm.update_conf` function to update the `$GDM_PROJ_CONF_FILE` file's `config` and `config_lock` arrays from `GDM_WORKING_CONFIG` and `GDM_WORKING_LOCK` rather than `GDM_PROJ_CONFIG_ARRAY` and `GDM_PROJ_LOCK_ARRAY`, respectively. The  `GDM_PROJ_*_ARRAY`s should not be modified but rather keep as untouched versions in case we need to backtrack. Instead, we'll add to  each `GDM_NEW_*_ARRAY`  as we either make a change or confirm what was there before. 
- [ ] In `8-gdm-helpers.zsh,` `gdm_echoVars` should use `gdm_quote` function to make sure values are appropriately quoted
- [ ] Add some new operations or sub-operations to GDM:
  - [ ] `$GMD unrequire [destination option | all but destination option | entire requirement ]`
  - [ ] `$GMD registry --show-unrequired`  show registers without required instances
  - [ ] `$GMD registry --rm-unrequired`   remove registers without required instances
  - [ ] `$GDM required --list` list (per line) `$destin_instance vendor/reponame#$rev setup=$setup` for each installed requirement. 
  - [ ] `$GDM required --info $destin_instance` show contents of manifest for installed requirement. Determining what `rev_is` value were if referencing a  `branch`, or `tag` for a given requirement can still be done via comparing to the `config` entry.  Those values can change in relation to the full `hash` but we aren't concerned with them aside from the time a new requirement is being installed or when the user wants to see them. Try: maybe use `git tag --points-at HEAD` to show tag on current commit or other commands like `git --no-pager log  -1 --pretty='hash=%H ; %nauthor_date="%aI" ;'` (with  more variables assigned to [placeholder](https://git-scm.com/docs/git-log#_pretty_formats) values) and something else like that to just get the commit message, which we'll parse to see if we need escaping of quotation marks.
  - [ ] `$GDM project --mv $to` to help move a project that has requirements outside project root (with warning prompts) (and update `proj_paths_lock` once it is implemented)
- [ ] Mention in some documentation that setup function can be used to export the destination path to env vars. 


## Past Commits

This list is in reverse order: Items on top are changed made in most recent to the current commit (but not the current commit).

#### Prep for lock i.e  parsing lock entries, quick parse normal & lock req's


* Replace all destination options (flags) with one where the variable will be called `destin` and the arg will be matching: `'^-{0,2}d(est|estin|estination|ir|irectory)?=.+'`
* We shouldn't put the value of `$GDM_REGISTRY` in the manifest: rather than registering the variable `register_path` use a new one called `path_in_registry`, which is the same as `register_path` but starts with the path segment after `$GDM_REGISTRY` 
* Make `setup` values that are not scripts or functions or are script that are not contained within the project root fail with `$GDM_ERRORS[invalid_setup]` (a new error code)
* Remove our `--allow-unlinked`/`--disallow-unlinked` flags for now. Later on we'll have something to clean the registry based on unlinked registered
* Rename `gdm()` to `gdm.main()` to make it more searchable.
* `config`/`config_lock` functionality
  * `conf_lock` element format is **the body of an associative array** (example): `"[destin]=jucedev [remote_url]=https://github.com/juce-framework/juce.git [rev]=develop [setup]=doit [hash]=8ed3618e12230ad8563098e1f17575239497b127 [tag]='' [branch]=develop [rev_is]=branch [setup_hash]=3f14a426 "`
  * In `gdm.parseRequirement`: Create options for parsing  `config_lock` entries and quick parsing of both normal and `config_lock`  requirements
* In `8-gdm-helpers.zsh`
  * Make `gdm_echoVars` faster by accumulating and output string to have only one `stdout` at the end of the function. 
  * Implement a `gdm_varsToMapBody` function to pack variables into the **the body of an associative array** and use this to generate `config_lock` array elements (the `lock_entry` parameter). This function should use the new `gdm_quote` function to make sure values are appropriately quoted.
  * Implement a `gdm_echoMapBodyToVars` function to convert **the body of an associative array** (output from  `gdm_varsToMapBody`)to  a string which assigns the values to variables (from the keys and values) and use this to parse `config_lock` array elements in `gdm.parseRequirement`. 
* (Start to) implement and `gdm.update_conf` function to update the `$GDM_PROJ_CONF_FILE` file's `config` and `config_lock` arrays from `GDM_PROJ_CONFIG_ARRAY` and `GDM_PROJ_LOCK_ARRAY`, respectively. 
* gdm_echoAndExec BUG: `gdm.require  juce-framework/juce#master`  outputs `cp -al "$GDM_REGISTRY/github.com/juce-framework/juce/7.0.5" "$GDM_REGISTRYd/juce"` via `gdm_echoAndExec` UPDATE: I made unrelated changes to  `gdm_echoAndExec` for whatever reasons, the bug behavior appears to not be happening now.  
* Directly executing `gdm.require` from within a project will register to the default value of `GDM_REGISTRY` even if the project the project's config bypasses this. Keep this behavior?? Update: No.. well sort of. I've blocked direct execution of `gdm.require`, one can only execute `require` as an operation and doing so always triggers `gdm.project` to be called.
* Cancelled plans:

  * ~~Lack of a setup option should default to a setup that removes the original `.git/` and does nothing else. If user provides a setup, do not remove the original `.git/`, thus `setup=:` can be used to retain `.git/`.~~
  * ~~Prior to executing setup, create a `$regis_parent_dir/${regis_id}.git` and place copy of original `.git/` in it.~~
  * ~~Consolidate  `2-gdm.init.zsh`   into two functions: `gdm.init` and `gdm.loadProject`~~


#### Always register by full `hash`, do not validate `tag` value.

* `regis_prefix` (the first part of `register_id`) should always be the full `hash` (the second part remains `"-$setup_hash"` if applicable) because this is the only thing that does not change (a `tag` or head of a `branch` can change `hash`). This is to prepare for a future change: if a locked requirement is being installed, it is installed by the `remote_url`, full `hash`, and `setup` (if applicable) ignoring everything else.
* Since we are changing the way we register, it no longer makes sense to embed the tag into the manifest file name either, so these should just be `$hash[_$setup_hash].gdm_manifest`. 
* Manifest should also be validated to contain what's needed to install a locked requirement: so no `tag` or `branch` and yes to `remote_url` `hash` `setup_hash` and maybe `register_path` (we shouldn't put the value of `$GDM_REGISTRY` in the manifest but we'll make that change later). Determining what `rev_is` value were if referencing a  `branch`, or `tag` for a given requirement can still be done via comparing to the `config` entry.  Those value can change in relation to the full `hash` but we aren't concerned with them aside from the time a new requirement is being installed. 
* `gdm_validateInstance` will need to be updated to reflect new, leaner format of manifest files and we should only fail if the `hash` or `setup` is different when installing a locked requirement from the registry or when verifying a previously installed requirement that is locked. 

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

#### Make gdm_parseRequirement output complete requirement details, etc

- Move resolution of clashing short hashes from `gdm.require` to  `gdm_parseRequirement` 
- Finish moving `gdm_parseRequirement` functions to `gdm_parseRequirement-helpers.zsh`
- ~~Add destination option relative to HOME directory.~~ This plan has been cancelled (or postponed?)
- ~~RETRACT~~ (or RESTRICT) FEATURE: Only allow require install directly in `$GDM_REQUIRED/` (remove all destination options but `as`)
- OR RESTRICT: temporarily or permanently have removed destination options available via enabling some experimental mode.
