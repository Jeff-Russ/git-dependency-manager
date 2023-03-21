# git-dependency-manager

##### A small zsh script for managing dependencies that are git repositories.

Git Dependency Manager (`gdm`) is a "no publish" package manager alternative that is language and platform agnostic. 

It was created to address the issue working on projects that make use of git repositories as libraries/frameworks for that have not been published to any package manager. For a particular "package" to be available via `gdm`, the only criteria is that it be hosted as git repository. `gdm` ensures each collaborator is working with the same version of requirement with consistent paths to reference them across different machines. 

# Features

* A given requirement specifies the version as the value of a git tag (or pattern matching that value) or a commit hash.
* Disk space efficient: inspired by [pnpm](https://www.npmjs.com/package/pnpm/v/3.7.0-3), if multiple projects on a particular machine have the same requirement, they reference the same files (via hard links) such that no additional storage is required.
* Low barrier to participation:
  * `gdm` is a "no publish," meaning any dependency that is available to be cloned as a git repository is by default a "package" available via `gdm`.
  * Your collaborators needn't have anything preinstalled: simply include a configuration script in your project root and all collaborators can assemble the same dependency configuration by one call to this script.


# News

The current version is `v1.0beta1` for which one caveat should be known: 

With this  version, it is recommended that each time resuming work on a project 
`./gdm conf`  should be re-run. Normally this won't be need but in cases where two 
projects may be  working off the same dependency in the global store, the files 
within it make have deviate into different inodes. Generally this would mean more 
drive space that needed would be used but in some cases, it could be your local 
version of the dependency could be corrupted.

Just run `./gdm conf` to be sure for now. This will be remedied soon!

# Installation




```sh
cd YOUR/PROJECT/ROOT/
curl https://raw.githubusercontent.com/Jeff-Russ/git-dependency-manager/main/gdm > ./gdm % chmod 755 ./gdm
```

That's it. I recommend to not .`gitignore` this `gdm` script as others who made clone 
your project will have it available to set up the same dependency environment you have.   

If you find yourself doing this a lot, for different repositories, create a reusable command 
that aliases the `curl` command (for zsh terminals):  

```zsh
% echo "\\n"'alias dl-gdm="curl https://raw.githubusercontent.com/Jeff-Russ/git-dependency-manager/main/gdm > ./gdm % chmod 755 ./gdm"' >> ~/.zshrc 
```

Then, from your project root, run `add-gdm` and the `gdm`  will be there for ya.

# Usage

```sh
./gdm help
Usage:
  ./gdm init   # will generate empty configuration file for your project
  ./gdm conf   # will read file and perform configuration.

By default, dependencies are installed (cloned to) ~/gdm_glob_store/ 
with hard links to them in each <project-root>/gdm_modules/

You can choose your own global location for your machine by
modifying your rc file (for example, ~/.zshrc):
  export GDM_GLOB_STORE_PATH="/desired/path/to/directory/"
You can choose your own location within a given probject by modifying the line:
  export GDM_MODULES_DIRNAME="gdm_modules"
in your project's gdm_conf.zsh file.
```

When you execute with:  

```sh
./gdm init
```

a file called `gdm_conf.zsh` will be placed in your current directory. This file 
is where you define you dependencies. It's packed with comments on how to to that.  

After you set up your  `gdm_conf.zsh`, run the following:  

```sh
./gdm conf
```

Afterward, everything will be set up for you! By default, you'll have a `gdm_modules/` 
directory in your project root with your dependencies (you probably should `.gitignore` this)
but you can choose a different name or bypass this entirely (see `gdm_conf.zsh` comments and
output from `./gdm help` for more information.).   

