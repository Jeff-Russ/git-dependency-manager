
* Lack of a setup option should default to a setup that removes the original `.git/` and does nothing else.
* If user provides a setup, do not remove the original `.git/`, thus `setup=:` can be used to retain `.git/`.
* Prior to executing setup, create a `$regis_parent_dir/${regis_id}.git` and place copy of original `.git/` in it.
* Add destination option relative to HOME directory. 
* Mention in some documentation that setup function can be used to export the destination path to env vars. 


