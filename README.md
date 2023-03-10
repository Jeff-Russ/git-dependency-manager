# git-dependency-manager

##### A small zsh script for managing dependencies that are git repositories.

After working on projects making use of git repositories as libraries/frameworks 
for which no proper package manager exist, managing these dependencies felt a bit 
error-prone. I would often have to take note of what git commit hash my code 
depended on and move the git HEAD pointer to that commit... then moving it forward 
for newer projects. This doesn't work very well when collaborating as there is no 
mechanism for doing this automatically (selecting version numbers per-project) and 
no consistent path to reference the dependencies across different machines.  

So I made little zsh script to do this for me. It's not ideal but it does the job. 
It depends on too many implementation details of git and commit message practices 
such as tagging releases but it works, for now. 

So if the problem this script tackles is a problem for you as well, give it a shot. 
It won't touch any part of your system beside a single global directory you choose 
to keep all dependencies and, optionally, a directory within each of your projects 
where links to the globally installed repositories are generated.  

# Features

* Disk space efficient:  inspired by [pnpm](https://www.npmjs.com/package/pnpm/v/3.7.0-3), project dependencies are hard links to a global store.
  * Automatic cleaning of unused dependencies kept in global store via reference counting of hard links.
* Multiple versions of the same dependency can be switched between or used concurrently.
* Nothing is installed on your system and no changes are made to your shell environment. Simply include the `gdm` in your project root and all collaborators can assemble the same dependency configuration by one call to this script.

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

