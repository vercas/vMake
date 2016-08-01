# vMake
Tool for building software and configuring builds.

## Obtaining

Best way to get vMake is with [LuaRocks](https://luarocks.org/): `luarocks install vmake`  
Alternatively, clone this repo (preferably, a tagged version) and place/symlink `vmake.lua` into a *$LUA_PATH* directory (depends on your environment; the working directory is generally amongst them).  

## vMakefiles

To use vMake, you need to write a "*vMakefile*". Only one I'm aware of is [Beelzebub's](https://github.com/vercas/Beelzebub/blob/master/vmakefile.lua).  
It uses every feature of vMake.  

Your vMakefile should always begin with...
```lua
#!/usr/bin/env lua
require "vmake"
```
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
```lua
Default "amd64" "debug"
```
(*note for those who are inexperienced with Lua: this is equivalent to `Default("amd64")("debug")` but it looks more declarative that way.*)

These can be declared simply like...
```lua
Configuration "release"
```
... or with more information, such as...
```lua
Architecture "amd64" {
    Data = {
        Opts_GCC = List { "-m64" },

        Opts_NASM = List { "-f", "elf64" },
    },

    Base = "x86",
}
```

As seen in the example above, they support inheritance, of sorts. Every confiuration can have a base configuration (used for data resolution), and every architecture can have a base architecture (same reason).  

The architecture and configuration of the current build are available in the `selArch` and `selConf` fields of the local environment argument of every function.  

The difference in semantics between configurations and architectures are as follows:
- A configuration represents the behaviour of the build. By far the most common examples are `debug` and `release`, where the former normally includes debug symbols and forbids optimization, while the latter excludes symbols and enables optimization.
- An architecture represents the platform/environment in which a build is used. Examples include `win64`, `android-armv7`, `linux-i346`.

Architectures, configurations and projects cannot share names.

#### Projects

Projects represent top-level components which can be selected for building.  
These can contain components and everything that a component can contain.  

At least one project must be defined for vMake to be able to do anything. An error will be shown if none is provided.  

A default project can be specified with the `Default` function, just like architectures and configurations:
```lua
Default "Beelzebub"
```

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

#### Rules

Rules provide the means to construct files.  

They do this through three functions/properties:
- `Filter`: Can be either of the following types...
    - `string` or `Path`: Matches the specific path exactly;
    - `List` of `string`s and `Path`s: Matches any path in the list;
    - `function`: Is given a destination path as argument and returns a `boolean` for a definitive answer, or a `Path` or `List` for further lookup.
- `Source`: Can be either of the following types...
    - `string` or `Path`: The destination file requires this specific source file;
    - `List` of `string`s and `Path`s: The destination file requires these specific source files;
    - `function`: Is given a destination path as argument and returns a `Path` or `List` of `string`s and `Path`s representing the source(s) for the destination path.
- `Action`: A `function` which is given the destination `Path` and `List` of sources (even if just one), and should perform the steps necessary to obtain the destination path;
- `Shared`: Whether the rule can be used by child components of the container or not.

There should be rules available for every file that doesn't exist.  

Rules cannot have the names of a project, configuration or architecture.  

#### Hierarchies and Data

All the objects above form hierarchies, and can contain arbitrary data in a property named `Data`.  

The parent of a rule or component is the containing component (or project). Projects have no parent.  
The parent of an architecture or configuration is the one named as its `Base`.  

When data keys are resolved in a function (through its local environment), it starts at the containing object and works its way up the hierarchy. Resolution stops when the key is found in the `Data` of an object.  

Data keys can only be strings, and values which are functions are called only once with a local environment to provide the actual data. This resolution happens on-demand, the first time a data key is retrieved.  

Data containers cannot be modified.  

Besides the type, there is no restriction on the value of keys.  

#### Command-line options (`CmdOpt`s)

Command-line options can be declared for build configuration (or other purposes).  
One must have a long name (at least two characters), and an optional short name (precisely one character).  

To be documented later. For examples, refer to Beelzebub's vMakefile linked above.  

### Output Directory

A vMakefile can declare an output directory, which is used by vMake to create temporary files (if/when needed) and should be used by components to locate their output as well.  

This is provided through the `OutputDirectory` function as such:
```lua
OutputDirectory "./.vmake"
--  or
OutputDirectory(function(_)
    return "./.vmake/" .. (_.selArch.Name .. "." .. _.selConf.Name)
end)
```

The latter example is actually the default value, resulting in a path like `./.vmake/arch.conf/`.

### Functions and Local Environments

Objects declared in vMakefiles make use of functions for providing non-constant values to data items and the majority of properties.  

All these functions receive a **local environment** table as their first argument.  

This table contains the following keys:
- `outDir`: Output directory of the vMakefile, of type `Path`;
- `selProj`: Top-level project selected to be built;
- `selArch`: Architecture selected for the build;
- `selConf`: Configuration selected for the build;
- `data`: Data container of the current object;
- `rule`: Current rule, if within one;
- `comp`: Current component (top-level projects included), or component which contains the current rule, if within any;
- `proj`: Current top-level project, or the top-level project which contains the current component or rule, if within any;
- `arch`: Current architecture, if within one;
- `conf`: Current configuration, if within one;
- `opt`: Current command-line option, if within one.

When any other key is requested from the local environment table, it attempts data resolution (in its `data` key) if possible.  
Failure to retrieve a key results in an error, not a `nil` value as typical.  

Attempts to modify this table also result in an error.

## Build Process

A build targets a specific (top-level) project, architecture and configuration.  

vMake's goal is to construct the files listed in the output of the selected project. To do this, it employs the work item resolution algorithm.  

### Work Item Resolution

When vMake tries to figure out how to construct a file, it employs a simple resolution algorithm.  

First, it looks through all the rules of the current component to find one whose filter matches the path.  
*If more than one rule matches, it's considered an error.*  

If a rule wasn't found, it looks through the output list of all child components for a matching path.  
*If more than one component lists the path as an output, it's also considered an error.*  

If no rule or child component output was found to match the path, it restarts the algorithm from the parent component/project, if any, **but will only accept shared rules**.  

If a rule is found, a *work item* is created.  
This work item, or the entire child component which lists the path as output, becomes a dependency of whatever requested this path.  

If a work item is created (from a rule), the sources of this file are retrieved according to the rule and this algorithm is applied to them as well.  

If a source of an item cannot be found, **and it does not exist** in the filesystem, it is clearly an error.  

### Execution

The build process occurs by calling the `Action`s of every rule involved, for all the work items created.  
These functions can only use a subset of the vMake API which can be translated into shell commands.  

A work item will only be executed after its dependencies have successfully executed.  

### Partial & Full Builds

Having an overview of the whole project, vMake is capable of building only the pieces which are missing or out-of-date.  
This is the default behaviour.  

The opposite of this is a full build, which will execute every single work item to reconstruct every file possible.  
To force a full build, pass the `--full` command-line argument to the vMakefile.  

### Parallelism

With the aid of **GNU Parallel**, which is an **optional** depdendency, vMake is capable of performing builds in parallel.  

Firstly, the directed dependency graph represented by all the work items (some of which are grouped into `work load`s) is levelled. Items which have no dependencies, or all dependencies are up-to-date, are on level 0, and all the others are one level higher than their highest dependency.  
This means every work item can be executed as soon as possible and no later.  

The work items are executed and all the vMake functions they call are actually turned into shell commands which are logged.  
When all the items finished execution, vMake knows every single command (or sequence of) that needs to be invoked to perform the build, and precisely when it can be executed.  

These commands are written into files, separated by level, and then `parallel` is invoked with them.  

To use parallelism, pass the `--jobs=#`/`-j #` command-line argument to the vMakefile, where `#` is the desired number of jobs that can run in parallel. `0` means unlimited, and `1` means usual serial execution.  
To get the best performance out of parallel builds, it is recommended to provide the number of hardware threads to this argument. `0` usually yields equally good results, though.  

#### Errors

vMake is normally perfectly capable of reporting errors even when its actions are invoked indirectly by GNU Parallel, by reading its log files and correlating them with its record of commands and work items.  

It will report precisely which commands failed (together with rule and destination path), with status code.  
Note: It will report any number of failed commands, not just one.  

#### Performance

Parallel builds will be faster than serial builds, with the possible exception of some extreme edge cases.  
Admittedly, it cannot compete yet with the likes of `GNU Make` in parallel speed, but maybe it will get there eventually.  

#### Integration w/ Other Features

Both partial and full builds can be parallelized, and the computation of work item levels takes this choice into account as well.  
