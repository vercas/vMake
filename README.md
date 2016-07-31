# vMake
Tool for building software and configuring builds.

## Obtaining

Best way to get vMake is with [LuaRocks](https://luarocks.org/): `luarocks install vmake`  
Alternatively, clone this repo (preferably, a tagged version) and place/symlink `vmake.lua` into a *$LUA_PATH* directory (depends on your environment; the working directory is generally amongst them).  

## vMakefiles

To use vMake, you need to write a "*vMakefile*". Only one I'm aware of is [Beelzebub's](https://github.com/vercas/Beelzebub/blob/master/vmakefile.lua).  
It uses every feature of vMake.  

Your vMakefile should always begin with...
    #!/usr/bin/env lua
    require "vmake"
... after which, you should declare all your projects, configurations, architectures, and command-line options.  
As the code is not preprocessed/parsed in any way, feel free to include full proper Lua code to do whatever computation is required for the declared objects.  

After everything is set up, simply call `vmake()` to act.  

### Object Declarations

vMake works through a set of declared objects, which tell it which projects are available, what components a project (or another component) has, rules which create files, available configurations and architectures, and command-line options.  

#### Configurations & Architectures

These two have identical roles and abilities but different semantics.  
They represent major decisions in the build process, and, once defined, are available for every project.  

If no configuration or architecture is provided, default ones (called "default-conf" or "default-arch") will be provided.  

A default configuration and architecture can be specified with the `Default` function as such:
    Default "amd64" "debug"
(*note for those who are inexperienced with Lua: this is equivalent to `Default("amd64")("debug")` but it looks more declarative that way.*)

These can be declared simply like...
    Configuration "release"
... or with more information, such as...
    Architecture "amd64" {
        Data = {
            Opts_GCC = List { "-m64" },

            Opts_NASM = List { "-f", "elf64" },
        },

        Base = "x86",
    }

As seen in the example above, they support inheritance, of sorts. Every confiuration can have a base configuration (used for data resolution), and every architecture can have a base architecture (same reason).  

The architecture and configuration of the current build are available in the `selArch` and `selConf` fields of the local environment argument of every function.  

The difference in semantics between configurations and architectures are as follows:
 - A configuration represents the behaviour of the build. By far the most common examples are `debug` and `release`, where the former normally includes debug symbols and forbids optimization, while the latter excludes symbols and enables optimization.
 - An architecture represents the platform/environment in which a build is used. Examples include `win64`, `android-armv7`, `linux-i346`.

Architectures, configurations and projects cannot share names.

#### Projects

Projects represent top-level components which can be selected for building.  
These can contain components and everything that a component can contain.  

Project names must be unique, and cannot be shared with architectures and configurations.

#### Components

A component (and, transitively, top-level projects) represent a piece (maybe whole) of a project.  
They are defined by the following main properties:
 - `Output`: one or more files which are produced by this component;
 - `Dependencies` (optional): One or more top-level projects **or** sibling components which must be fully build prior to starting building this one;
 - `Directory` (optional): A directory represented by this component;
 - `Description` (optional): A textual description of this component.

Besides these properties, a component may contain other components and rules.  

Building a component generally means that every file listed in its output is produced when it is done.  

Components cannot have the name of a project, architecture or configuration, nor that of a sibling component.  
