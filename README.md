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


# Installation


```sh
cd YOUR/PROJECT/ROOT/
curl https://raw.githubusercontent.com/Jeff-Russ/git-dependency-manager/main/gdm.zsh > ./gdm.zsh % chmod 755 ./gdm.zsh
```

That's it. I recommend to not .`gitignore` this `gdm.zsh` script as others who made clone 
your project will have it available to set up the same dependency environment you have.   

If you find yourself doing this a lot, for different repositories, create a reusable command 
that aliases the `curl` command (for zsh terminals):  

```zsh
% echo "\\n"'alias add-gdm="curl https://raw.githubusercontent.com/Jeff-Russ/git-dependency-manager/main/gdm.zsh > ./gdm.zsh % chmod 755 ./gdm.zsh"' >> ~/.zshrc 
```

Then, from your project root, run `add-gdm` and the `gdm.zsh`  will be there for ya.

# Usage

```sh
./gdm.zsh --help
Usage: call with
  --init    to generate empty configuration file or with
  --conf    to read existing configuration
By default, dependencies installed will be placed in ~/GDM_DEPS/ but
you can choose your own location by adding to your ~/.zshrc the following:
  export GDM_DEPS_DIR="/desired/path/to/directory/"
```

When you execute with:  

```sh
./gdm.zsh --init
```

a file called `gdm-conf.zsh` will be placed in your current directory. This file 
is where you define you dependencies. It's packed with comments on how to to that.  

After you set up your  `gdm-conf.zsh`, run the following:  

```sh
./gdm.zsh --conf
```

If all goes well, everything will be set up for you! By default, you'll have a `GDM_MODULES/` 
directory in your project root with your dependencies (you probably should `.gitignore` this)
but you can choose a different name or bypass this entirely (see `gdm-conf.zsh` comments).   

