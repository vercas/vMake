--[[
    Copyright (c) 2016 Alexandru-Mihai Maftei. All rights reserved.


    Developed by: Alexandru-Mihai Maftei
    aka Vercas
    http://vercas.com | https://github.com/vercas/vMake

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to
    deal with the Software without restriction, including without limitation the
    rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
    sell copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

      * Redistributions of source code must retain the above copyright notice,
        this list of conditions and the following disclaimers.
      * Redistributions in binary form must reproduce the above copyright
        notice, this list of conditions and the following disclaimers in the
        documentation and/or other materials provided with the distribution.
      * Neither the names of Alexandru-Mihai Maftei, Vercas, nor the names of
        its contributors may be used to endorse or promote products derived from
        this Software without specific prior written permission.


    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    CONTRIBUTORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
    FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
    WITH THE SOFTWARE.

    ---

    You may also find the text of this license in "LICENSE.md".
]]

local arg = _G.arg

if arg ~= nil and type(arg) ~= "table" then
    error("vMake error: 'arg' global variable, if present, must be a table containing command-line arguments as strings.")
end

if arg then
    for i = 1, #arg do
        if type(arg[i]) ~= "string" then
            error("vMake error: 'arg' table must be nil or a table containing command-line arguments as strnigs; it contains a "
                .. tostring(type(args[i])) .. " at position #" .. i .. ".")
        end
    end
end

local ______f, _____________t = function()return function()end end, {nil,
   [false]  = 'Lua 5.1',
   [true]   = 'Lua 5.2',
   [1/'-0'] = 'Lua 5.3',
   [1]      = 'LuaJIT' }
local luaVersion = _____________t[1] or _____________t[1/0] or _____________t[______f()==______f()]
--  Taken from http://lua-users.org/lists/lua-l/2016-05/msg00297.html

local vmake, vmake__call, getEnvironment, withEnvironment = {
    Version = "1.7.0",
    VersionNumber = 1007000,

    Debug = false,
    Silent = false,
    Verbose = false,
    Jobs = false,

    GlobalDataContainer = false,

    ShouldComputeGraph = true,
    ShouldDoWork = true,
    ShouldPrintGraph = false,
    ShouldClean = false,

    FullBuild = false,
    WorkGraph = false,
    MaxLevel = false,

    Capturing = false,
    CommandLog = false,

    JobsDir = false,
    ParallelOpts = false,
    HasGnuParallel = false,
}

local baseEnvironment = {
    ["_G"] = _G,    --  No need to hide this.
}

local codeLoc = 0
local LOC_DATA_EXP, LOC_RULE_SRC, LOC_RULE_FLT, LOC_RULE_ACT = 1, 2, 3, 4
local LOC_CMDO_HAN = 5

local curWorkItem = nil

vmake.Description = "vMake v" .. vmake.Version .. " [" .. vmake.VersionNumber
.. "] (c) 2016 Alexandru-Mihai Maftei, running under " .. luaVersion

pcall(require, "lfs")

SH_AND, SH_SEP, SH_RAW = {}, {}, {}

baseEnvironment.SH_AND, baseEnvironment.SH_SEP, baseEnvironment.SH_RAW = SH_AND, SH_SEP, SH_RAW

--  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --
--  Top-level Declarations
--  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --

--  Declared configurations, architectures and projects.
local configs, archs, projects, comps, rules, cmdlopts = {}, {}, {}, {}, {}, {}
local defaultProj, defaultArch, defaultConf, outDir = false, false, false, false

function Default(name, tolerant)
    assertType("string", name, "named default", 2)
    assertType({"nil", "boolean"}, tolerant, "tolerant", 2)

    local proj, arch, conf = projects[name], archs[name], configs[name]

    if proj then
        if defaultProj then
            error("vMake error: Default project is already chosen to be " .. tostring(defaultProj) .. "; cannot set it to " .. tostring(proj) .. ".", 2)
        end

        defaultProj = proj
    elseif arch then
        if defaultArch then
            error("vMake error: Default architecture is already chosen to be " .. tostring(defaultArch) .. "; cannot set it to " .. tostring(arch) .. ".", 2)
        end

        defaultArch = arch
    elseif conf then
        if defaultConf then
            error("vMake error: Default configuration is already chosen to be " .. tostring(defaultConf) .. "; cannot set it to " .. tostring(conf) .. ".", 2)
        end

        defaultConf = conf
    else
        error("vMake error: There is no project, architecture or configuration named \"" .. name .. "\".", 2)
    end

    return Default
end

function OutputDirectory(val, forbidFunc)
    if outDir then
        error("vMake error: Output directory is already defined.", 2)
    end

    local allowedTypes = {"string", "Path", "function"}

    if forbidFunc then allowedTypes[3] = nil end

    local valType = assertType(allowedTypes, val, 2)

    if valType == "string" then
        val = vmake.Classes.Path(val, "d")
    end

    outDir = val
    return val
end

local validFileTypes = { f = true, d = true, U = true }

function Path(val, type)
    assertType("string", val, "path", 2)
    assertType({"nil", "string"}, type, "path type", 2)

    if #val < 1 then
        error("vMake error: Path string must be non-empty.", 2)
    end

    if type and not validFileTypes[type] then
        error("vMake error: Path type \"" .. type .. "\" is invalid.", 2)
    end

    return vmake.Classes.Path(val, type or 'U')
end
baseEnvironment.Path = Path

function FilePath(val)
    assertType("string", val, "path", 2)

    if #val < 1 then
        error("vMake error: Path string must be non-empty.", 2)
    end

    return vmake.Classes.Path(val, "f")
end
baseEnvironment.FilePath = FilePath

function DirPath(val)
    assertType("string", val, "path", 2)

    if #val < 1 then
        error("vMake error: Path string must be non-empty.", 2)
    end

    return vmake.Classes.Path(val, "d")
end
baseEnvironment.DirPath = DirPath

function Configuration(name)
    checkName(name, "configuration", 2)

    local res = vmake.Classes.Configuration(name)

    configs[name] = res
    configs[#configs + 1] = res

    return function(tab)
        assertType("table", tab, "configuration table", 2)

        for k, v in pairs(tab) do
            assertType("string", k, "table key", 2)

            res[k] = v
        end

        return res
    end
end

function GetConfiguration(name)
    assertType("string", name, "configuration name", 2)

    if #name < 1 then
        error("vMake error: Name of configuration must be non-empty.", 2)
    end

    return configs[name]
end
baseEnvironment.GetConfiguration = baseEnvironment.GetConfiguration

function Architecture(name)
    checkName(name, "architecture", 2)

    local res = vmake.Classes.Architecture(name)

    archs[name] = res
    archs[#archs + 1] = res

    return function(tab)
        assertType("table", tab, "architecture table", 2)

        for k, v in pairs(tab) do
            assertType("string", k, "table key", 2)
            
            res[k] = v
        end

        return res
    end
end

function GetArchitecture(name)
    assertType("string", name, "architecture name", 2)

    if #name < 1 then
        error("vMake error: Name of architecture must be non-empty.", 2)
    end

    return archs[name]
end
baseEnvironment.GetArchitecture = baseEnvironment.GetArchitecture

local function spawnProjectFunction(pType, tName, topLevel)
    return function(name)
        checkName(name, tName, 2)

        local res = vmake.Classes.Project(name, pType)

        if topLevel then
            projects[name] = res
            projects[#projects + 1] = res
        else
            comps[#comps + 1] = res
        end

        return function(tab)
            assertType("table", tab, tName .. " table", 2)

            for k, v in pairs(tab) do
                assertType({"string", "integer"}, k, tName .. " table key", 2)
                
                if type(k) == "string" then
                    res[k] = v
                end
            end

            for i = 1, #tab do
                res:AddMember(tab[i])
            end

            return res
        end
    end
end

Project = spawnProjectFunction("proj", "project", true)
Component = spawnProjectFunction("comp", "component")

function Rule(name)
    checkName(name, "rule", 2)

    local res = vmake.Classes.Rule(name)

    rules[#rules + 1] = res

    return function(tab)
        assertType("table", tab, "rule table", 2)

        for k, v in pairs(tab) do
            assertType("string", k, "table key", 2)
            
            res[k] = v
        end

        return res
    end
end

function CmdOpt(name)
    assertType("string", name, "command-line option long name", 2)

    if #name < 2 then
        error("vMake error: Command-line option long name must be at least two characters long.", 2)
    end

    if cmdlopts[name] then
        error("vMake error: Command-line option long name \"" .. name .. "\" conflicts with another.", 2)
    end

    local res = vmake.Classes.CmdOpt(name)

    cmdlopts[#cmdlopts + 1] = res
    cmdlopts[name] = res

    local func

    func = function(val)
        local valType = assertType({"string", "table"}, val, "command-line option table / short name", 2)

        if valType == "table" then
            for k, v in pairs(val) do
                assertType("string", k, "table key", 2)
                
                res[k] = v
            end

            return res
        else
            res.ShortName = val

            return func
        end
    end

    return func
end

function GlobalData(tab)
    if not vmake.GlobalDataContainer then
        vmake.GlobalDataContainer = vmake.Classes.WithData()
    end

    vmake.GlobalDataContainer.Data = tab
    --  Will work multiple times.
end

--  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --
--  Utilitary Functions
--  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --

function typeEx(val)
    local t = type(val)

    if t ~= "table" then
        return t
    else
        local class = val.__class

        if class then
            return vmake.Classes[class] or t
            --  This will not work for classes that are not actually declared.
        else
            return t
        end
    end
end
baseEnvironment.type = baseEnvironment.typeEx
--  Note the alias!

local function escapeForShell(s)
    if #s < 1 then
        return "\"\""
    end

    s = s:gsub('"', "\\\"")

    if s:find("[^a-zA-Z0-9%+%-%*/=%.,_\"]") then
        return '"' .. s .. '"'
    end

    return s
end

--  --  --  --  --  --
--  Error Handling  --
--  --  --  --  --  --

function MSG(...)
    if not vmake.Verbose then
        return
    end

    local items = {...}

    for i = 1, #items do
        items[i] = tostring(items[i])
    end

    print(table.concat(items))
end
baseEnvironment.MSG = MSG

local function prettyString(val)
    if type(val) == "string" then
        return string.format("%q", val)
    else
        return tostring(val)
    end
end

local function printTable(t, append, indent, done)
    local myIndent = string.rep("\t", indent)

    for key, value in pairs(t) do
        append(myIndent)
        append(prettyString(key))

        if typeEx(value) == "table" and not done[value] then
            done[value] = true

            local ts = tostring(value)

            if ts:sub(1, 9) == "table: 0x" then
                append ": "
                append(ts)
                append "\n"
                printTable(value, append, indent + 1, done)
            else
                append " = "
                append(ts)
                append "\n"
            end
        else
            append " = "
            append(prettyString(value))
            append "\n"
        end
    end
end

local function printEndData(self, indent, out)
    indent = indent or 0

    local myIndent = string.rep("\t", indent)

    local res = { myIndent, "ERROR:\t", self.Error, "\n" }
    local function append(val, blergh, ...)
        res[#res + 1] = val

        if blergh then
            append(blergh, ...)
        end
    end

    myIndent = myIndent .. "\t"

    for i = 1, #self.Stack do
        local info, appendSource = self.Stack[i]
        
        append(myIndent)
        append(tostring(i))
        append "\t"

        if vmake.Verbose or vmake.Debug then
            function appendSource()
                append "\n"
                append(myIndent)
                append "\t  location: "

                if info.what ~= "C" then
                    append(info.short_src or info.source)

                    if info.currentline then
                        append ":"
                        append(tostring(info.currentline))
                    end
                    
                    append "\n"

                    if info.what == "Lua" and info.linedefined and (info.linedefined ~= info.currentline or info.lastlinedefined ~= info.currentline) then
                        --  This hides the definition of inline functions that will contain the erroneous line of code anyway.
                        --  Also excludes C code and main chunks, which show placeholder values there.

                        append(myIndent)
                        append "\t  definition at "

                        append(tostring(info.linedefined))

                        if info.lastlinedefined then
                            append "-"
                            append(tostring(info.lastlinedefined))
                        end
                
                        append "\n"
                    end
                else
                    append "C\n"
                end
            end
        else
            function appendSource()
                append "\t"

                if info.what ~= "C" then
                    append "  "
                    append(info.short_src or info.source)

                    if info.currentline then
                        append ":"
                        append(tostring(info.currentline))
                    end

                    if info.what == "Lua" and info.linedefined and (info.linedefined ~= info.currentline or info.lastlinedefined ~= info.currentline) then
                        --  This hides the definition of inline functions that will contain the erroneous line of code anyway.
                        --  Also excludes C code and main chunks, which show placeholder values there.

                        append "\t  def. at "

                        append(tostring(info.linedefined))

                        if info.lastlinedefined then
                            append "-"
                            append(tostring(info.lastlinedefined))
                        end
                    end
                
                    append "\n"
                else
                    append "  [C]\n"
                end
            end
        end

        if info.istailcall then
            append "tail calls..."

            if info.short_src or info.source then
                appendSource()
            else
                append "\n"
            end
        elseif info.name then
            --  This is a named function!

            append(info.namewhat)
            append "\t"
            append(info.name)
            appendSource()
        elseif info.what == "Lua" then
            --  Unnamed Lua function = anonymous

            append "anonymous function"
            appendSource()
        elseif info.what == "main" then
            --  This is the main chunk of code that is executing.

            append "main chunk"
            appendSource()
        elseif info.what == "C" then
            --  This might be what invoked the main chunk.

            append "unknown C code\n"
        end

        --  Now, upvalues, locals, parameters...

        if info.what ~= "C" and (vmake.Verbose or vmake.Debug) then
            --  Both main chunk and Lua functions can haz these.

            append(myIndent)
            append "\t  "

            if info.nparams == 1 then
                append "1 parameter; "
            else
                append(tostring(info.nparams))
                append " parameters; "
            end

            if #info._locals - info.nparams == 1 then
                append "1 local; "
            else
                append(tostring(#info._locals - info.nparams))
                append " locals; "
            end

            if info.nups == 1 then
                append "1 upvalue\n"
            else
                append(tostring(info.nups))
                append " upvalues\n"
            end

            local extraIndent = myIndent .. "\t\t"
            local done = { [_G] = true, [vmake] = true, }

            for j = 1, #info._locals do
                local key, value = info._locals[j].name, info._locals[j].value

                append(extraIndent)
                append(prettyString(key))

                if typeEx(value) == "table" and not done[value] then
                    done[value] = true

                    local ts = tostring(value)

                    if ts:sub(1, 9) == "table: 0x" then
                        append ": "
                        append(ts)
                        append "\n"
                        printTable(value, append, indent + 4, done)
                    else
                        append " = "
                        append(ts)
                        append "\n"
                    end
                else
                    append " = "
                    append(prettyString(value))
                    append "\n"
                end
            end

            if info._upvalues then
                for j = 1, #info._upvalues do
                    local key, value = info._upvalues[j].name, info._upvalues[j].value

                    append(extraIndent)
                    append(prettyString(key))

                    if typeEx(value) == "table" and not done[value] then
                        done[value] = true

                        local ts = tostring(value)

                        if ts:sub(1, 9) == "table: 0x" then
                            append ": "
                            append(ts)
                            append "\n"
                            printTable(value, append, indent + 4, done)
                        else
                            append " = "
                            append(ts)
                            append "\n"
                        end
                    else
                        append " = "
                        append(prettyString(value))
                        append "\n"
                    end
                end
            end
        end
    end

    res = table.concat(res)

    if out then
        return out(res)
    else
        return res
    end
end

local function queuefunc(fnc, functionlist, donefunctions)
    if donefunctions[fnc] then return end

    functionlist[#functionlist+1] = fnc
    donefunctions[fnc] = true
end

function GatherEndState(err)
    local functionlist, donefunctions = {}, {}

    local stack, thesaurus = {}, {}

    local i = 2

    while true do
        local info = debug.getinfo(i)

        if not info then
            break
        end

        stack[#stack+1] = info
        info._stackpos = i

        if info.func then
            thesaurus[info.func] = info
            queuefunc(info.func, functionlist, donefunctions)
            info.func = tostring(info.func)
        end

        --if info.what == "Lua" then
        info._locals = {}
        local locals = info._locals

        local j = 1

        while true do
            local n, v = debug.getlocal(i, j)

            if not n then break end

            locals[#locals+1] = {name=n,value=v}

            if type(v) == "function" then
                queuefunc(v, functionlist, donefunctions)
                locals[#locals].value = tostring(locals[#locals].value)
            end

            j = j + 1
        end
        --end

        i = i + 1
    end

    for i = 1, #functionlist do
        local fnc = functionlist[i]

        local info

        if thesaurus[fnc] then
            info = thesaurus[fnc]
        else
            info = debug.getinfo(fnc)
            thesaurus[fnc] = info
        end

        local ups = {}
        info._upvalues = ups

        for j = 1, info.nups do
            local n, v = debug.getupvalue(fnc, j)

            ups[#ups+1] = {name=n,value=v}

            if type(v) == "function" then
                queuefunc(v, functionlist, donefunctions)
                ups[#ups].value = tostring(ups[#ups].value)
            end
        end
    end

    local newthesaurus = {}

    for k, v in pairs(thesaurus) do
        newthesaurus[tostring(k)] = v
    end

    return { Stack = stack, Thesaurus = newthesaurus, Error = err, ShortTrace = debug.traceback(nil, 2), Print = printEndData }
end

do
    --  A small workaround around old xpcall versions.

    local foo = 1

    xpcall(
        function(arg)
            if arg == "bar" then
                foo = 2
            else
                foo = 0
            end
        end,
        function(err)
            io.stderr:write("This really shouldn't have happened:\n", err, "\n")
            os.exit(-100)
        end,
        "bar")

    assert(foo ~= 1, "'foo' should have changed!")

    if foo == 0 then
        MSG("xpcall doesn't seem to support passing arguments; working around it.")

        function vcall(inner_function, ...)
            local wrapped_args = {...}

            local function wrapper_function()
                return inner_function(unpack(wrapped_args))
            end

            local ret = {xpcall(wrapper_function, GatherEndState)}

            if ret[1] then
                --  Call succeeded.

                table.remove(ret, 1)

                return { Return = ret }
            else
                --  Call failed!

                return ret[2]
            end
        end
    else
        function vcall(fnc, ...)
            local ret = {xpcall(fnc, GatherEndState, ...)}

            if ret[1] then
                --  Call succeeded.

                table.remove(ret, 1)

                return { Return = ret }
            else
                --  Call failed!

                return ret[2]
            end
        end
    end
end

if setfenv then
    local cache = {}

    function withEnvironment(f, env)
        if cache[f] and cache[f][env] then
            return cache[f][env]
        end

        local bytecode = string.dump(f)

        --  TODO: Get function info.

        local new, err = loadstring(bytecode)

        if not new then
            error("vMake internal error: Failed to copy function " .. "<TODO>" .. " to change its environment: " .. err, 1)
        end

        setfenv(new, env)

        local i, nameN = 1

        repeat
            nameN = debug.getupvalue(new, i)

            if not nameN then
                break
            end

            local j, nameO, temp = 1

            repeat
                nameO, temp = debug.getupvalue(f, j)

                if nameO == nameN then
                    debug.setupvalue(new, i, temp)

                    break
                end

                j = j + 1
            until not nameO

            if not nameO then
                error("vMake internal error: Failed to set upvalue \"" .. nameN .. "\" of function " .. "<TODO>", 1)
            end

            i = i + 1
        until not nameN

        if cache[f] then
            cache[f][env] = new
        else
            cache[f] = { [env] = new }
        end

        cache[new] = { [env] = new }
        --  Yup, cache this one as well.

        return new
    end
else
    local cache = {}

    function getfenv(f)
        local i, name, val = 1

        repeat
            name, val = debug.getupvalue(f, i)

            if name == "_ENV" then
                return val
            end

            i = i + 1
        until not name

        return nil
    end

    function withEnvironment(f, env)
        if cache[f] and (cache[f][env] or cache[f][true]) then
            return cache[f][env] or cache[f][true]
        end

        if not getfenv(f) then
            if cache[f] then
                cache[f][true] = f
            else
                cache[f] = { [true] = f }
            end

            return f
        end

        --  So it has an environment, time to do the heavy lifting.

        local bytecode = string.dump(f)

        --  TODO: Get function info.

        local new, err = load(bytecode, "temp", "b", env)

        if not new then
            error("vMake internal error: Failed to copy function " .. "<TODO>" .. " to change its environment: " .. err, 1)
        end

        local i, nameN, temp = 1

        repeat
            nameN, temp = debug.getupvalue(new, i)

            if not nameN then
                break
            elseif nameN ~= "_ENV" then
                local j, nameO = 1

                repeat
                    nameO = debug.getupvalue(f, j)

                    if nameO == nameN then
                        debug.upvaluejoin(new, i, f, j)

                        break
                    end

                    j = j + 1
                until not nameO

                if not nameO then
                    error("vMake internal error: Failed to restore upvalue \"" .. nameN .. "\" of function " .. "<TODO>", 1)
                end
            elseif temp ~= env then
                --  This can happen if _ENV is not the first upvalue, as `load` sometimes (wrongly) assumes.

                debug.upvaluejoin(new, i, function() return env() end, 1)
                --  Dummy function will suffice.
            end

            i = i + 1
        until not nameN

        if cache[f] then
            cache[f][env] = new
        else
            cache[f] = { [env] = new }
        end

        cache[new] = { [env] = new }
        --  Yup, cache this one as well.

        return new
    end
end

function assertTypeEx(tname, valType, val, vname, errlvl)
    assert(type(valType) == "string", "vMake internal error: Argument #2 to 'assertType' should be a string.")

    if type(tname) == "string" then
        if valType ~= tname then
            error("vMake error: Type of " .. vname .. " should be '" .. tname .. "', not '" .. valType .. "'.", errlvl + 1)
        end
    elseif type(tname) == "table" then
        assert(#tname > 0, "vMake internal error: Argument #1 to 'assertType' should have a length greater than zero.")

        for i = #tname, 1, -1 do
            local tname2 = tname[i]

            assert(type(tname2) == "string", "vMake internal error: Argument #1 to 'assertType' should be an array of strings.")

            if tname2 == "integer" then
                if valType == "number" and val % 1 == 0 then
                    return valType
                end

                --  Else just move on to the next type. No biggie.
            elseif valType == tname2 then
                return valType
            end
        end

        local tlist = "'" .. tname[1] .. "'"

        for i = 2, #tname - 1 do
            tlist = tlist .. ", '" .. tname[i] .. "'"
        end

        if #tname > 1 then
            tlist = tlist .. ", or '" .. tname[#tname] .. "'"
        end

        error("vMake error: Type of " .. vname .. " should be " .. tlist .. ", not '" .. valType .. "'.", errlvl + 1)
    else
        error("vMake internal error: Argument #1 to 'assertType' should be a string or an array of strings, not a '" .. type(tname) .. ".")
    end

    return valType
end

function assertType(tname, val, vname, errlvl)
    return assertTypeEx(tname, typeEx(val), val, vname, errlvl and (errlvl + 1) or 1)
end
baseEnvironment.assertType = assertType

function checkName(name, obj, errlvl)
    assertType("string", name, obj .. " name", errlvl + 1)

    if #name < 1 then
        error("vMake error: Name of " .. obj .. " must be non-empty.", errlvl + 1)
    end

    if configs[name] then
        error("vMake error: Name of " .. obj .. " \"" .. name .. "\" conflicts with an already-defined configuration.", errlvl + 1)
    elseif archs[name] then
        error("vMake error: Name of " .. obj .. " \"" .. name .. "\" conflicts with an already-defined architecture.", errlvl + 1)
    elseif projects[name] then
        error("vMake error: Name of " .. obj .. " \"" .. name .. "\" conflicts with an already-defined project.", errlvl + 1)
    end
end

function table.shallowcopy(tab)
    local res = {}

    for k, v in pairs(tab) do
        res[k] = v
    end

    return res
end

function table.copyarray(tab)
    local res, len = {}, #tab

    for i = 1, len do
        res[i] = tab[i]
    end

    return res
end

function table.isarray(tab)
    local len = #tab

    for k, v in pairs(tab) do
        if type(k) ~= "number" or k < 1 or k > len or k % 1 ~= 0 then
            return false
        end
    end

    return true
end

function table.tostring(t, indent)
    indent = indent or 0

    local res = {}
    local function append(val)
        res[#res + 1] = val
    end

    printTable(t, append, indent, { [_G] = true, [vmake] = true })

    return table.concat(res);
end

do
    local validTrueStrings  = { ["true"]  = true, yes = true, on  = true }
    local validFalseStrings = { ["false"] = true, no  = true, off = true }

    function toboolean(val)
        local lVal = string.lower(val)

        if validTrueStrings[lVal] then
            return true
        elseif validFalseStrings[lVal] then
            return false
        end
    end
end

function string.trim(s)
    return s:match("^%s*(.-)%s*$")
end

function string.split(s, pattern, plain, n)
    --  Borrowed from https://github.com/stevedonovan/Penlight/blob/master/lua/pl/utils.lua#L172

    local i1, res = 1, {}

    if not pattern then pattern = plain and ' ' or "%s+" end
    if pattern == '' then return {s} end

    while true do
        local i2, i3 = s:find(pattern, i1, plain)

        if not i2 then
            local last = s:sub(i1)

            if last ~= '' then
                table.insert(res, last)
            end

            if #res == 1 and res[1] == '' then
                return {}
            else
                return res
            end
        else
            table.insert(res, s:sub(i1, i2 - 1))

            if n and #res == n then
                res[#res] = s:sub(i1)

                return res
            end

            i1 = i3 + 1
        end
    end
end

function string.iteratesplit(s, pattern, plain, n)
    local cnt, i1, i2, i3, res = 0, 1

    if not pattern then pattern = plain and ' ' or "%s+" end
    if pattern == '' then return {s} end

    return function()
        if not i1 then return end
        --  Means the end was reached.

        i2, i3 = s:find(pattern, i1, plain)

        if not i2 then
            local last = s:sub(i1)
            i1 = nil

            return last
        else
            cnt = cnt + 1

            if n and cnt == n then
                return s:sub(i1)
            end

            local res = s:sub(i1, i2 - 1)
            i1 = i3 + 1

            return res, s:sub(i2, i3)
        end
    end
end

--  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --
--  Class System
--  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --

do
    local metamethods = {
        "add", "sub", "mul", "div", "mod", "pow", "unm", "concat", "len",
        "eq", "lt", "le", "gc", "tostring", "call"
    }

    for i = 1, #metamethods do
        metamethods[i] = "__" .. metamethods[i]
    end

    --  Will actually store the classes.
    local classStore = {}

    --  Should be quick.
    local propfuncs = {}

    --  Will hold the class bases metatables.
    local classBases = {}

    --  Inheritance table.
    local inheritance = {}
    --  Parents table.
    local parents = {}

    --  Prevent malicious changes.
    vmake.Classes = setmetatable({}, {
        __index = function(self, key)
            return classStore[key]
        end,

        __newindex = function()
            error("vMake error: Invalid operation; cannot change the vmake.Classes table.")
        end,

        __metatable = "Nope."
    })

    local function addInheritance(cName, cParent)
        if cParent then
            if inheritance[cParent] then
                table.insert(inheritance[cParent], cName)
            else
                inheritance[cParent] = { cName }
            end

            addInheritance(cName, classStore[cParent].__parent and classStore[cParent].__parent.__name)
        else
            if inheritance[true] then
                table.insert(inheritance[true], cName)
            else
                inheritance[true] = { cName }
            end
        end
    end

    local function addParent(cName, cParent)
        parents[cName] = cParent
    end

    local function makePropFunc(prop, name, base)
        local pget, pset, povr, pret, ptyp = prop.get, prop.set, prop.OVERRIDE, prop.RETRIEVE, prop.TYPE

        local evname = "__on_update__" .. name

        local fnc

        if povr then
            if ptyp then
                pset = function(self, val, errlvl)
                    if typeEx(val) ~= ptyp then
                        error("vMake Classes error: Property \"" .. name .. "\" value must be of type " .. tostring(ptyp), errlvl + 1)
                    end

                    rawset(self, povr, val)
                end
            else
                pset = function(self, val)
                    rawset(self, povr, val)
                end
            end

            pget = function(self)
                return rawget(self, povr)
            end

            prop.get, prop.set = pget, pset
        elseif pret then
            pget = function(self)
                return rawget(self, pret)
            end

            prop.get = pget
        end

        if pget then
            if pset then
                if ptyp then
                    fnc = function(self, write, val, errlvl)
                        if not errlvl then errlvl = 2 else errlvl = errlvl + 1 end

                        if write then
                            if typeEx(val) ~= ptyp then
                                error("vMake Classes: Property \"" .. name .. "\" value must be of type " .. tostring(ptyp), errlvl)
                            end

                            pset(self, val, errlvl)

                            if self[evname] then
                                self[evname](self, val, errlvl)
                            end
                        else
                            return pget(self, errlvl)
                        end
                    end
                else
                    fnc = function(self, write, val, errlvl)
                        if not errlvl then errlvl = 2 else errlvl = errlvl + 1 end

                        if write then
                            pset(self, val, errlvl)

                            if self[evname] then
                                self[evname](self, val, errlvl)
                            end
                        else
                            return pget(self, errlvl)
                        end
                    end
                end
            else
                fnc = function(self, write, errlvl)
                    if not errlvl then errlvl = 2 else errlvl = errlvl + 1 end

                    if write then
                        error("vMake Classes: Property \"" .. name .. "\" has no setter!", errlvl)
                    else
                        return pget(self, errlvl)
                    end
                end
            end
        else
            return false
        end

        propfuncs[prop] = fnc
    end

    local function spawnClass(cName, cParentName, cBase)
        local cParent, cParentBase

        local __base_new_indexer, __base_indexer

        for k, v in pairs(cBase) do
            if type(v) == "table" then
                makePropFunc(v, k, cBase)
            end
        end

        if cParentName then
            --  By now, they MUST exist.
            cParent = classStore[cParentName]
            cParentBase = classBases[cParentName]

            __base_indexer = cParentBase.__index
            __base_new_indexer = cParentBase.__newindex
        end

        local __new_indexer, __indexer = cBase.__newindex or rawset, cBase.__index or __base_indexer

        local _base_0 = {
            __metatable = "What do you want to do with this class instance's metatable?",

            __index = function(self, key, errlvl)
                if key == "__class" then
                    return classBases[cName].__class
                end
                
                local res = rawget(cBase, key)
                --  Will look for a property.

                if not errlvl then errlvl = 1 end

                if propfuncs[res] then
                    return propfuncs[res](self, false, nil, errlvl + 1)
                end

                if res == nil and __indexer then
                    return __indexer(self, key, errlvl + 1)
                end

                return res
            end,

            __newindex = function(self, key, val, errlvl)
                local res = rawget(cBase, key)
                --  Will look for a property.

                if not errlvl then errlvl = 1 end

                if res ~= nil and propfuncs[res] then
                    return propfuncs[res](self, true, val, errlvl + 1)
                elseif res == nil and __base_new_indexer then
                    --  If nil, keep looking up the hierarchy for a valid property.
                    --  If none is found, it will eventually just set the value on the table.
                    return __base_new_indexer(self, key, val, errlvl + 1)
                else
                    return __new_indexer(self, key, val, errlvl + 1)
                end
            end
        }

        for i = #metamethods, 1, -1 do
            local mm = metamethods[i]

            if cBase[mm] then
                _base_0[mm] = cBase[mm]
            elseif cParentBase and cParentBase[mm] then
                _base_0[mm] = cParentBase[mm]
            end
        end

        local __init = cBase.__init

        local function __init2(...)
            if cParent then
                cParent.__inheritedInitializer(...)
            end

            __init(...)
        end

        local actualInitializer = (cBase.__init_inherit ~= false) and __init2 or __init
        
        local _class_0 = setmetatable({
            __init = __init,    --  Poor attempt to prevent retarded usage by changing that function...
            __base = cBase,
            __name = cName,
            __parent = cParent,


            __inheritedInitializer = actualInitializer,
        }, {
            __metatable = "Why do you need to work with this class's metatable?",

            __index = function (cls, name)
                local val = rawget(cBase, name)

                if val == nil and cParent then
                    return cParent[name]
                else
                    return val
                end
            end,

            __call = function (cls, ...)
                local new = setmetatable({ }, _base_0)

                cls.__inheritedInitializer(new, ...)

                return new
            end,
        })

        _base_0.__class = _class_0

        classBases[cName] = _base_0

        addInheritance(cName, cParentName)
        
        return _class_0
    end

    --  Formal class creation function.
    function vmake.CreateClass(cName, cParentName, cBase)
        if type(cName) == "table" and cParentName == nil and cBase == nil then
            return vmake.CreateClass(cName.Name, cName.ParentName, cName.Base)
        end

        if type(cName) ~= "string" then
            error("Class name must be a string, not a " .. type(cName) .. ".")
        else
            if classStore[cName] then
                error("Class named \"" .. tostring(cName) .. "\" already defined!!")
            end
        end

        if cParentName ~= nil and type(cParentName) ~= "string" then
            error("Parent class name must be nil or a string, not a " .. type(cParentName) .. ".")
        elseif cParentName and not classStore[cParentName] then
            error("Specified parent class does not exist (yet?)!")
        end

        if type(cBase) == "function" then
            cBase = cBase()
            --  "Unpack" the function which is supposed to return a table.

            if type(cBase) ~= "table" then
                error("Class base unpacker must return a table, not a " .. type(cBase) .. ".")
            end
        elseif type(cBase) ~= "table" then
            error("Class base must be a table or a function that returns a table (referred to as \"unpacker\"), not a " .. type(cBase) .. ".")
        end

        local class

        class = spawnClass(cName, cParentName, cBase)

        classStore[cName] = class
        classStore[class] = cName

        return class
    end

    --  Returns the name of each class that inherits from the given class.
    --  True = all classes.
    function vmake.GetChildrenOf(cls)
        if type(cls) == "string" then
            if classStore[cls] then
                return inheritance[cls] or {}
            else
                error("No class named \"" .. cls .. "\" declared (yet?).")
            end
        elseif cls == true then
            return inheritance[true] or {}
        else
            error("Invalid argument! Must be a valid class name or true for listing defined classes!")
        end
    end

    --  Returns the name of the parent of the given class.
    function vmake.GetParentOf(cls)
        if type(cls) == "string" then
            if classStore[cls] then
                return parents[cls]
            else
                error("No class named \"" .. cls .. "\" declared (yet?).")
            end
        else
            error("Invalid argument! Must be a valid class name.")
        end
    end
end

--  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --
--  Class Declarations
--  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --

local getListContainer
local assurePathInfo
local setDataOwner, setDataNext, mergeData
local linkDataWithOther
local normalizeConfigBase, normalizeArchBase
local setProjectOwner, getProjectRules, getProjectComponents
local setRuleOwner
local incrementCmdoCount
local setWorkEntityDone, setWorkEntityOutdated, setWorkEntityLevel
local setWorkItemSource

--  --  --  --  --
--  Path Class  --
--  --  --  --  --

do
    local typesEqualities = {
        f = {
            f = true,
            d = false,
            U = true,
        },
        d = {
            f = false,
            d = true,
            U = true,
        },
        U = {
            f = true,
            d = true,
            U = true,
        },
    }

    -- local function trimStartCurrentDirectory(str)
    --     if str:sub(1, 2) == "./" then
    --         return str:sub(3)
    --     else
    --         return str
    --     end
    -- end

    local function trimStartDirectory(str)
        return str:match("^/*[^/]+/(.-)$")
    end

    local function trimEndDirectory(str)
        return str:match("^(.-)/[^/]+/*$")
    end

    local function getFileName(str)
        return str:match("^.-/([^/]+)/*$")
    end

    local function canonizePath(str)
        local i1, res, len, frag = 1, {}, 0

        if #str < 2 then
            return str
        end

        while true do
            local i2, i3 = str:find("/+", i1, false)

            frag = str:sub(i1, i2 and (i2 - 1) or nil)

            if frag == ".." and len > 0 and res[len] ~= ".." then
                if res[len] ~= "" and res[len] ~= "." then
                    res[len] = nil

                    len = len - 1
                end

                --  Else do nothing.
            elseif frag ~= '.' then
                len = len + 1

                res[len] = frag
            end

            if i2 then
                i1 = i3 + 1
            else
                if len >= 2 and #(res[len]) == 0 and #(res[len - 1]) > 0 then
                    res[len] = nil

                    len = len - 1
                end

                if len == 0 or (len == 1 and res[1] == "") then
                    return str:sub(1, 1) == '/' and '/' or '.'
                else
                    return table.concat(res, '/')
                end
            end
        end
    end

    local function isPathAbsolute(str)
        return str[1] == '/'
    end

    local _key_path_valu, _key_path_abso, _key_path_leng, _key_path_type = {}, {}, {}, {}
    local _key_path_mtim, _key_path_exst = {}, {}

    vmake.CreateClass("Path", nil, {
        __init = function(self, val, type, mtime)
            self[_key_path_valu] = canonizePath(val)
            self[_key_path_abso] = isPathAbsolute(self[_key_path_valu])
            self[_key_path_leng] = #self[_key_path_valu]
            self[_key_path_type] = type or 'U'
            self[_key_path_mtim] = mtime or false
            self[_key_path_exst] = mtime and true or nil
        end,

        __tostring = function(self)
            return self[_key_path_valu]
        end,

        Equals = function(self, othr)
            if othr == nil then
                return false
            end

            local othrType = typeEx(othr)

            if othrType == "string" then
                if self[_key_path_type] == 'f' then
                    --  If the other path ends with a slash, it's definitely not a file.
                    return othr:sub(-1) ~= "/" and self[_key_path_valu] == canonizePath(othr)
                else
                    return self[_key_path_valu] == canonizePath(othr)
                end
            elseif othrType == "Path" then
                local compat = typesEqualities[self[_key_path_type]][othr[_key_path_type]]

                if compat then
                    return self[_key_path_valu] == othr[_key_path_valu]
                else
                    if vmake.Debug and self[_key_path_valu] == othr[_key_path_valu] then
                        error("vMake error: Paths have incompatible types but identical value: " .. self[_key_path_valu], 2)
                    else
                        return false
                    end
                end
            end

            error("vMake error: Nonsensical comparison between a Path and a '" .. othrType .. "'.", 2)
        end,

        __eq = function(self, othr)
            if not rawget(othr, _key_path_type) then
                if vmake.Debug then
                    error("vMake error: Nonsensical comparison between a Path and a '" .. typeEx(othr) .. "'.", 2)
                else
                    return false
                end
            end

            local compat = typesEqualities[self[_key_path_type]][othr[_key_path_type]]

            if compat then
                return self[_key_path_valu] == othr[_key_path_valu]
            else
                if vmake.Debug and self[_key_path_valu] == othr[_key_path_valu] then
                    error("vMake error: Paths have incompatible types but identical value: " .. self[_key_path_valu], 2)
                else
                    return false
                end
            end
        end,

        __add = function(self, othr)
            if self[_key_path_type] == "f" then
                error("vMake error: You cannot append a path to a file.", 2)
            end

            local otherPathType = 'U'
            local othrType = assertType({"string", "Path"}, othr, "other path", 2)

            if othrType == "Path" then
                otherPathType = othr[_key_path_type]
                othr = othr[_key_path_valu]
            elseif #othr < 1 then
                error("vMake error: Path to append must be non-empty.", 2)
            end

            if isPathAbsolute(othr) then
                error("vMake error: Cannot append an absolute path to any other path.", 2)
            end

            return vmake.Classes.Path(self[_key_path_valu] .. '/' .. othr, otherPathType)
        end,

        __concat = function(left, right)
            local leftType = assertType({"string", "number", "Path"}, left, "left operand", 2)

            if leftType == "Path" then
                local rightType = assertType({"string", "number"}, right, "right operand", 2)

                if rightType == "number" then
                    right = tostring(right)
                end

                return vmake.Classes.Path(left[_key_path_valu] .. right, 'U')
            else
                --  Right operand has to be the path.

                if leftType == "number" then
                    left = tostring(left)
                end

                return left .. right[_key_path_valu]
            end
        end,

        Absolute         = { RETRIEVE = _key_path_abso },
        Length           = { RETRIEVE = _key_path_leng },
        Type             = { RETRIEVE = _key_path_type },
        ModificationTime = { RETRIEVE = _key_path_mtim },
        Exists           = { RETRIEVE = _key_path_exst },

        IsFile      = { get = function(self) return self[_key_path_type] == 'f' end },
        IsDirectory = { get = function(self) return self[_key_path_type] == 'd' end },
        IsUnknown   = { get = function(self) return self[_key_path_type] == 'U' end },

        IsCurrentDirectory = { get = function(self) return self[_key_path_valu] == '.' end },

        GetParent = function(self)
            local val = self[_key_path_valu]

            if val == "." or val == ".." or val == "/" then
                return nil
            end

            local res = vmake.Classes.Path(trimEndDirectory(val), "d")

            if self[_key_path_exst] then
                assurePathInfo(res)
            end

            return res
        end,

        GetName = function(self)
            local val = self[_key_path_valu]

            if val == "." or val == ".." or val == "/" then
                return self
            end

            return vmake.Classes.Path(getFileName(val), "U")
        end,

        StartsWith = function(self, other)
            local otherType = assertType({"string", "Path"}, other, "start path", 2)

            if otherType == "string" then
                other = canonizePath(other)
            elseif otherType == "Path" then
                other = other[_key_path_valu]
            end

            if #other > self[_key_path_leng] then
                return false
            end

            local i1, i2 = self[_key_path_valu]:find(other, 1, true)

            if not i1 or i1 ~= 1 then
                return false
            end

            if i2 == self[_key_path_leng] then
                return true
            elseif self[_key_path_valu]:sub(i2 + 1, i2 + 1) == '/' then
                --  Okay, this is correct.

                return true
            else
                return false
            end
        end,

        EndsWith = function(self, ...)
            local vals = {...}

            if #vals < 1 then
                error("vMake error: 'EndsWith' should receive at least one argument, besides the path itself.", 2)
            end

            for i = 1, #vals do
                local val = vals[i]
                local valType = assertType({"string", "Path"}, val, "end string #" .. i, 2)

                if valType == "string" then
                    if #val < 1 then
                        error("vMake error: Argument #" .. i .. " to 'EndsWith' must be a non-empty string or a path.", 2)
                    end

                    if val == self[_key_path_valu]:sub(-#val) then
                        return true
                    end
                else
                    --  It's a path, so it must be contained fully within a directory
                    --  in this path.

                    local len = val.Length
                    local len2 = self[_key_path_leng] - len

                    if self[_key_path_valu]:sub(len2, len2) == '/'
                        and val[_key_path_valu] == self[_key_path_valu]:sub(-len) then
                        return true
                    end
                end
            end

            return false
        end,

        TrimEnd = function(self, cnt)
            assertType("number", cnt, "count", 2)

            if cnt < 1 or cnt % 1 ~= 0 then
                error("vMake error: Argument #1 to 'TrimEnd' should be a positive integer.", 2)
            end

            local str = self[_key_path_valu]

            if cnt >= self[_key_path_leng] then
                error("vMake error: Argument #1 to 'TrimEnd' is too large, it leaves nothing in the path \""
                    .. str .. "\".", 2)
            end

            return vmake.Classes.Path(str:sub(1, self[_key_path_leng] - cnt), 'U')
            --  The type cannot be preserved here.
        end,

        RemoveExtension = function(self)
            local new = self[_key_path_valu]:match("^(.*)%.[^%.]-$")

            return new and vmake.Classes.Path(new, 'U') or nil
        end,

        ChangeExtension = function(self, ext)
            assertType("string", ext, "extension", 2)

            local new = self[_key_path_valu]:match("^(.*)%.[^%.]-$")

            return new and vmake.Classes.Path(new .. "." .. ext, 'U') or nil
        end,

        GetExtension = function(self)
            return self[_key_path_valu]:match("^.*%.([^%.]-)$")
        end,

        CheckExtension = function(self, ...)
            local vals = {...}

            if #vals < 1 then
                error("vMake error: 'CheckExtension' should receive at least one argument, besides the path itself.", 2)
            end

            local ext = self[_key_path_valu]:match("^.*%.([^%.]-)$")

            if not ext then
                --  No extension? Meh.

                return false
            end

            for i = #vals, 1, -1 do
                local val = vals[i]
                local valType = assertType({"string", "List"}, val, "extension #" .. i, 2)

                if valType == "string" then
                    if ext == val then
                        return ext
                    end
                else
                    if val:Any(function(val) return ext == val end) then
                        return true
                    end
                end
            end

            return false
        end,

        SkipDirs = function(self, cnt)
            assertType("number", cnt, "count", 2)

            if cnt < 1 or cnt % 1 ~= 0 then
                error("vMake error: Argument #1 to 'SkipDirs' should be a positive integer.", 2)
            end

            local str = self[_key_path_valu]

            for i = 1, cnt do
                str = trimStartDirectory(str)

                if #str < 1 then
                    error("vMake error: Path does not contain " .. tostring(cnt) .. " directories.", 2)
                end
            end

            return vmake.Classes.Path(str, self[_key_path_type])
            --  No harm in preserving the type, I suppose. :S
        end,

        Skip = function(self, other)
            local otherType = assertType({"string", "Path"}, other, "path to skip", 2)

            if otherType == "string" then
                other = canonizePath(other)
            elseif otherType == "Path" then
                other = other[_key_path_valu]
            end

            if #other > self[_key_path_leng] then
                error("vMake error: Path \"" .. tostring(self)
                    .. "\" cannot begin with \"" .. other
                    .. "\" because it is too short.", 2)
            end

            local i1, i2 = self[_key_path_valu]:find(other, 1, true)

            if not i1 or i1 ~= 1 then
                error("vMake error: Path \"" .. tostring(self)
                    .. "\" does not begin with \"" .. other .. "\".", 2)
            end

            if i2 == self[_key_path_leng] then
                return vmake.Classes.Path(".", self[_key_path_type])
            elseif self[_key_path_valu]:sub(i2 + 1, i2 + 1) == '/' then
                --  Okay, this is correct.

                return vmake.Classes.Path(self[_key_path_valu]:sub(i2 + 2), self[_key_path_type])
            else
                error("vMake error: Path \"" .. tostring(self)
                    .. "\" does not begin with \"" .. other .. "\".", 2)
            end
        end,

        Progress = function(self)
            local str, i = self[_key_path_valu], 2

            local function iterator()
                if not i then
                    return  --  Nothing, zee end.
                end

                local i1 = str:find("/", i, true)

                if i1 then
                    local res = str:sub(1, i1 - 1)

                    i = i1 + 1

                    return res
                else
                    i = nil

                    return str
                end
            end

            return iterator
        end,
    })

    function assurePathInfo(path, force)
        if path[_key_path_exst] and not force then
            return path
        end

        local oldCodeLoc = codeLoc; codeLoc = 0

        local type, mtime = fs.GetInfo(path)

        codeLoc = oldCodeLoc

        if type then
            path[_key_path_type] = type
            path[_key_path_mtim] = mtime

            path[_key_path_exst] = true
        else
            path[_key_path_exst] = false
        end

        return path
    end
end

--  --  --  --  --
--  List Class  --
--  --  --  --  --

do
    local _key_list_cont, _key_list_seld = {}, {}

    vmake.CreateClass("List", nil, {
        __init = function(self, sealed, template)
            if (sealed or template ~= nil) and type(template) ~= "table" then
                error("vMake error: List constructor's argument #2 must be a table, unless non-sealed.", 4)
            end

            rawset(self, _key_list_cont, template and table.copyarray(template) or {})
            rawset(self, _key_list_seld, sealed or false)
        end,

        __tostring = function(self)
            return "[List " .. tostring(self[_key_list_cont]) .. "]"
        end,

        Print = function(self, sep, conv)
            assertType({"nil", "string"}, sep, "separator", 2)
            assertType({"nil", "function"}, conv, "converter", 2)

            if not conv then conv = tostring end

            local stringz = sep and {} or {"[List Print", tostring(self[_key_list_cont])}
            local stringzLen = #stringz

            for i = 1, #self[_key_list_cont] do
                stringz[i + stringzLen] = conv(self[_key_list_cont][i])
            end

            if not sep then
                stringz[#stringz + 1] = "]"
            end

            return table.concat(stringz, sep or ' ')
        end,

        __index = function(self, key, errlvl)
            if type(key) == "number" then
                local cont = self[_key_list_cont]

                if key < 1 or key > #cont then
                    error("vMake error: Given numeric key to List is out of range.", errlvl + 1)
                end

                if key % 1 ~= 0 then
                    error("vMake error: Given numeric key to List is not an integer.", errlvl + 1)
                end

                return cont[key]
            end

            --  Whatever type of key this is, it is unacceptable.

            error("vMake error: Given key to a List is of invalid type '" .. type(key) .. "'.", errlvl + 1)
        end,

        __newindex = function(self, key, val, errlvl)
            local keyType = type(key)

            if keyType == "string" and key ~= "__class" then
                --  Yes, random string keys are allowed to annotate lists.

                return rawset(self, key, val)
            elseif keyType == "number" then
                if self[_key_list_seld] then
                    error("vMake error: List is sealed.", errlvl + 1)
                end

                local cont = self[_key_list_cont]

                if key < 1 or key > #cont then
                    error("vMake error: Given numeric key to List is out of range.", errlvl + 1)
                end

                if key % 1 ~= 0 then
                    error("vMake error: Given numeric key to List is not an integer.", errlvl + 1)
                end

                cont[key] = val
                return
            end

            error("vMake error: Given key to a List is of invalid type '" .. keyType .. "'.", errlvl + 1)
        end,

        Sealed = { RETRIEVE = _key_list_seld },

        Seal = function(self, tolerant)
            if not tolerant and self[_key_list_seld] then
                error("vMake error: List is already sealed.", 2)
            end

            self[_key_list_seld] = true

            return self
        end,

        __len = function(self)
            return #self[_key_list_cont]
        end,

        Length = {
            get = function(self, errlvl)
                return #self[_key_list_cont]
            end,
        },

        __add = function(self, othr)
            local othrType = assertType({"table", "List"}, othr, "other list", 2)

            if othrType == "List" then
                othr = othr[_key_list_cont]
            elseif not table.isarray(other) then
                error("vMake error: Table to concatenate with must be a pure array table.", 2)
            end

            local new = vmake.Classes.List(false, self[_key_list_cont])
            local arr, lenN, lenO = new[_key_list_cont], #new[_key_list_cont], #othr

            for i = 1, lenO do
                arr[lenN + i] = othr[i]
            end

            return new
        end,

        AppendMany = function(self, othr)
            local othrType = assertType({"table", "List"}, othr, "other list", 2)

            if othrType == "List" then
                othr = othr[_key_list_cont]
            elseif not table.isarray(othr) then
                error("vMake error: Table to concatenate with must be a pure array table.", 2)
            end

            if self[_key_list_seld] then
                error("vMake error: List is sealed.", 2)
            end

            local arr, lenS, lenO = self[_key_list_cont], #self[_key_list_cont], #othr

            for i = 1, lenO do
                arr[lenS + i] = othr[i]
            end

            return self
        end,

        Append = function(self, item)
            if self[_key_list_seld] then
                error("vMake error: List is sealed.", 2)
            end

            self[_key_list_cont][#self[_key_list_cont] + 1] = item

            return self
        end,

        AppendUnique = function(self, item)
            if self[_key_list_seld] then
                error("vMake error: List is sealed.", 2)
            end

            local lenS, this = #self[_key_list_cont], self[_key_list_cont]

            for i = 1, lenS do
                if this[i] == item then
                    return false
                end
            end

            this[lenS + 1] = item

            return self
        end,

        Where = function(self, pred)
            assertType("function", pred, "predicate", 2)

            local new = vmake.Classes.List()
            local othr, lenS, this = new[_key_list_cont], #self[_key_list_cont], self[_key_list_cont]

            for i = 1, lenS do
                local val = this[i]

                if pred(val) then
                    othr[#othr + 1] = val
                end
            end

            return new
        end,

        Any = function(self, pred)
            assertType({"nil", "function"}, pred, "predicate", 2)

            if pred == nil then
                --  Simple.

                return #self[_key_list_cont] > 0
            end

            local lenS, this = #self[_key_list_cont], self[_key_list_cont]

            for i = 1, lenS do
                if pred(this[i]) then
                    return true
                end
            end

            return false
        end,

        First = function(self, pred)
            assertType({"nil", "function"}, pred, "predicate", 2)

            if pred == nil then
                --  Simple.

                return self[_key_list_cont][1]
            end

            local lenS, this = #self[_key_list_cont], self[_key_list_cont]

            for i = 1, lenS do
                if pred(this[i]) then
                    return this[i]
                end
            end

            return nil
        end,

        Last = function(self, pred)
            assertType({"nil", "function"}, pred, "predicate", 2)

            local lenS, this = #self[_key_list_cont], self[_key_list_cont]

            if pred == nil then
                --  Simple.

                return this[lenS]
            end

            for i = lenS, 1, -1 do
                if pred(this[i]) then
                    return this[i]
                end
            end

            return nil
        end,

        Contains = function(self, val)
            local lenS, this = #self[_key_list_cont], self[_key_list_cont]

            for i = 1, lenS do
                if this[i] == val then
                    return true
                end
            end

            return false
        end,

        Copy = function(self)
            local new = vmake.Classes.List()
            local othr, lenS, this = new[_key_list_cont], #self[_key_list_cont], self[_key_list_cont]

            for i = 1, lenS do
                othr[i] = this[i]
            end

            return new
        end,

        Select = function(self, trans)
            assertType("function", trans, "transformer", 2)

            local new = vmake.Classes.List()
            local othr, lenS, this = new[_key_list_cont], #self[_key_list_cont], self[_key_list_cont]

            for i = 1, lenS do
                othr[i] = trans(this[i])
            end

            return new
        end,

        SelectUnique = function(self, trans)
            assertType("function", trans, "transformer", 2)

            local new = vmake.Classes.List()
            local othr, lenS, this = new[_key_list_cont], #self[_key_list_cont], self[_key_list_cont]

            for i = 1, lenS do
                local item, add = trans(this[i]), true

                for j = 1, #othr do
                    if othr[j] == item then
                        add = false
                        break
                    end
                end

                if add then
                    othr[#othr + 1] = item
                end
            end

            return new
        end,

        ForEach = function(self, action, extreme)
            assertType("function", action, "action", 2)

            local lenS, this = #self[_key_list_cont], self[_key_list_cont]

            for i = 1, lenS do
                extreme = action(this[i], extreme)
            end

            return self, extreme
        end,

        Unpack = function(self)
            return unpack(self[_key_list_cont])
        end,
    })

    function getListContainer(list)
        return list[_key_list_cont]
    end
end

--  --  --  --  --  --
--  Data Container  --
--  --  --  --  --  --

do
    local _key_data_base, _key_data_comp, _key_data_ownr, _key_data_next = {}, {}, {}, {}

    vmake.CreateClass("Data", nil, {
        __init = function(self, base)
            self[_key_data_base] = base or {}
            self[_key_data_comp] = {}
            self[_key_data_ownr] = false
            self[_key_data_next] = false
        end,

        __tostring = function(self)
            return "[Data Container " .. tostring(self[_key_data_base]) .. "]"
        end,

        __index = function(self, key, errlvl)
            assertType({"string", "number"}, key, "data key", errlvl + 1)

            local res = self:TryGet(key, errlvl + 1)

            if res ~= nil then
                return res
            end

            error("vMake error: Missing data item \"" .. tostring(key) .. "\".", errlvl + 1)
        end,

        TryGet = function(self, key, errlvl)
            local res = self[_key_data_comp][key]

            if res ~= nil then
                return res
            end

            res = self[_key_data_base][key]

            if res == nil then
                local nextData = self[_key_data_next]

                if nextData then
                    res = nextData:TryGet(key, errlvl + 1)
                end
            elseif type(res) == "function" then
                --  Functions are executed (once) to obtain the data. They better
                --  not return nil.

                res = withEnvironment(res, getEnvironment(self))

                local oldCodeLoc = codeLoc; codeLoc = LOC_DATA_EXP

                res = res()

                codeLoc = oldCodeLoc
            end

            self[_key_data_comp][key] = res
            --  No need to check for nil or something like that.
            
            return res
        end,

        Owner = { RETRIEVE = _key_data_ownr },
        Next  = { RETRIEVE = _key_data_next },
    })

    function setDataOwner(data, ownr, errlvl)
        local cur = data[_key_data_ownr]

        if not cur then
            data[_key_data_ownr] = ownr
        else
            error("vMake error: " .. tostring(data) .. " already belongs to " .. tostring(cur) .. "; cannot set owner again (to " .. tostring(ownr) .. ").", errlvl + 1)
        end
    end

    function setDataNext(data, next, errlvl)
        local cur = data[_key_data_next]

        if not cur or not next then
            data[_key_data_next] = next
        else
            error("vMake internal error: " .. tostring(data) .. " already links to " .. tostring(cur) .. "; cannot set next again (to " .. tostring(next) .. ").", errlvl + 1)
        end
    end

    function mergeData(data, new, errlvl)
        local base = data[_key_data_base]

        for k, v in pairs(new) do
            assertType({"string", "number"}, k, "merge data key", errlvl + 1)

            if base[k] ~= nil then
                error("vMake error: Data merge conflict - key \"" .. tostring(k) .. "\" already defined.", errlvl + 1)
            end

            base[k] = v
        end
    end
end

--  --  --  --  --
--  With  Data  --
--  --  --  --  --

do
    local _key_wida_data, _key_wida_dnxt = {}, {}

    vmake.CreateClass("WithData", nil, {
        __init = function(self)
            self[_key_wida_data] = vmake.Classes.Data()
            self[_key_wida_dnxt] = false

            setDataOwner(self[_key_wida_data], self, errlvl)
        end,

        Data = {
            get = function(self)
                return self[_key_wida_data]
            end,

            set = function(self, val, errlvl)
                local valType = assertType("table", val, "data", errlvl + 1)

                mergeData(self[_key_wida_data], val, errlvl + 1)
            end,
        },
    })

    function linkDataWithOther(this, other, errlvl)
        if this[_key_wida_data] then
            if other and other[_key_wida_data] then
                setDataNext(this[_key_wida_data], other[_key_wida_data], errlvl + 1)
            else
                setDataNext(this[_key_wida_data], false, errlvl + 1)
            end
        elseif this and other and other[_key_wida_data] then
            this[_key_wida_dnxt] = other[_key_wida_data]
        end
    end
end

--  --  --  --  --  --  --  --
--   Configuration  Class   --
--  --  --  --  --  --  --  --

do
    local _key_conf_name, _key_conf_base, _key_conf_aux = {}, {}, {}

    vmake.CreateClass("Configuration", "WithData", {
        __init = function(self, name)
            self[_key_conf_name] = name
            self[_key_conf_base] = false
            self[_key_conf_aux ] = false
        end,

        __tostring = function(self)
            local base = self[_key_conf_base]

            if type(base) == "string" then
                return "[Configuration " .. self[_key_conf_name] .. " : \"" .. base .. "\"]"
            elseif base then
                return "[Configuration " .. self[_key_conf_name] .. " : " .. base.Name .. "]"
            else
                return "[Configuration " .. self[_key_conf_name] .. "]"
            end
        end,

        Name = { RETRIEVE = _key_conf_name },
        Auxiliary = { OVERRIDE = _key_conf_aux, TYPE = "boolean" },

        Base = {
            get = function(self)
                return self[_key_conf_base]
            end,

            set = function(self, val, errlvl)
                if self[_key_conf_base] then
                    error("vMake error: " .. tostring(self) .. " has already defined its base.", errlvl + 1)
                end

                assertType({"string", "Configuration"}, val, "base", errlvl + 1)

                self[_key_conf_base] = val
                linkDataWithOther(self, val, errlvl + 1)
            end,
        },

        Hierarchy = function(self)
            local val = self

            local function iterator()
                local ret = val

                if val then
                    val = val.Base or nil
                end

                return ret
            end

            return iterator
        end,
    })

    function normalizeConfigBase(conf, errlvl)
        if type(conf[_key_conf_base]) == "string" then
            local base = configs[conf[_key_conf_base]]

            if base then
                conf[_key_conf_base] = base
                linkDataWithOther(conf, base, errlvl + 1)
            else
                error("vMake error: " .. tostring(conf) .. " defined with unknown base \"" .. conf[_key_conf_base] .. "\".", errlvl + 1)
            end
        else
            linkDataWithOther(conf, vmake.GlobalDataContainer, errlvl + 1)
        end
    end
end

--  --  --  --  --  --  --
--  Architecture Class  --
--  --  --  --  --  --  --

do
    local _key_arch_name, _key_arch_base, _key_arch_aux = {}, {}, {}

    vmake.CreateClass("Architecture", "WithData", {
        __init = function(self, name)
            self[_key_arch_name] = name
            self[_key_arch_base] = false
            self[_key_arch_aux ] = false
        end,

        __tostring = function(self)
            local base = self[_key_arch_base]

            if type(base) == "string" then
                return "[Architecture " .. self[_key_arch_name] .. " : \"" .. base .. "\"]"
            elseif base then
                return "[Architecture " .. self[_key_arch_name] .. " : " .. base.Name .. "]"
            else
                return "[Architecture " .. self[_key_arch_name] .. "]"
            end
        end,

        Name = { RETRIEVE = _key_arch_name },
        Auxiliary = { OVERRIDE = _key_arch_aux, TYPE = "boolean" },

        Base = {
            get = function(self)
                return self[_key_arch_base]
            end,

            set = function(self, val, errlvl)
                if self[_key_arch_base] then
                    error("vMake error: " .. tostring(self) .. " has already defined its base.", errlvl + 1)
                end

                assertType({"string", "Architecture"}, val, "base", errlvl + 1)

                self[_key_arch_base] = val
                linkDataWithOther(self, val, errlvl + 1)
            end,
        },

        Hierarchy = function(self)
            local val = self

            local function iterator()
                local ret = val

                if val then
                    val = val.Base or nil
                end

                return ret
            end

            return iterator
        end,
    })

    function normalizeArchBase(arch, errlvl)
        if type(arch[_key_arch_base]) == "string" then
            local base = archs[arch[_key_arch_base]]

            if base then
                arch[_key_arch_base] = base
                linkDataWithOther(arch, base, errlvl + 1)
            else
                error("vMake error: " .. tostring(arch) .. " defined with unknown base \"" .. arch[_key_arch_base] .. "\".", errlvl + 1)
            end
        else
            linkDataWithOther(arch, vmake.GlobalDataContainer, errlvl + 1)
        end
    end
end

--  --  --  --  --  --
--  Project  Class  --
--  --  --  --  --  --

do
    local _key_proj_name, _key_proj_type, _key_proj_desc, _key_proj_dire = {}, {}, {}, {}
    local _key_proj_comp, _key_proj_ruls, _key_proj_ownr, _key_proj_outp = {}, {}, {}, {}
    local _key_proj_deps = {}

    vmake.CreateClass("Project", "WithData", {
        __init = function(self, name, tp)
            self[_key_proj_name] = name
            self[_key_proj_type] = tp
            self[_key_proj_desc] = false
            self[_key_proj_dire] = false
            self[_key_proj_deps] = false

            self[_key_proj_comp] = {}
            self[_key_proj_ruls] = {}
            self[_key_proj_ownr] = false
            self[_key_proj_outp] = false
        end,

        __tostring = function(self)
            if self[_key_proj_type] == "proj" then
                return "[Project " .. self[_key_proj_name] .. "]"
            elseif self[_key_proj_type] == "comp" then
                local owner = self[_key_proj_ownr]

                if owner then
                    return "[Component " .. self[_key_proj_name] .. " of " .. tostring(owner) .. "]"
                else
                    return "[Component " .. self[_key_proj_name] .. "]"
                end
            else
                error("vMake internal error: Unknown project type '" .. self[_key_proj_type] .. "'.", 2)
            end
        end,

        Name = { RETRIEVE = _key_proj_name },
        Type = { RETRIEVE = _key_proj_type },
        Description = { OVERRIDE = _key_proj_desc, TYPE = "string" },
        Owner = { RETRIEVE = _key_proj_ownr },

        Dependencies = {
            get = function(self)
                return self[_key_proj_deps]
            end,

            set = function(self, val, errlvl)
                errlvl = errlvl + 1

                if self[_key_proj_deps] then
                    error("vMake error: " .. tostring(self) .. " has already defined its dependencies.", errlvl)
                end

                local valType = assertType({"string", "List", "function"}, val, "dependencies", errlvl)

                if valType == "List" then
                    for i = #val, 1, -1 do
                        assertType("string", val[i], "dependencies list item #" .. i, errlvl)
                    end
                end

                self[_key_proj_deps] = val
            end,
        },

        ExpandDependencies = function(self, errlvl)
            if errlvl then errlvl = errlvl + 1 else errlvl = 2 end

            local val = self[_key_proj_deps]
            local valType = typeEx(val)

            if valType == "function" then
                val = withEnvironment(val, getEnvironment(self))

                local oldCodeLoc = codeLoc; codeLoc = LOC_DATA_EXP

                val = val()
                valType = assertType({"string", "List"}, val, "dependencies expansion", errlvl)

                codeLoc = oldCodeLoc
            end

            if valType == "List" then
                if val.Sealed then
                    error("vMake error: The list provided to project/component dependencies must be non-sealed.", errlvl)
                end

                local i = 1

                val = val:Select(function(dep)
                    assertType("string", dep, "dependencies list item #" .. i, errlvl + 1)

                    local item = projects[dep]

                    if not item and self[_key_proj_ownr] then
                        item = self[_key_proj_ownr][_key_proj_comp][dep]
                    end

                    if not item then
                        error("vMake error: Unknown dependency \"" .. dep .. "\" for " .. tostring(self)
                            .. "; should be a sibling component or top-level project.", errlvl + 1)
                    end

                    i = i + 1
                    return item
                end):Seal()
            elseif valType == "string" then
                local item = val
                val = projects[val]

                if not val and self[_key_proj_ownr] then
                    val = self[_key_proj_ownr][_key_proj_comp][item]
                end

                if not val then
                    error("vMake error: Unknown dependency \"" .. item .. "\" for " .. tostring(self)
                        .. "; should be a sibling component or top-level project.", errlvl)
                end

                val = (List { val }):Seal()
            elseif valType == "boolean" then
                val = vmake.Classes.List(true, {})
            else
                --  Otherwise, there is nothing to do.

                error("vMake internal error: Dependencies of " .. tostring(self) .. " appear to be of type '" .. valType .. "'.")
            end

            self[_key_proj_deps] = val
        end,

        Output = {
            get = function(self)
                return self[_key_proj_outp]
            end,

            set = function(self, val, errlvl)
                errlvl = errlvl + 1

                if self[_key_proj_outp] then
                    error("vMake error: " .. tostring(self) .. " has already defined its output.", errlvl)
                end

                local valType = assertType({"string", "Path", "List", "function"}, val, "output", errlvl)

                if valType == "List" then
                    for i = #val, 1, -1 do
                        assertType({"string", "Path"}, val[i], "output list item #" .. i, errlvl)
                    end
                end

                self[_key_proj_outp] = val
            end,
        },

        ExpandOutput = function(self, errlvl)
            if errlvl then errlvl = errlvl + 1 else errlvl = 2 end

            local val = self[_key_proj_outp]

            if not val then
                error("vMake error: " .. tostring(self) .. " does not define its output.", errlvl)
            end

            local valType = typeEx(val)

            if valType == "function" then
                val = withEnvironment(val, getEnvironment(self))

                local oldCodeLoc = codeLoc; codeLoc = LOC_DATA_EXP

                val = val()
                valType = assertType({"string", "Path", "List"}, val, "output expansion", errlvl)

                codeLoc = oldCodeLoc
            end

            if valType == "List" then
                if val.Sealed then
                    error("vMake error: The list provided to project/component output must be non-sealed.", errlvl)
                end

                for i = #val, 1, -1 do
                    local item = val[i]
                    local itemType = assertType({"string", "Path"}, item, "output expansion list item #" .. i, errlvl)

                    if itemType == "string" then
                        val[i] = vmake.Classes.Path(item, 'U')
                    end
                end

                val:Seal()
            elseif valType == "string" then
                val = vmake.Classes.List(true, { vmake.Classes.Path(val, 'U') })
            elseif valType == "Path" then
                val = vmake.Classes.List(true, { val })
            end

            self[_key_proj_outp] = val
        end,

        Directory = {
            get = function(self)
                return self[_key_proj_dire]
            end,

            set = function(self, val, errlvl)
                if self[_key_proj_dire] then
                    error("vMake error: " .. tostring(self) .. " has already defined its directory.", errlvl + 1)
                end

                local valType = assertType({"string", "Path"}, val, "directory", errlvl + 1)

                if valType == "string" then
                    val = DirPath(val)
                end

                self[_key_proj_dire] = val
            end,
        },

        AddMember = function(self, mem)
            local mt = typeEx(mem)

            if mt == "Project" then
                if mem.Type == "proj" then
                    error("vMake error: " .. tostring(self) .. " cannot contain a top-level project as a member!", 2)
                end

                if self:GetMember(mem.Name) then
                    error("vMake error: " .. mem .. " conflicts with an already-defined member.", 2)
                end

                local tab = self[_key_proj_comp]

                tab[mem.Name] = mem
                tab[#tab + 1] = mem

                setProjectOwner(mem, self, 2)
            elseif mt == "Rule" then
                if self:GetMember(mem.Name) then
                    error("vMake error: " .. mem .. " conflicts with an already-defined member.", 2)
                end

                local tab = self[_key_proj_ruls]

                tab[mem.Name] = mem
                tab[#tab + 1] = mem

                setRuleOwner(mem, self, 2)
            else
                error("vMake error: " .. tostring(self) .. " cannot contain a member of type '" .. mt .. "'.", 2)
            end
        end,

        GetMember = function(self, name)
            return self[_key_proj_comp][name] or self[_key_proj_ruls][name]
            --  Easy-peasy.
        end,
    })

    function setProjectOwner(proj, ownr, errlvl)
        if proj[_key_proj_type] == "proj" then
            error("vMake error: Top-level project cannot be a member of anything else.", errlvl + 1)
        end

        local cur = proj[_key_proj_ownr]

        if not cur then
            proj[_key_proj_ownr] = ownr
            linkDataWithOther(proj, ownr, errlvl + 1)
        else
            error("vMake error: " .. tostring(proj) .. " already belongs to " .. tostring(cur) .. "; cannot set owner again (to " .. tostring(ownr) .. ").", errlvl + 1)
        end
    end

    function getProjectRules(proj)
        return proj[_key_proj_ruls]
    end

    function getProjectComponents(proj)
        return proj[_key_proj_comp]
    end
end

--  --  --  --  --
--  Rule Class  --
--  --  --  --  --

do
    local _key_rule_name, _key_rule_desc, _key_rule_ownr, _key_rule_shrd = {}, {}, {}, {}
    local _key_rule_fltr, _key_rule_sorc, _key_rule_deps, _key_rule_acti = {}, {}, {}, {}

    vmake.CreateClass("Rule", "WithData", {
        __init = function(self, name)
            self[_key_rule_name] = name
            self[_key_rule_desc] = false
            self[_key_rule_ownr] = false
            self[_key_rule_shrd] = nil

            self[_key_rule_fltr] = false
            self[_key_rule_sorc] = false
            self[_key_rule_deps] = false
            self[_key_rule_acti] = false
        end,

        __tostring = function(self)
            local owner = self[_key_rule_ownr]

            if owner then
                return "[Rule " .. self[_key_rule_name] .. " of " .. tostring(owner) .. "]"
            else
                return "[Rule " .. self[_key_rule_name] .. "]"
            end
        end,

        Name = { RETRIEVE = _key_rule_name },
        Description = { OVERRIDE = _key_rule_desc, TYPE = "string" },
        Owner = { RETRIEVE = _key_rule_ownr },

        Action = {
            TYPE = "function",

            get = function(self, errlvl)
                return self[_key_rule_acti]
            end,

            set = function(self, val, errlvl)
                if self[_key_rule_acti] then
                    error("vMake error: " .. tostring(self) .. " has already defined its action.", errlvl)
                end

                self[_key_rule_acti] = val
            end,
        },

        Shared = {
            TYPE = "boolean",

            get = function(self, errlvl)
                return self[_key_rule_shrd]
            end,

            set = function(self, val, errlvl)
                if self[_key_rule_shrd] ~= nil then
                    error("vMake error: " .. tostring(self) .. " has already defined its 'Shared' property.", errlvl)
                end

                self[_key_rule_shrd] = val
            end,
        },

        Filter = {
            get = function(self)
                return self[_key_rule_fltr]
            end,

            set = function(self, val, errlvl)
                errlvl = errlvl + 1

                if self[_key_rule_fltr] then
                    error("vMake error: " .. tostring(self) .. " has already defined its filter.", errlvl)
                end

                local valType = assertType({"string", "Path", "List", "function"}, val, "filter", errlvl)

                if valType == "List" then
                    if val.Sealed then
                        error("vMake error: The list provided to rule filter must be non-sealed.", errlvl)
                    end

                    for i = #val, 1, -1 do
                        local item = val[i]
                        local itemType = assertType({"string", "Path"}, item, "filter list item #" .. i, errlvl)

                        if itemType == "string" then
                            val[i] = vmake.Classes.Path(item, 'U')
                        end
                    end

                    val:Seal()
                elseif valType == "string" then
                    val = vmake.Classes.Path(val, 'U')
                end

                self[_key_rule_fltr] = val
            end,
        },

        Filters = function(self, dst)
            local dstType = assertType({"string", "Path"}, dst, "destination", 2)

            if dstType == "string" then
                dst = vmake.Classes.Path(dst, 'U')
            end

            local val = self[_key_rule_fltr]

            if not self[_key_rule_fltr] then
                error("vMake error: " .. tostring(self) .. " does not define a filter.", 2)
            end
            
            local valType = typeEx(val)

            if valType == "function" then
                val = withEnvironment(val, getEnvironment(self))

                local oldCodeLoc = codeLoc; codeLoc = LOC_RULE_FLT

                val = val(dst)
                valType = typeEx(val)

                codeLoc = oldCodeLoc

                if valType == "boolean" then
                    return val
                end

                --  Not a boolean? Then it must be a Path or List, handled by the code below.
            end

            if valType == "Path" then
                return dst == val
            elseif valType == "List" then
                return val:Contains(dst)
            end

            error("vMake error: Filter of " .. tostring(self) .. " is of unknown type: " .. valType, 2)
        end,

        Source = {
            get = function(self)
                return self[_key_rule_sorc]
            end,

            set = function(self, val, errlvl)
                errlvl = errlvl + 1

                if self[_key_rule_sorc] then
                    error("vMake error: " .. tostring(self) .. " has already defined its sources.", errlvl)
                end

                assertType({"string", "Path", "List", "function"}, val, "sources", errlvl)

                self[_key_rule_sorc] = val
            end,
        },

        GetSources = function(self, dst)
            local dstType = assertType({"string", "Path"}, dst, "destination", 2)

            if dstType == "string" then
                dst = vmake.Classes.Path(dst, 'U')
            end

            if not self[_key_rule_sorc] then
                -- error("vMake error: " .. tostring(self) .. " does not define a filter.", 2)
                return false
            end
            
            local val = self[_key_rule_sorc]
            local valType = assertType({"string", "Path", "List", "function"}, val, "source expansion result", 2)

            if valType == "function" then
                val = withEnvironment(val, getEnvironment(self))

                local oldCodeLoc = codeLoc; codeLoc = LOC_RULE_SRC

                val = val(dst)

                codeLoc = oldCodeLoc

                if not val then
                    return false
                end

                valType = assertType({"string", "Path", "List"}, val, "source expansion result", 2)
            end

            if valType == "List" then
                if val.Sealed then
                    error("vMake error: The list provided to " .. tostring(self) .. " source must be non-sealed.", 2)
                end

                for i = #val, 1, -1 do
                    local item = val[i]
                    local itemType = assertType({"string", "Path"}, item, "source #" .. i, 2)

                    if itemType == "string" then
                        val[i] = vmake.Classes.Path(item, 'U')
                    end
                end

                return val:Seal()
            elseif valType == "Path" then
                return vmake.Classes.List(true, { val })
            else
                return vmake.Classes.List(true, { vmake.Classes.Path(val, 'U') })
            end

            error("vMake error: Source of " .. tostring(self) .. " is of unknown type: " .. tostring(valType), 2)
        end,
    })

    function setRuleOwner(rule, ownr, errlvl)
        local cur = rule[_key_rule_ownr]

        if not cur then
            rule[_key_rule_ownr] = ownr
            linkDataWithOther(rule, ownr, errlvl + 1)
        else
            error("vMake error: " .. tostring(rule) .. " already belongs to " .. tostring(cur) .. "; cannot set owner again (to " .. tostring(ownr) .. ").", errlvl + 1)
        end
    end
end

--  --  --  --  --  --
--   CmdOpt Class   --
--  --  --  --  --  --

do
    local _key_cmdo_name, _key_cmdo_shnm, _key_cmdo_desc, _key_cmdo_hndr = {}, {}, {}, {}
    local _key_cmdo_cnts, _key_cmdo_many, _key_cmdo_mand, _key_cmdo_type = {}, {}, {}, {}
    local _key_cmdo_disp = {}

    vmake.CreateClass("CmdOpt", "WithData", {
        __init = function(self, name)
            self[_key_cmdo_name] = name
            self[_key_cmdo_desc] = false
            self[_key_cmdo_hndr] = false
            self[_key_cmdo_shnm] = false
            self[_key_cmdo_cnts] = 0
            self[_key_cmdo_type] = false
            self[_key_cmdo_disp] = false
        end,

        __tostring = function(self)
            local shortname = self[_key_cmdo_shnm]

            if shortname then
                return "[CmdOpt " .. self[_key_cmdo_name] .. " | " .. shortname .. "]"
            else
                return "[CmdOpt " .. self[_key_cmdo_name] .. "]"
            end
        end,

        Name        = { RETRIEVE = _key_cmdo_name },
        Description = { OVERRIDE = _key_cmdo_desc, TYPE = "string"  },
        Count       = { RETRIEVE = _key_cmdo_cnts },

        Many        = { OVERRIDE = _key_cmdo_many, TYPE = "boolean" },
        Mandatory   = { OVERRIDE = _key_cmdo_mand, TYPE = "boolean" },

        Type = {
            TYPE = "string",

            get = function(self, errlvl)
                return self[_key_cmdo_type]
            end,

            set = function(self, val, errlvl)
                if self[_key_cmdo_type] then
                    error("vMake error: " .. tostring(self) .. " has already defined its type.", errlvl)
                end

                self[_key_cmdo_type] = val
            end,
        },

        Handler = {
            TYPE = "function",

            get = function(self, errlvl)
                return self[_key_cmdo_hndr]
            end,

            set = function(self, val, errlvl)
                if self[_key_cmdo_hndr] then
                    error("vMake error: " .. tostring(self) .. " has already defined its handler.", errlvl)
                end

                self[_key_cmdo_hndr] = val
            end,
        },

        ExecuteHandler = function(self, val)
            local han = self[_key_cmdo_hndr]

            if not han then
                error("vMake error: " .. tostring(self) .. " does not define a handler.", 2)
            end

            han = withEnvironment(han, getEnvironment(self))

            local oldCodeLoc = codeLoc; codeLoc = LOC_CMDO_HAN
            
            local res = han(val)

            codeLoc = oldCodeLoc
        end,

        ShortName = {
            TYPE = "string",

            get = function(self, errlvl)
                return self[_key_cmdo_shnm]
            end,

            set = function(self, val, errlvl)
                if self[_key_cmdo_shnm] then
                    error("vMake error: " .. tostring(self) .. " has already defined its short name.", errlvl)
                end

                if #val ~= 1 then
                    error("vMake error: Command-line option short name must be exactly one character long.", errlvl)
                end

                if val:find("%A") then
                    error("vMake error: Command-line option short name must be a letter (lowercase or uppercase).", errlvl)
                end

                if cmdlopts[val] then
                    error("vMake error: Cannot assign short name to "
                        .. tostring(self)
                        .. " because it is already assigned to "
                        .. tostring(cmdlopts[val]) .. ".", errlvl)
                end

                self[_key_cmdo_shnm] = val
                cmdlopts[val] = self
            end,
        },

        Display = {
            TYPE = "string",

            get = function(self, errlvl)
                return self[_key_cmdo_disp]
            end,

            set = function(self, val, errlvl)
                if self[_key_cmdo_disp] then
                    error("vMake error: " .. tostring(self) .. " has already defined its display value.", errlvl)
                end

                if #val < 1 then
                    error("vMake error: Command-line option display value must be non-empty.", errlvl)
                end

                self[_key_cmdo_disp] = val
            end,
        },
    })

    function incrementCmdoCount(cmdo)
        cmdo[_key_cmdo_cnts] = cmdo[_key_cmdo_cnts] + 1
    end
end

--  --  --  --  --  --  --
--   WorkEntity Class   --
--  --  --  --  --  --  --

do
    local _key_wken_prqs, _key_wken_done, _key_wken_outd, _key_wken_levl = {}, {}, {}, {}

    vmake.CreateClass("WorkEntity", nil, {
        __init = function(self)
            self[_key_wken_prqs] = vmake.Classes.List()
            self[_key_wken_done] = false
            self[_key_wken_outd] = false
            self[_key_wken_levl] = -1
        end,

        Prerequisites = { RETRIEVE = _key_wken_prqs },
        Done          = { RETRIEVE = _key_wken_done },
        Outdated      = { RETRIEVE = _key_wken_outd },
        Level         = { RETRIEVE = _key_wken_levl },

        Seal = function(self)
            self[_key_wken_prqs]:Seal(true)
        end,
    })

    function setWorkEntityDone(wken)
        wken[_key_wken_done] = true
    end

    function setWorkEntityOutdated(wken, val)
        wken[_key_wken_outd] = val
    end

    function setWorkEntityLevel(wken, levl)
        wken[_key_wken_levl] = levl
    end
end

--  --  --  --  --  --
--  WorkItem Class  --
--  --  --  --  --  --

do
    local _key_wkit_path, _key_wkit_rule, _key_wkit_srcs = {}, {}, {}

    vmake.CreateClass("WorkItem", "WorkEntity", {
        __init = function(self, path, rule)
            self[_key_wkit_path] = path
            self[_key_wkit_rule] = rule
            self[_key_wkit_srcs] = false
        end,

        __tostring = function(self)
            return "[Work Item for " .. tostring(self[_key_wkit_path]) .. " | " .. tostring(self[_key_wkit_rule]) .. "]"
        end,

        Path          = { RETRIEVE = _key_wkit_path },
        Rule          = { RETRIEVE = _key_wkit_rule },
        Sources       = { RETRIEVE = _key_wkit_srcs },
    })

    function setWorkItemSource(wkit, srcs)
        wkit[_key_wkit_srcs] = srcs
    end
end

--  --  --  --  --  --
--  WorkLoad Class  --
--  --  --  --  --  --

do
    local _key_wkld_itms, _key_wkld_comp = {}, {}

    vmake.CreateClass("WorkLoad", "WorkEntity", {
        __init = function(self, comp)
            self[_key_wkld_itms] = vmake.Classes.List()
            self[_key_wkld_comp] = comp
        end,

        __tostring = function(self)
            return "[Work Load for " .. tostring(self[_key_wkld_comp]) .. " | " .. #self[_key_wkld_itms] .. " items]"
        end,

        Items         = { RETRIEVE = _key_wkld_itms },
        Component     = { RETRIEVE = _key_wkld_comp },

        Seal = function(self)
            self[_key_wkld_itms]:Seal(true)
            self[_key_wkld_prqs]:Seal(true)
        end,
    })
end

--  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --
--  Filesystem Library
--  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --

fs = {}
baseEnvironment.fs = fs

if lfs then
    local modeMap = setmetatable({
        file = 'f',
        directory = 'd',
    }, {
        __index = function(self, key)
            rawset(self, key, 'U')

            return 'U'
        end,
    })

    function fs.ListDir(dir, rec)
        local dirType = assertType({"string", "Path"}, dir, "directory", 2)

        assertType({"nil", "number"}, rec, "recursivity", 2)

        if codeLoc == LOC_RULE_ACT then
            error("vMake error: Directories cannot be listed in rule actions.")
        end

        if dirType == "Path" then
            if dir.IsFile then
                error("vMake error: The given Path must not point to a known file: " .. tostring(dir), 2)
            end

            dir = tostring(dir)
        end
        
        if rec and (rec < 0 or rec % 1 ~= 0) then
            error("vMake error: Recursivity must be a non-negative integer, or nil, not " .. tostring(rec) .. ".", 2)
        end

        local out = vmake.Classes.List()
        local skippedSelf = false

        local function recurseDirectory(dir, order)
            order = order + 1
            dir = dir .. "/"    --  kek

            for path in lfs.dir(dir) do
                if path ~= "." and path ~= ".." then
                    local fPath = dir .. path
                    local attr = lfs.attributes(fPath)

                    out:Append(vmake.Classes.Path(fPath, modeMap[attr.mode], attr.modification))

                    if (not rec or order <= rec) and attr.mode == "directory" then
                        recurseDirectory(fPath, order)
                    end
                end
            end
        end

        local okay, err = pcall(recurseDirectory, dir, 1)

        if not okay then
            if err:sub(1, 12) == "cannot open " then
                error("vMake error: Directory \"" .. dir .. "\" does not exist.", 2)
            else
                error("vMake internal error: " .. err, 2)
            end
        end

        return out
    end

    function fs.GetInfo(pth)
        local pthType = assertType({"string", "Path"}, pth, "path", 2)

        if codeLoc == LOC_RULE_ACT then
            error("vMake error: File/directory info cannot be retrieved in rule actions.")
        end

        if pthType == "Path" then
            pth = tostring(pth)
        end

        local attr, err = lfs.attributes(pth)

        if not attr then
            if err:sub(1, 37) == "cannot obtain information from file `" then
                return nil, nil
            else
                error("vMake internal error: " .. err, 2)
            end
        end

        return modeMap[attr.mode], attr.modification
    end

    function fs.MkDir(dir, prog)
        local dirType = assertType({"string", "Path"}, dir, "directory", 2)
        assertType({"nil", "boolean"}, prog, "progressive", 2)

        if codeLoc ~= 0 and codeLoc ~= LOC_RULE_ACT and codeLoc ~= LOC_CMDO_HAN then
            error("vMake error: Directories can only be created from rule actions or command-line option handlers.")
        end

        if codeLoc ~= 0 and vmake.Capturing then
            if prog ~= false then
                return sh.silent("mkdir", "-p", dir)
            else
                return sh.silent("mkdir", dir)
            end
        end

        if dirType == "Path" and dir.Exists then
            return false
        end

        local function innerMkDir(dir)
            local okay, err = lfs.mkdir(dir)

            if not okay then
                if err == "File exists" then
                    return false
                else
                    error("vMake error: Could not create directory: " .. err, 3)
                end
            end

            return true
        end

        if prog ~= false then
            if dirType == "string" then
                dir = Path(dir)
            end

            local last

            for part in dir:Progress() do
                last = innerMkDir(part)
            end

            return last
        else
            if dirType == "Path" then
                dir = tostring(dir)
            end

            return innerMkDir(dir)
        end
    end
else
    --  Kudos to mijyuoon for helping out with this. :>

    function fs.ListDir(dir, rec)
        local dirType = assertType({"string", "Path"}, dir, "directory", 2)

        assertType({"nil", "number"}, rec, "recursivity", 2)

        if codeLoc == LOC_RULE_ACT then
            error("vMake error: Directories cannot be listed in rule actions.")
        end

        if dirType == "string" then
            dir = escapeForShell(dir)
        else
            if dir.IsFile then
                error("vMake error: The given Path must not point to a known file: " .. tostring(dir), 2)
            end

            dir = escapeForShell(tostring(dir))
        end

        local cmd = "find " .. dir

        if rec then
            if rec < 0 or rec % 1 ~= 0 then
                error("vMake error: Recursivity must be a non-negative integer, or nil, not " .. tostring(rec) .. ".", 2)
            end

            cmd = cmd .. " -maxdepth " .. tostring(rec)
        end

        cmd = cmd .. ' -printf "%y %T@ %p\\n"'

        local output = vmake.Classes.List()
        local skippedSelf = false

        local fp = io.popen(cmd)

        for line in fp:lines() do
            if skippedSelf then
                local fType, fMtime, fPath = line:match("(.) ([^%s]+) (.*)")

                output:Append(vmake.Classes.Path(fPath, fType, tonumber(fMtime)))
            else
                skippedSelf = true
            end
        end

        local a, b, c = fp:close()

        if c == 1 then
            error("vMake error: Directory \"" .. dir .. "\" does not exist.", 2)
        end

        return output
    end

    function fs.GetInfo(pth)
        local pthType = assertType({"string", "Path"}, pth, "path", 2)

        if codeLoc ~= 0 and codeLoc == LOC_RULE_ACT then
            error("vMake error: File/directory info cannot be retrieved in rule actions.")
        end

        if pthType == "string" then
            pth = escapeForShell(pth)
        else
            pth = escapeForShell(tostring(pth))
        end

        local cmd = "find " .. pth  .. ' -maxdepth 0 -printf "%y\\n%T@" 2>&1'

        local output = {}

        local fp = io.popen(cmd)

        for line in fp:lines() do
            output[#output + 1] = line
        end

        local a, b, c = fp:close()

        if c == 1 then
            return nil, nil
        end

        return output[1], tonumber(output[2])
    end

    function fs.MkDir(dir, prog)
        local dirType = assertType({"string", "Path"}, dir, "directory", 2)
        assertType({"nil", "boolean"}, prog, "progressive", 2)

        if codeLoc ~= 0 and codeLoc ~= LOC_RULE_ACT and codeLoc ~= LOC_CMDO_HAN then
            error("vMake error: Directories can only be created from rule actions or command-line option handlers.")
        end

        if dirType == "Path" and dir.Exists then
            return false
        end

        if prog ~= false then
            return sh.silent("mkdir", "-p", dir)
        else
            return sh.silent("mkdir", dir)
        end
    end
end

function fs.Copy(dst, src, ovr, bufSize)
    local dstType = assertType({"string", "Path"}, dst, "destination", 2)
    local srcType = assertType({"string", "Path"}, src, "source", 2)
    assertType({"nil", "boolean"}, bufSize, "override", 2)
    assertType({"nil", "number"}, bufSize, "buffer size", 2)

    if dstType == "Path" then
        if dst.IsDirectory then
            error("vMake error: The given copy destination Path must not point to a known directory: " .. tostring(dst), 2)
        end

        dst = tostring(dst)
    end

    if srcType == "Path" then
        if src.IsDirectory then
            error("vMake error: The given copy source Path must not point to a known directory: " .. tostring(src), 2)
        end

        src = tostring(src)
    end

    if not bufSize then
        bufSize = 65536
    elseif bufSize < 1 or bufSize % 1 ~= 0 then
        error("vMake error: Copy buffer size must be a positive integer.", 2)
    end

    if codeLoc ~= 0 and codeLoc ~= LOC_RULE_ACT and codeLoc ~= LOC_CMDO_HAN then
        error("vMake error: Files can only be copied from rule actions or command-line option handlers.")
    end

    if codeLoc ~= 0 and vmake.Capturing then
        if ovr then
            return sh.silent("cp", "-f", src, dst)
        else
            return sh.silent("cp", src, dst)
        end
    end

    if not ovr then
        --  When not overriding, the destination ought to not exist.

        local fOutO, errOutO = io.open(dst, "r")

        if fOutO then
            fOutO:close()

            return false
        end
    end

    local fIn, errIn = io.open(src, "r")

    if not fIn then
        error("vMake error: Unable to open file \"" .. src .. "\" as source for copying: " .. errIn, 2)
    end

    local fOut, errOut = io.open(dst, "w+")

    if not fOut then
        error("vMake error: Unable to open file \"" .. dst .. "\" as destination for copying: " .. errOut, 2)
    end

    while true do
        local block = fIn:read(bufSize)

        if not block then
            break
        end

        fOut:write(block)
    end

    fOut:close()
    fIn:close()
end

--  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --
--  Shell Library
--  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --

local _key_shll_slnt, _key_shll_tolr = {}, {}

local shellmeta = {
    __metatable = "Still no."
}

local function shell_string(cmd, ...)
    local cmdType = assertType({"string", "Path"}, cmd, "command", 2)

    if cmdType == "Path" then
        cmd = tostring(cmd)
    end

    local nextIsRaw = false
    local function appendArg(arg, tab, errlvl)
        errlvl = errlvl + 1

        if arg == nil then
            error("vMake error: Shell command argument cannot be nil.", errlvl)
        end

        local argType = typeEx(arg)

        if nextIsRaw then
            assertTypeEx("string", argType, arg, "command argument", errlvl + 1)

            tab[#tab + 1] = arg

            nextIsRaw = false
        elseif argType == "List" then
            arg:ForEach(function(item) appendArg(item, tab, errlvl) end)
        elseif arg == SH_AND then
            tab[#tab + 1] = "&&"
        elseif arg == SH_SEP then
            tab[#tab + 1] = ";"
        elseif arg == SH_RAW then
            nextIsRaw = true
        else
            tab[#tab + 1] = escapeForShell(tostring(arg))
        end
    end

    local args, tab = {...}, {cmd}

    for i = 1, #args do
        appendArg(args[i], tab, 2)
    end

    return table.concat(tab, " ")
end

function shellmeta.__call(self, cmd, ...)
    if codeLoc ~= 0 and codeLoc ~= LOC_RULE_ACT and codeLoc ~= LOC_CMDO_HAN then
        error("vMake error: Shell commands can only be executed from rule actions and command-line option handlers.")
    end

    cmd = shell_string(cmd, ...)

    local printCmd = vmake.Verbose or not (self[_key_shll_slnt] or vmake.Silent)

    if codeLoc == LOC_RULE_ACT and vmake.Capturing then
        local lastLog = vmake.CommandLog:Last()

        if lastLog and lastLog.WorkItem == curWorkItem then
            lastLog.Commands:Append({
                Command = cmd,
                Tolerant = self[_key_shll_tolr],
                Print = printCmd,
            })
        else
            vmake.CommandLog:Append({
                WorkItem = curWorkItem,
                Commands = List {
                    {
                        Command = cmd,
                        Tolerant = self[_key_shll_tolr],
                        Print = printCmd,
                    }
                },
            })
        end

        --  If the last logged command belongs to the same work item, simply
        --  append another command to it.

        return "UNKNOWN"
    else
        if printCmd then
            print(cmd)
        end

        local okay, exitReason, code = os.execute(cmd)

        if not okay and not self[_key_shll_tolr] then
            error("vMake failed to execute shell command"
                .. (printCmd and "; " or (":\n" .. cmd .. "\n"))
                .. "exit reason: " .. tostring(exitReason) .. "; status code: " .. tostring(code), 2)
        end

        return okay or false
    end
end

function shellmeta.__index(self, key)
    if key == "silent" then
        return setmetatable({
            [_key_shll_slnt] = true,
            [_key_shll_tolr] = self[_key_shll_tolr]
        }, shellmeta)
    elseif key == "tolerant" then
        return setmetatable({
            [_key_shll_slnt] = self[_key_shll_slnt],
            [_key_shll_tolr] = true
        }, shellmeta)
    elseif key == "string" then
        return shell_string
    else
        return rawget(self, key)
    end
end

sh = setmetatable({ [_key_shll_slnt] = false, [_key_shll_tolr] = false }, shellmeta)
baseEnvironment.sh = sh

--  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --
--  Environments
--  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --

do
    local envs = {}

    function getEnvironment(obj)
        if envs[obj] then
            return envs[obj]
        end

        local envind, envmtt = {}, {
            __metatable = "How about no?",

            __newindex = function(self, key, val)
                error("vMake error: Local environment table cannot be altered directly.")
            end,
        }

        local objType = typeEx(obj)

        --  Step 1, merge data into local environment if the environment's object
        --  is data, and also reference it indiscriminately.

        if objType == "Data" then
            obj = obj.Owner
            objType = typeEx(obj)
        end

        if type(obj) == "table" then
            envind.data = obj.Data
        end

        --  Step 2, add rule if this is one.

        if objType == "Rule" then
            envind.rule = obj

            obj = obj.Owner
            objType = typeEx(obj)

            if not envind.data then envind.data = obj.Data end
            --  Set data once again if not present yet.
        end

        --  Step 3, add bottom-level component and top-level project if any.
        --  Otherwise, add current architecture or configuration.

        if objType == "Project" then
            envind.comp = obj
            --  A top-level project is also a valid component.

            while obj.Type ~= "proj" do
                obj = obj.Owner
                objType = typeEx(obj)

                if not envind.data then envind.data = obj.Data end
                --  Set data once again if not present yet.
            end

            envind.proj = obj
            --  `obj` is now guaranteed to be a top-level project.
        elseif objType == "Architecture" then
            envind.arch = obj
        elseif objType == "Configuration" then
            envind.conf = obj
        elseif objType == "CmdOpt" then
            envind.opt = obj
        elseif objType ~= "WithData" then
            error("vMake internal error: Uknown object type '" .. objType .. "' (" .. tostring(obj) .. ") for environment creation.")
        end

        local data = envind.data

        function envmtt.__index(self, key)
            assertType({"string", "number"}, key, "local environment key", 2)

            local res = envind[key]

            if res == nil then
                res = baseEnvironment[key]
            else
                return res
            end

            if res == nil then
                res = data:TryGet(key, 2)
            end

            return res
        end

        local res = setmetatable({}, envmtt)

        envs[obj] = res
        return res
    end
end

--  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --
--  Main Tasks
--  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --

function vmake.ValidateAndDefault()
    --  Step 1, validate projects.

    for i = #projects, 1, -1 do
        local val = projects[i]

        assert(not val.Owner, "vMake error: " .. tostring(val) .. " must not be a member of anything; it is owned by " .. tostring(val.Owner) .. ".")
        assert(val.Output, "vMake error: " .. tostring(val) .. " does not define any output.")

        if val.Directory then
            assert(fs.GetInfo(val.Directory), "vMake error: " .. tostring(val) .. " is defined with a non-existing directory.")
        else
            val.Directory = DirPath "."
        end

        if vmake.GlobalDataContainer then
            linkDataWithOther(val, vmake.GlobalDataContainer, 2)
        end
    end

    --  Step 2, validate components.

    for i = #comps, 1, -1 do
        local val = comps[i]

        assert(val.Owner, "vMake error: " .. tostring(val) .. " is not a member of anything.")
        assert(val.Output, "vMake error: " .. tostring(val) .. " does not define any output.")

        if val.Directory then
            assert(fs.GetInfo(val.Directory), "vMake error: " .. tostring(val) .. " is defined with a non-existing directory.")
        else
            val.Directory = DirPath "."
        end
    end

    --  Step 3, validate rules.

    for i = #rules, 1, -1 do
        local val = rules[i]

        assert(val.Owner, "vMake error: " .. tostring(val) .. " is not a member of anything.")
        assert(val.Filter, "vMake error: " .. tostring(val) .. " does not define a filter.")
        assert(val.Action, "vMake error: " .. tostring(val) .. " does not define an action.")
    end

    --  Step 4, validate archs and configs.

    if #archs == 0 then
        Architecture "default-arch"
    end

    for i = #archs, 1, -1 do
        local val = archs[i]

        normalizeArchBase(val, 2)
    end

    if #configs == 0 then
        Configuration "default-conf"
    end

    for i = #configs, 1, -1 do
        local val = configs[i]

        normalizeConfigBase(val, 2)
    end

    --  Step 5, command-line options.

    for i = 1, #cmdlopts do
        local val = cmdlopts[i]

        if vmake.GlobalDataContainer then
            linkDataWithOther(val, vmake.GlobalDataContainer, 2)
        end
    end

    --  Step 6, check defaults.

    if not defaultProj then
        if #projects > 1 then
            error("vMake error: No default project specified when there is more than one project defined.")
        end

        defaultProj = projects[1]
    end

    if not defaultArch then
        if #archs > 1 then
            error("vMake error: No default architecture specified when there is more than one architecture defined.")
        end

        defaultArch = archs[1]
    end

    assert(not defaultArch.Auxiliary, "vMake error: Default architecture is auxiliary.")

    if not defaultConf then
        if #configs > 1 then
            error("vMake error: No default configuration specified when there is more than one configuration defined.")
        end

        defaultConf = configs[1]
    end

    assert(not defaultConf.Auxiliary, "vMake error: Default configuration is auxiliary.")

    if not outDir then
        if #archs > 1 or #configs > 1 then
            OutputDirectory(function()
                return "./.vmake/" .. (selArch.Name .. "." .. selConf.Name)
            end)
        else
            OutputDirectory "./.vmake"
        end
    end
end

function vmake.CheckArguments()
    if not arg then return end

    local i, n, acceptOptions = 1, #arg, true
    local selProj, selArch, selConf

    while i <= n do
        local cur, usedNextArg = arg[i], false

        if cur == "--" then
            acceptOptions = false
        elseif #cur > 0 then
            local handled = false

            local function doOption(long, optName, val)
                local opt = cmdlopts[optName]

                if not opt then
                    error("vMake error: Unknown command-line option \"" .. optName .. "\".")
                end

                incrementCmdoCount(opt)

                if not opt.Many and opt.Count > 1 then
                    error("vMake error: Multiple instances of command-line option \"" .. optName .. "\" found.")
                end

                local optType = opt.Type

                if optType then
                    if not val then
                        val = arg[i + 1]

                        if not val then
                            error("vMake error: Command-line option \"" .. optName .. "\" lacks a value.")
                        end

                        usedNextArg = true
                    end

                    if optType == "boolean" then
                        local bVal = toboolean(val)

                        if bVal ~= nil then
                            val = bVal
                        else
                            error("vMake error: Command-line argument value \""
                                .. val
                                .. "\" does not represent a valid boolean value, as required by option \""
                                .. optName .. "\".")
                        end
                    elseif optType == "number" then
                        local nVal = tonumber(val)

                        if nVal then
                            val = nVal
                        else
                            error("vMake error: Command-line argument value \""
                                .. val
                                .. "\" does not represent a valid number, as required by option \""
                                .. optName .. "\".")
                        end
                    elseif optType == "integer" then
                        local nVal = tonumber(val)

                        if nVal and nVal % 1 == 0 then
                            val = nVal
                        else
                            error("vMake error: Command-line argument value \""
                                .. val
                                .. "\" does not represent a valid integer, as required by option \""
                                .. optName .. "\".")
                        end
                    end
                end

                opt:ExecuteHandler(val)

                handled = true
            end

            if acceptOptions then
                if cur:sub(1, 2) == "--" then
                    --  So this is a long option name.

                    local eqPos = cur:find('=', 3, true)

                    local optName = eqPos and cur:sub(3, eqPos - 1) or cur:sub(3)

                    if #optName < 2 then
                        error("vMake error: Command-line argument #" .. i .. " contains a long option name, but it is too short; should be at least two characters long.")
                    end

                    doOption(true,
                        optName,
                        eqPos and cur:sub(eqPos + 1) or nil)
                elseif cur:sub(1, 1) == '-' then
                    --  So, short option name.

                    for j = 2, #cur do
                        doOption(false, cur:sub(j, j), nil)
                    end
                end
            end

            if not handled then
                --  So, this ought to be a project, architecture and configuration
                --  specification.

                local proj, arch, conf = projects[cur], archs[cur], configs[cur]

                if proj then
                    if selProj then
                        error("vMake error: Default project is already chosen to be " .. tostring(selProj) .. "; cannot set it to " .. tostring(proj) .. ".")
                    end

                    selProj = proj
                elseif arch then
                    if selArch then
                        error("vMake error: Default architecture is already chosen to be " .. tostring(selArch) .. "; cannot set it to " .. tostring(arch) .. ".")
                    end

                    selArch = arch
                    
                    assert(not arch.Auxiliary, "vMake error: Selected architecture is auxiliary.")
                elseif conf then
                    if selConf then
                        error("vMake error: Default configuration is already chosen to be " .. tostring(selConf) .. "; cannot set it to " .. tostring(conf) .. ".")
                    end

                    selConf = conf
                    
                    assert(not conf.Auxiliary, "vMake error: Selected configuration is auxiliary.")
                else
                    error("vMake error: There is no project, architecture or configuration named \"" .. cur .. "\".")
                end
            end
        end

        i = i + (usedNextArg and 2 or 1)
    end

    if selProj then defaultProj = selProj end
    if selArch then defaultArch = selArch end
    if selConf then defaultConf = selConf end

    baseEnvironment.selArch, baseEnvironment.selConf, baseEnvironment.selProj = defaultArch, defaultConf, defaultProj
    --  Done.
end

function vmake.ExpandProperties()
    --  Step 1, the output directory.

    if type(outDir) == "function" then
        local fnc = outDir
        outDir = nil

        fnc = withEnvironment(fnc, getEnvironment(vmake.GlobalDataContainer))

        local oldCodeLoc = codeLoc; codeLoc = LOC_DATA_EXP

        OutputDirectory(fnc())

        codeLoc = oldCodeLoc
    end

    baseEnvironment.outDir = outDir

    --  Step 2, projects.

    for i = #projects, 1, -1 do
        local val = projects[i]

        val:ExpandOutput(3)
        val:ExpandDependencies(3)
    end

    --  Step 3, components.

    for i = #comps, 1, -1 do
        local val = comps[i]

        val:ExpandOutput(3)
        val:ExpandDependencies(3)
    end

    --  Step 4, misc.

    vmake.JobsDir = outDir + ".jobs"
end

function vmake.ConstructWorkGraph()
    local constructFromProject, constructForFile

    constructForFile = function(proj, path, assoc, stack, errlvl, goingUp, depAssoc, isSource)
        errlvl = errlvl + 1

        local sPath = tostring(path)

        if not goingUp then
            --  If going up, this check was already performed once. No need to
            --  repeat.

            for i = #stack, 1, -1 do
                if stack[i] == sPath then
                    --  Recursive dependencies are not okay. </3

                    error("vMake error: Detected circular dependency for "
                        .. sPath .. " of " .. tostring(proj) .. "."
                        , errlvl)
                end
            end
        end

        if assoc[sPath] then
            --  This is a directed graph, not a tree, so multiplicates are okay. <3

            -- print("MULTIPLICATE", path)

            return assoc[sPath][1], assoc[sPath][2], assoc[sPath][3]
        end

        -- print("GOD HELP WITH", path, "FOR", proj)

        if not goingUp then
            --  When going up, the path is already on the stack, and won't change
            --  with further recursive calls. Thus, re-adding it is redundant.

            stack[#stack + 1] = sPath
        end

        --  So, first thing to do here is to find a matching rule.
        --  First, this project's rules are checked.
        --  No more than one rule must match the output file.

        local ruls, matches, item, refs, found = getProjectRules(proj), {}, false, {}, false

        for i = #ruls, 1, -1 do
            if (not goingUp or ruls[i].Shared) and ruls[i]:Filters(path) then
                --  If the search is going up, only shared rules are considered.

                matches[#matches + 1] = ruls[i]

                --  No stopping, because multiplicates must be immediately found.
            end
        end

        if #matches == 1 then
            --  Okay, cool.

            item = vmake.Classes.WorkItem(path, matches[1])

            -- print("ITEM", item, "1 MATCH")

            assoc[sPath] = {item, refs, true}
            found = true
        elseif #matches == 0 then
            --  No matches... Scheiße. This means the rule can either be defined
            --  in a parent project and must be shared, or this path must be in
            --  the output of an immediate child component.

            local comps, firstFind = getProjectComponents(proj), false

            -- print("LOOKING DOWN AT", #comps, "COMPONENTS OF", proj)

            for i = 1, #comps do
                local comp = comps[i]
                local thisIsIt = comp.Output:Contains(path)

                if thisIsIt then
                    if found then
                        error("vMake error: Path \"" .. sPath
                            .. "\" found in at least two immediate child components of "
                            .. tostring(proj) .. ":\n\t"
                            .. tostring(firstFind) .. "\n\t"
                            .. tostring(comp), errlvl)
                    end

                    if not depAssoc[comp] then
                        depAssoc[comp] = true
                        refs = { comp }

                        --  No item association is done here.
                    end

                    firstFind = comp
                    found = true

                    --  Do not quit iterating; duplicates must be found!
                end
            end

            if not found then
                --  Either this is going up or it simply wasn't found in the
                --  output of an immediate child component.

                local ownr = proj.Owner

                if not ownr then
                    if not isSource then
                        error("vMake error: Unable to find rule for path \"" .. sPath
                            .. "\" of " .. tostring(proj) .. ".", errlvl)
                    end
                else
                    -- print("LOOKING UP AT", ownr)

                    item, refs, found = constructForFile(ownr, path, assoc, stack, errlvl, true, depAssoc, isSource)
                    --  Look up.
                end
            end
        else
            for i = 1, #matches do matches[i] = tostring(matches[i]) end

            error("vMake error: Path \"" .. sPath .. "\" matches more than one target:\n\t"
                .. table.concat(matches, "\n\t"), errlvl)
        end

        if item then
            local srcs, outdated = item.Rule:GetSources(path), false

            if srcs then
                -- print("SOURCES\n", table.concat(getListContainer(srcs:Select(function(src)
                --     return typeEx(src) .. " \"" .. tostring(src) .. "\""
                -- end)), "\n\t"), "\n\tOF", item)

                setWorkItemSource(item, srcs)

                srcs:ForEach(function(src)
                    -- print("SRC", src, "OF", item)

                    assurePathInfo(src)

                    local subItem, subRefs, subFound = constructForFile(proj, src, assoc, stack, errlvl + 2, false, depAssoc, true)

                    if subItem then
                        item.Prerequisites:Append(subItem)
                    end

                    if subRefs then
                        -- if refs then
                        --     for i = #subRefs, 1, -1 do
                        --         refs[#refs + 1] = subRefs[i]
                        --     end
                        -- else
                        --     refs = subRefs
                        -- end

                        for i = #subRefs, 1, -1 do
                            item.Prerequisites:Append(constructFromProject(subRefs[i], assoc, stack, errlvl + 2))
                        end
                    end

                    if (src.ModificationTime
                        and path.ModificationTime
                        and src.ModificationTime <= path.ModificationTime)
                        or (src.IsDirectory and src.Exists) then
                        --  Source NOT modified after the destination? Cool!
                        --  Source is an existing directory? Also cool!

                        -- MSG("Preq ", src, " of ", item, " is NOT outdated.")

                        return
                    end

                    outdated = true
                    --  Otherwise, this is definitely an outdated item.

                    -- MSG("Preq ", src, " of ", item, " is outdated!")

                    if not subFound then
                        --  Nothing? Means this file ought to already exist.

                        -- print("AIN'T FOUND NUTHIN FOR", src, "OF", item)

                        if not src.ModificationTime then
                            error("vMake error: Unable to find rule for dependency \"" .. tostring(src)
                                .. "\" of " .. tostring(item) .. "; stack:\n\t"
                                .. table.concat(getListContainer(vmake.Classes.List(false, stack):Select(function(elem)
                                    return tostring(elem)
                                end)), "\n\t"), errlvl + 2)
                        end
                    end
                end)
            else
                --  This item has no sources, therefore it is considered outdated
                --  if it doesn't exist.

                outdated = not path.Exists
            end

            setWorkEntityOutdated(item, outdated)

            -- if outdated then
            --     MSG(item, " is outdated.")
            -- else
            --     MSG(item, " is up-to-date.")
            -- end
        end

        if not goingUp then
            --  It wasn't added. Thus, it is not removed.

            stack[#stack] = nil
        end

        -- print("GOD HELPED FIND", item, refs[1], refs[2], "FOR", path)

        return item, refs, found
    end

    constructFromProject = function(proj, assoc, stack, errlvl)
        errlvl = errlvl + 1

        for i = #stack, 1, -1 do
            if stack[i] == proj then
                --  Recursive dependencies are not okay. </3

                error("vMake error: Detected circular dependency for " .. tostring(proj) .. "; stack:\n\t"
                    .. table.concat(getListContainer(vmake.Classes.List(false, stack):Select(function(sorc)
                        return tostring(sorc)
                    end)), "\n\t"), errlvl)
            end
        end

        if assoc[proj] then
            --  Multiplicates are okay. <3

            return assoc[proj]
        end

        stack[#stack + 1] = proj
        -- print("STACK PUSH", #stack, proj)

        local load = vmake.Classes.WorkLoad(proj)
        assoc[proj] = load
        --  Associate early.

        local deps, outp, depAssoc = proj.Dependencies:Copy(), proj.Output, {}
        --  An associative array is used to make sure each component is added as
        --  a prerequisite only once.

        -- print("COMP DEPS", proj, deps:Print())
        -- print("COMP OUTP", outp:Print())

        if not outp then
            error("vMake internal error: Somehow " .. tostring(proj) .. " has nil output.", errlvl)
        end

        outp:ForEach(function(path)
            assurePathInfo(path)

            local item, iRefs = constructForFile(proj, path, assoc, {}, errlvl + 2, false, depAssoc, false)

            if item then
                load.Items:Append(item)
            end

            if iRefs and #iRefs > 0 then
                deps:AppendMany(iRefs)
            end
        end)

        local uniquer = {}

        load.Prerequisites:AppendMany(deps:Where(function(dep)
            local val = uniquer[dep]
            uniquer[dep] = true
            return not val
        end):Select(function(dep)
            -- print("DEPENDENCY", dep, "OF", proj)

            return constructFromProject(dep, assoc, stack, errlvl + 2)
        end))

        -- print("STACK POP", #stack, stack[#stack], proj)
        stack[#stack] = nil
        return load
    end

    local assoc, stack = {}, {}

    return constructFromProject(defaultProj, assoc, stack, 2)
end

function vmake.ChartWorkGraph()
    if vmake.WorkGraph.Done then
        return
    end

    local function chartEntity(ent, done, min)
        if done[ent] then
            return done[ent]
        end

        local newMin = min

        local function checkLevel(subEnt, max)
            if subEnt.Done then
                return max
            end

            local preqLvl = chartEntity(subEnt, done, newMin)

            if not max then
                return preqLvl
            elseif preqLvl > max then
                return preqLvl
            else
                return max
            end
        end

        local scratch, max = ent.Prerequisites:ForEach(checkLevel)

        if typeEx(ent) == "WorkLoad" then
            if max then
                --  If there are any prerequisites to this workload, all its
                --  items will have a higher level than the preqs.

                newMin = max + 1
            end

            local scratch, max2 = ent.Items:ForEach(checkLevel)

            if not max or (max2 and max2 > max) then
                max = max2
            end
        end

        if max then
            if typeEx(ent) == "WorkLoad" then
                done[ent] = max
            else
                done[ent] = max + 1
            end
        else
            done[ent] = min
        end

        setWorkEntityLevel(ent, done[ent])

        return done[ent]
    end

    local done = {}

    vmake.MaxLevel = chartEntity(vmake.WorkGraph, done, 0)
end

function vmake.SanitizeWorkGraph()
    local done = {}

    local function sanitizeEntity(ent, done)
        if done[ent] ~= nil then
            return done[ent]
        end

        local outdated = ent.Outdated

        local function checkOutdated(preq)
            if sanitizeEntity(preq, done) then
                outdated = true
                --  Upvalues, schmupvalues.
            end
        end

        --  Tthis otherwise up-to-date entity will become outdated if any of its
        --  prerequisites are outdated.

        ent.Prerequisites:ForEach(checkOutdated)

        if typeEx(ent) == "WorkLoad" then
            --  If this is a workload, any outdated item also makes it outdated.

            ent.Items:ForEach(checkOutdated)
        end

        --  If it's already outdated, then there's nothing that can change that.

        if not outdated then
            setWorkEntityOutdated(ent, outdated)

            setWorkEntityDone(ent)
            --  Nothing to do for this one.
        end

        done[ent] = outdated
        return outdated
    end

    sanitizeEntity(vmake.WorkGraph, done)
end

function vmake.DoWork()
    if not vmake.WorkGraph then
        error("vMake error: Unable to do work before building the work graph.")
    end

    if vmake.WorkGraph.Done then
        print("Nothing to do; everything is up-to-date.")
    end

    local doItem, doLoad

    doItem = function(item)
        if item.Done then
            return true
        end

        local res = item.Prerequisites:Any(function(preq)
            if typeEx(preq) == "WorkLoad" then
                return not doLoad(preq)
            else
                return not doItem(preq)
            end
        end)
        --  This will stop when the first one fails.

        if res then
            return false
        end

        local act = withEnvironment(item.Rule.Action, getEnvironment(item.Rule))

        MSG("Executing ", item)

        local oldCodeLoc = codeLoc; codeLoc = LOC_RULE_ACT
        curWorkItem = item

        res = vcall(act, item.Path, item.Sources)

        curWorkItem = nil
        codeLoc = oldCodeLoc

        if res.Error then
            io.stderr:write("Failed to execute action of ", tostring(item.Rule)
                , " for \"", tostring(item.Path), "\":\n", res:Print())
        end

        setWorkEntityDone(item)

        return not res.Error
    end
    
    doLoad = function(load)
        if load.Done then
            return true
        end

        local res = load.Prerequisites:Any(function(preq)
            return not doLoad(preq)
        end)

        if res then
            return false
        end

        return not load.Items:Any(function(item)
            return not doItem(item)
        end)
    end

    return doLoad(vmake.WorkGraph)
end

function vmake.HandleCapture()
    if vmake.WorkGraph.Done then
        return
    end

    if vmake.JobsDir then
        fs.MkDir(vmake.JobsDir)

        local shFiles = {}

        for lvl = 0, vmake.MaxLevel do
            local fName = tostring(vmake.JobsDir + ("batch-" .. lvl .. ".sh"))

            local fSh, errSh = io.open(fName, "w+")

            if not fSh then
                error("vMake internal error: Unable to open file \"" .. fName .. "\" to store level " .. lvl .. " shell commands: " .. errSh, 2)
            end

            shFiles[lvl] = {
                Descriptor = fSh,
                Path = fName,
                LogPath = vmake.JobsDir + ("log-" .. lvl .. ".txt")
            }
        end

        local commandAssoc = {}

        vmake.CommandLog:ForEach(function(e)
            local str, last = {}

            e.Commands:ForEach(function(cmd)
                if last then
                    if last.Tolerant then
                        str[#str + 1] = "; "
                    else
                        str[#str + 1] = " && "
                    end
                end

                str[#str + 1] = cmd.Command
                last = cmd
            end)

            str[#str + 1] = "\n"
            str = table.concat(str)

            e.ResultedCommand = str

            shFiles[e.WorkItem.Level].Descriptor:write(str)

            commandAssoc[str:trim()] = e.WorkItem
        end)

        for lvl = 0, #shFiles do
            shFiles[lvl].Descriptor:close()
        end

        for lvl = 0, #shFiles do
            local okay = sh.silent.tolerant("sh", "-c",
                sh.string("export", "PARALLEL_SHELL=/bin/sh", SH_AND
                , "parallel", vmake.ParallelOpts
                , "--joblog", shFiles[lvl].LogPath
                , "-a", shFiles[lvl].Path
                , "-j", vmake.Jobs))

            if not okay then
                local fLog, errLog = io.open(tostring(shFiles[lvl].LogPath), "r")

                if not fLog then
                    error("vMake internal error: Unable to open log file \"" .. tostring(shFiles[lvl].LogPath) .. "\" to determine which level " .. lvl .. " cmmand failed: " .. errLog, 2)
                end

                local firstLine = fLog:read("*l")

                if firstLine ~= "Seq\tHost\tStarttime\tJobRuntime\tSend\tReceive\tExitval\tSignal\tCommand" then
                    fLog:close()

                    error("vMake internal error: Format of log file \"" .. tostring(shFiles[lvl].LogPath) .. "\" needed to determine which level " .. lvl .. " command failed is unknown!")
                end

                local failedJobs = {}

                for line in fLog:lines() do
                    local jobId, jobHost, jobStart, jobRuntime, jobSend, jobReceive, jobExitVal, jobSignal, jobCommand
                        = line:match("^(%d+)%s+([^\t]*)%s+([%d%.,]+)%s+([%d%.,]+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(.*)$")

                    if not jobCommand then
                        fLog:close()

                        error("vMake internal error: Uknown format encountered in log file \"" .. tostring(shFiles[lvl].LogPath) .. "\" needed to determine which level " .. lvl .. " command failed:\n"
                            .. line .. "\n"
                            .. table.concat({jobId, jobHost, jobStart, jobRuntime, jobSend, jobReceive, jobExitVal, jobSignal, jobCommand}, "\t"))
                    end

                    if tonumber(jobExitVal) ~= 0 then
                        failedJobs[#failedJobs + 1] = {
                            ID = jobId,
                            Host = jobHost,
                            Start = jobStart,
                            Runtime = jobRuntime,
                            Send = jobSend,
                            Receive = jobReceive,
                            ExitValue = jobExitVal,
                            Signal = jobSignal,
                            Command = jobCommand,
                            WorkItem = commandAssoc[jobCommand:trim()],
                        }
                    end
                end

                fLog:close()

                if #failedJobs == 0 then
                    error("vMake internal error: Failed to execute level " .. lvl .. " shell commands, but unable to find relevant information in log files!")
                end

                io.stderr:write("----------------------------------------\n")

                for i = 1, #failedJobs do
                    local job = failedJobs[i]

                    if job.WorkItem then
                        io.stderr:write(" - ", tostring(job.WorkItem.Rule), " for \"", tostring(job.WorkItem.Path)
                            , "\":\nexit code ", tostring(job.ExitValue), "\n")
                    else
                        io.stderr:write(" - Unknown work item or path:\nexit code ", tostring(job.ExitValue), "\n")
                    end

                    io.stderr:write(job.Command, "\n")
                end

                io.stderr:write("----------------------------------------\n")

                error("vMake error: Failed to execute " .. (#failedJobs == 1 and "a" or #failedJobs) .. " level " .. lvl .. " shell command" .. (#failedJobs == 1 and "" or "s")
                    .. ", as listed above.")
            end
        end
    end
end

function vmake.PrintData()
    local dumpWorkItem, dumpWorkLoad

    local function itemOrList(val)
        if typeEx(val) == "List" then
            return tostring(#val) .. " items: " .. val:Print()
        else
            return tostring(val)
        end
    end

    local function dumpRule(rule, ind)
        if not ind then ind = "" end

        local res = ind .. tostring(rule) .. "\n"

        return res
    end

    local function dumpProject(proj, ind)
        if not ind then ind = "" end

        local res = ind .. tostring(proj) .. "\n"
            .. ind .. "  - Description: " .. (proj.Description or "--NONE--") .. "\n"
            .. ind .. "  - Directory: " .. tostring(proj.Directory) .. "\n"
            .. ind .. "  - Dependencies: " .. itemOrList(proj.Dependencies) .. "\n"
            .. ind .. "  - Output: " .. itemOrList(proj.Output) .. "\n"

        local ruls, comp = getProjectRules(proj), getProjectComponents(proj)

        res = res .. ind .. "  - Rules: (" .. #ruls .. ")\n"

        for i = 1, #ruls do
            res = res .. dumpRule(ruls[i], ind .. "    ")
        end

        if #comp > 0 then
            res = res .. ind .. "  - Components: (" .. #comp .. ")\n"

            for i = 1, #comp do
                res = res .. dumpProject(comp[i], ind .. "    ")
            end
        else
            res = res .. ind .. "  - Components: NONE\n"
        end

        return res
    end

    dumpWorkItem = function(wkit, ind, printed)
        if not ind then ind = "" end

        local res = ind .. tostring(wkit) .. "\n"

        if printed then
            if printed[wkit] then
                --  Won't print everything about a specific workload twice.

                return res
            else
                printed[wkit] = true
            end
        else
            printed = { [wkit] = true }
        end

        res = res .. ind .. "  - Level " .. tostring(wkit.Level) .. "\n"

        local newInd = ind .. "    "

        if wkit.Prerequisites and #wkit.Prerequisites > 0 then
            res = res .. ind .. "  - Prerequisites: (" .. #wkit.Prerequisites .. ")\n"
                .. table.concat(getListContainer(wkit.Prerequisites:Select(function(preq)
                    if typeEx(preq) == "WorkLoad" then
                        return dumpWorkLoad(preq, newInd, printed)
                    else
                        return dumpWorkItem(preq, newInd, printed)
                    end
                end)))
        else
            res = res .. ind .. "  - Prerequisites: NONE\n"
        end

        if wkit.Sources and #wkit.Sources > 0 then
            res = res .. ind .. "  - Sources: (" .. #wkit.Sources .. ")\n" .. ind .. "    "
                .. table.concat(getListContainer(wkit.Sources:Select(function(sorc)
                    return tostring(sorc)
                end)), "\n" .. ind .. "    ") .. "\n"
        else
            res = res .. ind .. "  - Sources: NONE\n"
        end

        return res
    end

    dumpWorkLoad = function(wkld, ind, printed)
        if not ind then ind = "" end

        local res = ind .. tostring(wkld) .. "\n"

        if printed then
            if printed[wkld] then
                --  Won't print everything about a specific workload twice.

                return res
            else
                printed[wkld] = true
            end
        else
            printed = { [wkld] = true }
        end

        res = res .. ind .. "  - Level " .. tostring(wkld.Level) .. "\n"

        local newInd = ind .. "    "

        if not wkld.Prerequisites then
            res = res .. ind .. "  - Prerequisites: Oh darn\n"
        elseif #wkld.Prerequisites > 0 then
            res = res .. ind .. "  - Prerequisites: (" .. #wkld.Prerequisites .. ")\n"
                .. table.concat(getListContainer(wkld.Prerequisites:Select(function(wkld)
                    return dumpWorkLoad(wkld, newInd, printed)
                end)))
        else
            res = res .. ind .. "  - Prerequisites: NONE\n"
        end

        if not wkld.Items then
            res = res .. ind .. "  - Items: Oh darn\n"
        elseif #wkld.Items > 0 then
            res = res .. ind .. "  - Items: (" .. #wkld.Items .. ")\n"
                .. table.concat(getListContainer(wkld.Items:Select(function(wkit)
                    return dumpWorkItem(wkit, newInd, printed)
                end)))
        else
            res = res .. ind .. "  - Items: NONE\n"
        end

        return res
    end

    return dumpProject(defaultProj) .. "\n" .. dumpWorkLoad(vmake.WorkGraph)
end

function vmake__call()
    vmake.ValidateAndDefault()

    vmake.ParallelOpts = vmake.Classes.List()
    vmake.CheckArguments()

    vmake.ExpandProperties()

    if vmake.ShouldClean then
        sh.silent("rm", "-Rf", outDir)
    end

    if vmake.ShouldComputeGraph then
        vmake.WorkGraph = vmake.ConstructWorkGraph()

        if not vmake.FullBuild then
            vmake.SanitizeWorkGraph()
        end

        vmake.ChartWorkGraph()

        if vmake.ShouldDoWork then
            if vmake.Jobs then
                vmake.Capturing = true
                vmake.CommandLog = List { }
            end

            local res = vmake.DoWork()

            if not res then
                os.exit(2)
            end

            if vmake.Capturing then
                vmake.HandleCapture()
            end
        end

        if vmake.ShouldPrintGraph then
            print(vmake.PrintData())
        end
    end
end

function vmake.CheckGnuParallel()
    if vmake.HasGnuParallel then
        return true
    end

    if os.execute("parallel --version > /dev/null") then
        vmake.HasGnuParallel = true
    else
        error("vMake error: GNU Parallel is required (for now, in $PATH) for non-serial execution.")
    end
end

--  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --
--  Command-line Options
--  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --

CmdOpt "help" "h" {
    Description = "Displays available command-line options.",

    Handler = function()
        local parts = {}

        local function printHierarchy(val)
            parts[#parts + 1] = "    - "
            parts[#parts + 1] = val.Name

            local tmp = val.Base

            while tmp do
                parts[#parts + 1] = " -> "
                parts[#parts + 1] = tmp.Name

                tmp = tmp.Base
            end

            parts[#parts + 1] = "\n"
        end

        local function printDesc(val)
            if val.Description then
                for line in val.Description:iteratesplit("\n", true) do
                    parts[#parts + 1] = "        "
                    parts[#parts + 1] = line
                    parts[#parts + 1] = "\n"
                end
            end
        end

        if arg and arg[0] then
            parts[#parts + 1] = "Usage: "
            parts[#parts + 1] = arg[0]
            parts[#parts + 1] = " [options] [--] [project, architecture & configuration]\n\n"
        end

        for i = 1, #cmdlopts do
            local opt = cmdlopts[i]

            parts[#parts + 1] = "    --"
            parts[#parts + 1] = opt.Name

            if opt.Type then
                parts[#parts + 1] = "=<"
                parts[#parts + 1] = opt.Display or opt.Type
                parts[#parts + 1] = ">"
            end

            if opt.ShortName then
                parts[#parts + 1] = "  -"
                parts[#parts + 1] = opt.ShortName

                if opt.Type then
                    parts[#parts + 1] = " <"
                    parts[#parts + 1] = opt.Display or opt.Type
                    parts[#parts + 1] = ">"
                end
            end

            parts[#parts + 1] = "\n"

            printDesc(opt)

            parts[#parts + 1] = "\n"
        end

        parts[#parts + 1] = "Projects:\n"

        for i = 1, #projects do
            local val = projects[i]

            parts[#parts + 1] = "    - "
            parts[#parts + 1] = val.Name
            parts[#parts + 1] = "\n"

            printDesc(val)
        end

        parts[#parts + 1] = "\nArchitectures:\n"

        for i = 1, #archs do
            local val = archs[i]
            local tmp = val.Base

            if not val.Auxiliary then
                printHierarchy(val)
                printDesc(val)
            end
        end

        parts[#parts + 1] = "\nConfigurations:\n"

        for i = 1, #configs do
            local val = configs[i]
            local tmp = val.Base

            if not val.Auxiliary then
                printHierarchy(val)
                printDesc(val)
            end
        end

        parts[#parts + 1] = "\nPowered by "
        parts[#parts + 1] = vmake.Description

        print(table.concat(parts))
        vmake.ShouldComputeGraph = false
    end,
}

CmdOpt "version" "v" {
    Description = "Displays brief information about vMake.",

    Handler = function()
        print(vmake.Description)
        vmake.ShouldComputeGraph = false
    end,
}

CmdOpt "debug" {
    Description = "Enables some debugging features, making the code more strict,"
             .. "\nexposing possibly unwanted behaviour.",

    Handler = function()
        vmake.Debug = true
    end,
}

CmdOpt "print" {
    Description = "Prints all the defined data and the computed work graph"
             .. "\n(a directed dependency graph) which would otherwise be executed.",

    Handler = function()
        vmake.ShouldPrintGraph = true
        vmake.ShouldDoWork = false
    end,
}

CmdOpt "clean" "c" {
    Description = "Cleans the output directory."
             .. "\nWill not perform a build unless `--full` is also specified.",

    Handler = function()
        vmake.ShouldClean = true

        if not vmake.FullBuild then
            vmake.ShouldComputeGraph = false
        end
    end,
}

CmdOpt "full" "f" {
    Description = "Indicates that work items should be executed even if they"
             .. "\nare considered up-to-date.",

    Handler = function()
        vmake.FullBuild = true

        if vmake.ShouldClean then
            vmake.ShouldComputeGraph = true
        end
    end,
}

CmdOpt "jobs" "j" {
    Description = "Number of jobs to use for rule action execution."
             .. "\n0 means unlimited. Defaults to 1, meaning serial execution.",

    Type = "integer",

    Handler = function(val)
        if val < 0 then
            error("vMake error: Number of jobs must be 0 for unlimited or a positive integer.")
        end

        if val ~= 1 then
            vmake.CheckGnuParallel()

            vmake.Jobs = val
        end
    end,
}

CmdOpt "parallel-bar" {
    Description = "Enables the display of a progress bar when using GNU Parallel.",

    Handler = function()
        vmake.CheckGnuParallel()

        vmake.ParallelOpts:Append("--bar")
    end,
}

CmdOpt "silent" {
    Description = "Omits unsilenced shell commands from standard output.",

    Handler = function()
        if vmake.Verbose then
            error("vMake error: Cannot be silent and verbose at the same time.")
        end

        vmake.Silent = true
    end,
}

CmdOpt "verbose" {
    Description = "Outputs more detailed information to standard output,"
             .. "\nsuch as the steps taken by vMake and all shell commands executed.",

    Handler = function()
        if vmake.Silent then
            error("vMake error: Cannot be silent and verbose at the same time.")
        end
        
        vmake.Verbose = true
    end,
}

--  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --
--  Wrap Up
--  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --

_G.vmake = setmetatable({

}, {
    __metatable = "Nooooooooope.",

    __index = vmake,

    __newindex = function(self, key, val)
        error("vMake error: Cannot modify key '" .. tostring(key) .. "' of the 'vmake' global table.", 2)
    end,

    __call = vmake__call,
})

--  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --
--  OS Environment Library
--  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --

local osenvmeta = {
    __metatable = "Still noooo."
}

function osenvmeta.__index(self, key)
    return os.getenv(key)
end

env = setmetatable({ }, osenvmeta)

--  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --
--  List Utilities
--  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --

local bracketPairs = { ["["] = "]", ["]"] = "["
                    ,  ["("] = ")", [")"] = "("
                    ,  ["{"] = "}", ["}"] = "{" }

local function parseListElement(line, linelen, i)
    local res = {}

    local inEscape, inSQ, inDQ, afterSpecial = false, false, false, false
    local parenStack, quoteStart = {}

    local firstChar = line:sub(i, i)
    local firstCharSpecial = string.find("!$", firstChar, 1, true)
    -- local firstCharSpecial = string.find("!@$", firstChar, 1, true)

    if not firstCharSpecial then
        firstChar = false
    end

    while i <= linelen do
        local c = line:sub(i, i)

        if not c then break end

        if afterSpecial then
            --  After a special character, only an opening square bracket or an identifier may follow.

            if c == "[" then
                if afterSpecial ~= "!" then
                    parenStack[#parenStack + 1] = c
                else
                    return table.concat(res), i, firstChar, string.format("Exclamation mark at character #%d must be followed directly by an identifier, not opening square brackets", i - 1)
                end
            elseif c:match("([_a-zA-Z])") then
                --  Okay, this is an identifier. Means a period must be added before it.

                if afterSpecial ~= "!" then
                    res[#res + 1] = "."
                end
            else
                --  This ought to be wrong.

                if afterSpecial == "!" then
                    return table.concat(res), i, firstChar, string.format("Special character '%s' at #%d must be followed directly by an identifier", afterSpecial, i - 1)
                else
                    return table.concat(res), i, firstChar, string.format("Special character '%s' at #%d must be followed directly by an identifier or opening square brackets", afterSpecial, i - 1)
                end
            end
            
            res[#res + 1] = c

            afterSpecial = false
        elseif inEscape then
            if c == 'n' then
                res[#res + 1] = '\n'
            elseif c == 't' then
                res[#res + 1] = '\t'
            elseif c == 'b' then
                res[#res + 1] = '\b'
            else
                res[#res + 1] = c
            end

            inEscape = false
        elseif quoteStart then
            if c == '\\' then
                inEscape = true
            elseif inSQ and c == "'" then
                quoteStart = nil
                inSQ = false
            elseif inDQ and c == '"' then
                quoteStart = nil
                inDQ = false
            else
                res[#res + 1] = c
            end
        else
            if c == '\\' then
                if firstCharSpecial then
                    --  Escape sequences can only show up inside quotes if the first character is special.

                    return table.concat(res), i, firstChar, string.format("Escape sequences in special elements can only appear within quotes (strings); backslash at character #%d is invalid", i)
                else
                    inEscape = true
                end
            elseif c == '"' then
                quoteStart = i
                inDQ = true
            elseif c == "'" then
                quoteStart = i
                inSQ = true
            elseif string.find(" \t\n", c, 1, true) and #parenStack == 0 then
                --  This is clearly an element separator.

                i = i - 1

                break
            elseif firstCharSpecial then
                if string.find("([{", c, 1, true) then
                    parenStack[#parenStack + 1] = c
                    res[#res + 1] = c
                elseif string.find(")]}", c, 1, true) then
                    if parenStack[#parenStack] == bracketPairs[c] then
                        parenStack[#parenStack] = nil
                        res[#res + 1] = c
                    elseif #parenStack == 0 then
                        --  Stray bracket.

                        return table.concat(res), i, firstChar, string.format("Stray closing bracket '%s' at character #%d", c, i)
                    else
                        --  Unmatching bracket.

                        return table.concat(res), i, firstChar, string.format("Unexpected closing bracket '%s' at character #%d; expected '%s'", c, i, parenStack[#parenStack])
                    end
                -- elseif c == "@" then
                --     res[#res + 1] = " _"
                --     afterSpecial = c
                elseif c == "$" then
                    res[#res + 1] = " env"
                    afterSpecial = c
                elseif c == "!" then
                    res[#res + 1] = " "
                    afterSpecial = c
                else
                    res[#res + 1] = c
                end
            else
                res[#res + 1] = c
            end
        end

        i = i + 1
    end

    res = table.concat(res)

    if inEscape then
        return res, i, firstChar, "Unfinished escape sequence at character #" .. (i - 1)
    end

    if inSQ then
        return res, i, firstChar, "Unpaired single quotes at character #" .. quoteStart
    end

    if inDQ then
        return res, i, firstChar, "Unpaired double quotes at character #" .. quoteStart
    end

    if #parenStack > 0 then
        return res, i, firstChar, "Missing closing brackets for the following opened brackets: " .. table.concat(parenStack)
    end

    return res, i, firstChar
end

local function parseListInner(line, linelen)
    local res, i, special, err = nil, 1
    local arr = {}

    while i <= linelen do
        local c, oldPos = line:sub(i, i), i

        if not string.find(" \t\n", c, 1, true) then
            --  Whitespaces are completely ignored between elements.

            res, i, special, err = parseListElement(line, linelen, i)

            if res ~= nil then
                arr[#arr + 1] = { Text = res, Special = special, Position = oldPos }
            end

            if err then
                return arr, err, i
            end
        end
        
        i = i + 1
    end

    return arr
end

local function parseList(str)
    return parseListInner(str, #str)
end

do
    local listCache = {}
    --  Note, this caches the list creator chunks, not the lists themselves.

    function List(tab)
        local tabType = assertType({"string", "table"}, tab, "list array", 2)

        if listCache[tab] then
            return listCache[tab]()
        end

        if tabType == "table" then
            if not table.isarray(tab) then
                error("vMake error: List must be initialized with a pure array table.", 2)
            end

            local res = vmake.Classes.List(false, tab)

            listCache[tab] = res

            return res
        else
            local lst, err = parseList(tab)

            if err then
                error("vMake error: List syntax error: " .. err, 2)
            end

            local template, values = { "return List {\n" }, { }

            for i = 1, #lst do
                values[i] = lst[i].Text

                if lst[i].Special then
                    -- if lst[i].Special == "@" then
                    --     error("vMake error: List semantics error: Cannot use special character '@' in this context.", 2)
                    -- end

                    if i == 1 then
                        template[2] = "%s\n"
                    else
                        template[i + 1] = ", %s\n"
                    end
                else
                    if i == 1 then
                        template[2] = "%q\n"
                    else
                        template[i + 1] = ", %q\n"
                    end
                end
            end

            template[#template + 1] = "}\n"

            template = table.concat(template):format(unpack(values))

            --  Okay, that code now needs to be executed.

            local res, err = loadstring(template, "temporary list creator")

            if res then
                listCache[tab] = res

                return res()
            end

            local endState = GatherEndState(err)

            io.stderr:write("Failed to parse temporary list creator:\n"
                , template
                , endState:Print())

            os.exit(4)
        end
    end
    baseEnvironment.List = List
end

--  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --
--  Lambda Utilities
--  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --

function L(code)
    assertType("string", code, "lambda code", 2)

    local params, expression = code:match("^%s*|(.-)|(.+)$")

    if not params or not expression then
        error("vMake error: Lambda code should be in the format \"|arg1, arg2, ...| expression\".", 2)
    end

    return loadstring(
([[return function(%s)
    return %s
end]]):format(params, expression)
        , "lambda")()
end
baseEnvironment.L = L

local function lambdaShortcut(name, params, filter)
    assertType("string", name, "lambda shortcut name", 2)
    assertType("string", params, "lambda shortcut parameters", 2)
    assertType({"nil", "function"}, filter, "lambda shortcut filter", 2)

    local anonFuncTemplate =
([[return function(%s)
    return %%s
end
]]):format(params)

    local cache = {}

    if filter then
        local chunkName = "filtered " .. name .. " lambda"
        local expName = chunkName .. " expression"

        return function(unfiltered)
            if unfiltered == nil then
                error("vMake error: Must pass non-nil value to " .. name .. " lambda generator.", 2)
            end

            if cache[unfiltered] then
                return cache[unfiltered]
            end

            local expression, endState = vcall(filter, unfiltered)

            if expression.Return then
                expression = expression.Return[1]

                assertType("string", expression, expName, 2)
                expression = anonFuncTemplate:format(expression)

                local res, err = loadstring(expression, chunkName)

                if res then
                    res = res()
                    cache[unfiltered] = res

                    return res
                end

                endState = GatherEndState(err)
            else
                endState = expression

                expression = ''
            end

            io.stderr:write("Failed to parse filtered " .. name .. " lambda:\n"
                , expression
                , "UNFILTERED:\n", unfiltered, "\n"
                , endState:Print())

            os.exit(3)
        end
    else
        return function(expression)
            assertType("string", expression, expName, 2)

            if cache[unfiltered] then
                return cache[unfiltered]
            end

            expression = anonFuncTemplate:format(expression)
            local res, err = loadstring(expression, chunkName)

            if res then
                res = res()
                cache[unfiltered] = res

                return res
            end

            local endState = GatherEndState(err)

            io.stderr:write("Failed to parse " .. name .. " lambda:\n"
                , expression
                , endState:Print())

            os.exit(3)
        end
    end
end

DAT = lambdaShortcut("data", "_", function(exp)
    assertType("string", exp, "data lambda expression", 3)

    local res, lastSep, lastWasEmpty = {}, nil, false

    for chunk, sep in string.iteratesplit(exp, '[%$]') do
        if lastSep then
            if lastWasEmpty then
                res[#res + 1] = lastSep
                res[#res + 1] = chunk

                lastWasEmpty = false
            else
                if #chunk == 0 then
                    lastWasEmpty = true
                else
                    if chunk:sub(1, 1) == '[' then
                        res[#res + 1] = " env"
                    elseif chunk:match("^([_a-zA-Z])") then
                        res[#res + 1] = " env."
                    else
                        error("Data lambda syntax error: '" .. lastSep .. "' should directly preceed an identifier or an array index (in square brackets).")
                    end

                    res[#res + 1] = chunk
                end
            end
        elseif #chunk > 0 then
            res[#res + 1] = chunk
        end

        lastSep = sep
    end

    if lastWasEmpty then
        error("Data lambda syntax error: '" .. exp:sub(-1) .. "' was encountered at the end of the code; it should directly preceed an identifier or an array index (in square brackets).")
    end

    return table.concat(res)
end)

FLT = lambdaShortcut("rule filter", "dst", function(exp)
    assertType("string", exp, "rule filter lambda expression", 3)

    local res, lastSep, lastWasEmpty = {}, nil, false

    for chunk, sep in string.iteratesplit(exp, '[%$]') do
        if lastSep then
            if lastWasEmpty then
                res[#res + 1] = lastSep
                res[#res + 1] = chunk

                lastWasEmpty = false
            else
                if #chunk == 0 then
                    lastWasEmpty = true
                else
                    if chunk:sub(1, 1) == '[' then
                        res[#res + 1] = " env"
                    elseif chunk:match("^([_a-zA-Z])") then
                        res[#res + 1] = " env."
                    else
                        error("Rule filter lambda syntax error: '" .. lastSep .. "' should directly preceed an identifier or an array index (in square brackets).")
                    end

                    res[#res + 1] = chunk
                end
            end
        elseif #chunk > 0 then
            res[#res + 1] = chunk
        end

        lastSep = sep
    end

    if lastWasEmpty then
        error("Rule filter lambda syntax error: '" .. exp:sub(-1) .. "' was encountered at the end of the code; it should directly preceed an identifier or an array index (in square brackets).")
    end

    return table.concat(res)
end)

LST = lambdaShortcut("data list", "", function(exp)
    assertType("string", exp, "data list lambda expression", 3)

    local lst, err = parseList(exp)

    if err then
        error("Data list syntax error: " .. err, 3)
    end

    local template, values = { "List {\n" }, { }

    for i = 1, #lst do
        values[i] = lst[i].Text

        if lst[i].Special then
            if i == 1 then
                template[2] = "%s\n"
            else
                template[i + 1] = ", %s\n"
            end
        else
            if i == 1 then
                template[2] = "%q\n"
            else
                template[i + 1] = ", %q\n"
            end
        end
    end

    template[#template + 1] = "}\n"

    return table.concat(template):format(unpack(values))
end)

ACT = lambdaShortcut("rule action", "dst, src", function(exp)
    assertType("string", exp, "rule action lambda expression", 3)

    local lst, err = parseList(exp)

    if err then
        error("Rule action lambda syntax error: " .. err, 3)
    end

    if #lst == 0 then
        error("Rule action lambda mustn't be empty.", 3)
    end

    local template, values = { "sh.silent(\n" }, { }

    for i = 1, #lst do
        values[i] = lst[i].Text

        if lst[i].Special then
            if i == 1 then
                template[2] = "%s\n"
            else
                template[i + 1] = ", %s\n"
            end
        else
            if i == 1 then
                template[2] = "%q\n"
            else
                template[i + 1] = ", %q\n"
            end
        end
    end

    template[#template + 1] = ")\n"

    return table.concat(template):format(unpack(values))
end)

--  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --
--  Some common templates
--  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --

--  Does what it says on the tin. It's a blank tin.
function DoNothing() end
baseEnvironment.DoNothing = DoNothing

--  Ditto.
function NewList() return List { } end
baseEnvironment.NewList = NewList

--  An action which copies a single source file to the destination.
function CopySingleFileAction(dst, src)
    fs.Copy(dst, src[1])
end

--  Creates a rule which pretends to provide missing files matching the given
--  set of extensions.
function ExcuseMissingFilesRule(ext)
    assertType({"string", "List", "table", "function"}, ext, "extension(s)", 2)

    return Rule "Excuse Missing Headers" {
        Data = {
            ExcusedExtensionsSource = ext,

            ExcusedExtensions = function()
                local ext = ExcusedExtensionsSource

                local extType = assertType({"string", "List", "table"}, ext, "extension expansion", 1)

                if extType == "string" then
                    ext = vmake.Classes.List(true, { ext })
                else
                    for i = 1, #ext do
                        assertType("string", ext[i], "extension #" .. i, 1)
                    end

                    if extType == "table" then
                        ext = vmake.Classes.List(true, ext)
                    else
                        ext:Seal(true)
                    end
                end

                return ext
            end,
        },

        Filter = function(dst)
            return dst:CheckExtension(ExcusedExtensions) and not fs.GetInfo(dst)
        end,

        Source = NewList,

        Action = DoNothing,
    }
end

--  Creates a rule which creates missing directories.
function CreateMissingDirectoriesRule(shared)
    return Rule "Create Missing Directories" {
        Shared = shared or false,

        Filter = function(dst) return dst.IsDirectory end,

        Action = function(dst, src)
            fs.MkDir(dst)
        end,
    }
end

--  Parses the GCC-generated Make dependency file associated with the given
--  destination file, if found and possible.
--  Any form of failure results in an empty list being returned.
function ParseGccDependencies(dst, src, keepSrc)
    assertType("Path", dst, "destination file")
    assertType({"nil", "Path"}, src, "main source file")
    assertType({"nil", "boolean"}, keepSrc, "keep source")

    if not fs.GetInfo(dst) then
        --  Destination doesn't exist? It will be created anyway, so parsing the
        --  (leftover) dependency files will not help in any way.

        return keepSrc and vmake.Classes.List(false, { src }) or vmake.Classes.List()
    end

    local dep = dst:ChangeExtension("d")
    --  '.o' -> '.d'

    local fDep, errDep = io.open(tostring(dep), "r")

    if not fDep then
        --  This is not really a problem. Maybe it doesn't exist. Maybe the dog
        --  ate it. No probz.

        MSG("Failed to open dependecy file \"", dep, "\": ", errDep)

        return keepSrc and vmake.Classes.List(false, { src }) or vmake.Classes.List()
    end

    local firstLine = fDep:read("*l")

    if not firstLine then
        return keepSrc and vmake.Classes.List(false, { src }) or vmake.Classes.List()
    end

    local deps, lineCnt, file, dep1 = {}, 1, firstLine:match("^(.-):(.-) \\$")

    if dep1 and dep1 ~= "" then
        deps[1] = dep1:trim()
    end

    for line in fDep:lines() do
        local content, ending = line:match("^ (.-)( ?\\?)$")
        lineCnt = lineCnt + 1

        if ending ~= "" and ending ~= " \\" then
            --  This is just wrong. Abandon.

            MSG("Odd ending in dependency file \"", dep, "\" line ", lineCnt, ": ", ending)

            return keepSrc and vmake.Classes.List(false, { src }) or vmake.Classes.List()
        end

        local lastWasEscaped = false

        for comp, sep in content:iteratesplit("%s+") do
            local backslashes = comp:match("^.-(\\*)$")
            local thisIsEscaped = backslashes and (#backslashes % 2 == 1)

            if lastWasEscaped then
                deps[#deps] = deps[#deps] .. comp
            else
                deps[#deps + 1] = comp
            end

            lastWasEscaped = thisIsEscaped

            if thisIsEscaped then
                if sep then
                    deps[#deps] = deps[#deps] .. sep
                else
                    MSG("An escaped dependency fragment to be at the end of a line:\n", line, "\n", comp)

                    return keepSrc and vmake.Classes.List(false, { src }) or vmake.Classes.List()
                end
            end
        end

        if lastWasEscaped then
            --  Should always be false at the end.

            return keepSrc and vmake.Classes.List(false, { src }) or vmake.Classes.List()
        end

        if ending == "" then
            break
        end
    end

    fDep:close()

    --  TODO: Parse escape sequences (..?) in the dependencies.

    deps = vmake.Classes.List(false, deps):Where(function(val)
        return val and not val:match("^%s*$")
    end)

    if keepSrc then
        if not src:Equals(deps:First()) then
            deps = vmake.Classes.List(false, { src }) + deps:Where(function(val)
                return not src:Equals(val)
            end)
        end
    else
        deps = deps:Where(function(val)
            return not src:Equals(val)
        end)
    end

    return deps
end
baseEnvironment.ParseGccDependencies = ParseGccDependencies

local function parseObjectExtension(path, header)
    if header then
        return tostring(path):match("^(.+)%.gch$")
    else
        local part1, part2 = tostring(path):match("^(.+)%.([^%.]+)%.o$")

        if not part1 then
            return nil, nil
        end

        local arch = GetArchitecture(part2)

        if arch then
            return part1, arch
        else
            return part1 .. "." .. part2, nil
        end
    end
end

local function checkObjectExtension(path, ext, header)
    local part1, part2 = tostring(path):match(header and "^(.+)%.([^%.]+)%.gch$"
                                                     or  "^(.+)%.([^%.]+)%.o$")

    if not part1 then
        return false
    end

    if GetArchitecture(part2) then
        return part1:sub(-#ext - 1) == "." .. ext
    else
        return part2 == ext
    end
end

local function sourceArchitecturalCode(dst)
    local file, arch, src, res = parseObjectExtension(dst, false)

    if arch then
        if SourcesSubdirectory then
            src = ArchitecturesDirectory + arch.Name + SourcesSubdirectory + Path(file):Skip(ObjectsDirectory)
        else
            src = ArchitecturesDirectory + arch.Name + Path(file):Skip(ObjectsDirectory)
        end
    else
        if SourcesSubdirectory then
            src = CommonDirectory + SourcesSubdirectory + Path(file):Skip(ObjectsDirectory)
        else
            src = CommonDirectory + Path(file):Skip(ObjectsDirectory)
        end
    end

    if UseMakeDependencies then
        res = ParseGccDependencies(dst, src, true) + List { dst:GetParent() }
    else
        res = List { src, dst:GetParent() }
    end

    if PrecompiledCppHeader then
        res:Append(PrecompiledCppHeaderPath .. ".gch")
    end

    return res
end

local function sourceArchitecturalHeader(dst)
    local file, src, res = parseObjectExtension(dst, true), nil
    file = Path(file):Skip(PchDirectory)

    if HeadersSubdirectory then
        for arch in selArch:Hierarchy() do
            local pth = ArchitecturesDirectory + arch.Name + HeadersSubdirectory + file

            if fs.GetInfo(pth) then
                src = pth

                break
            end
        end

        if not src then
            src = comp.Directory + HeadersSubdirectory + file
        end
    else
        for arch in selArch:Hierarchy() do
            local pth = ArchitecturesDirectory + arch.Name + file

            if fs.GetInfo(pth) then
                src = pth

                break
            end
        end

        if not src then
            src = comp.Directory + file
        end
    end

    if UseMakeDependencies then
        res = ParseGccDependencies(dst, src, true) + List { dst:GetParent() }
    else
        res = List { src, dst:GetParent() }
    end

    return res
end

local function generateManagedComponent(compType)
    return function(name)
        local comp = compType(name)({ })

        local data = {
            CommonDirectory = DAT "comp.Directory",
            ArchitecturesDirectory = DAT "comp.Directory",

            SourcesSubdirectory = false,
            HeadersSubdirectory = false,

            IncludeDirectories = function()
                local res = List { }

                if PrecompiledCHeader or PrecompiledCppHeader then
                    res:Append(PchDirectory)
                end

                if HeadersSubdirectory then
                    res:Append(comp.Directory + HeadersSubdirectory)

                    for arch in selArch:Hierarchy() do
                        res:Append(ArchitecturesDirectory + arch.Name + HeadersSubdirectory)
                    end
                else
                    res:Append(comp.Directory)

                    for arch in selArch:Hierarchy() do
                        res:Append(ArchitecturesDirectory + arch.Name)
                    end
                end

                return res
            end,

            Opts_Includes_Base = function()
                return IncludeDirectories:Select(function(val) return "-I" .. val end)
            end,

            Opts_Includes_Nasm_Base = function()
                return Opts_Includes_Base:Select(function(dir) return dir .. "/" end)
            end,

            Opts_Includes      = DAT "Opts_Includes_Base",
            Opts_Includes_Nasm = DAT "Opts_Includes_Nasm_Base",

            Opts_Libraries = function()
                return Libraries:Select(function(val)
                    return "-l" .. val
                end)
            end,

            Libraries = List { },   --  Default to none.

            ObjectsDirectory = DAT "outDir + comp.Directory",

            Objects = function()
                local comSrcDir = CommonDirectory

                if SourcesSubdirectory then
                    comSrcDir = comSrcDir + SourcesSubdirectory
                end

                local objects = fs.ListDir(comSrcDir)
                    :Where(function(val) return val:EndsWith(SourceExtensions:Unpack()) end)
                    :Select(function(val)
                        return ObjectsDirectory + val:Skip(comSrcDir) .. ".o"
                    end)

                for arch in selArch:Hierarchy() do
                    local arcSrcDir = ArchitecturesDirectory + arch.Name
                    local suffix = "." .. arch.Name .. ".o"

                    if SourcesSubdirectory then
                        arcSrcDir = arcSrcDir + SourcesSubdirectory
                    end

                    if fs.GetInfo(arcSrcDir) then
                        objects:AppendMany(fs.ListDir(arcSrcDir)
                            :Where(function(val) return val:EndsWith(SourceExtensions:Unpack()) end)
                            :Select(function(val)
                                return ObjectsDirectory + val:Skip(arcSrcDir) .. suffix
                            end))
                    end
                end

                return objects
            end,

            PchDirectory = DAT "outDir + comp.Directory + '.pch'",

            PrecompiledCHeaderPath   = DAT "PchDirectory + PrecompiledCHeader",
            PrecompiledCppHeaderPath = DAT "PchDirectory + PrecompiledCppHeader",

            SourceExtensions = function()
                return Languages:Select(function(lang)
                    if lang == "C++" then
                        return ".cpp"
                    elseif lang == "C" then
                        return ".c"
                    elseif lang == "GAS" then
                        return ".S"
                    elseif lang == "NASM" then
                        return ".asm"
                    else
                        error("vMake error: Unknown complex project/component language: " .. lang)
                    end
                end)
            end,

            HeaderExtensions = function()
                local res = Languages:SelectUnique(function(lang)
                    if lang == "C++" then
                        return ".hpp"
                    elseif lang == "C" then
                        return ".h"
                    elseif lang == "GAS" then
                        return ".h" --  Yes, GAS uses C headers.
                    elseif lang == "NASM" then
                        return ".inc"
                    else
                        error("vMake error: Unknown complex project/component language: " .. lang)
                    end
                end)

                res:AppendUnique(".inc")
                --  Yes, `.inc` is kinda universal.

                return res
            end,

            BinaryPath = DAT "comp.Output:First()",

            BinaryDependencies = List { },

            LinkerScript = false,
        }

        local langsProvided, targetProvided, excusesHeaders = false, false, false

        return function(tab)
            assertType("table", tab, name .. " table", 2)

            for k, v in pairs(tab) do
                if k == "Data" then
                    for dk, dv in pairs(v) do
                        data[dk] = dv
                    end
                elseif k == "Languages" then
                    local langsType = assertType({"string", "List", "table"}, v, "Languages", 2)

                    if langsType == "string" then
                        v = List { v }
                    elseif langsType == "table" then
                        v = List(v)
                    end

                    langsProvided = v
                elseif k == "Target" then
                    assertType("string", v, "Target", 2)

                    targetProvided = v
                elseif k == "ExcuseHeaders" then
                    assertType("boolean", v, "ExcuseHeaders", 2)

                    excusesHeaders = v
                elseif type(k) == "string" then
                    comp[k] = v
                end
            end

            if not langsProvided then
                error("vMake error: Complex project/component needs `Languages` property.", 2)
            end

            if langsProvided:Contains("C") then
                comp:AddMember(Rule "Compile C" {
                    Filter = function(dst) return checkObjectExtension(dst, "c", false) end,

                    Source = sourceArchitecturalCode,

                    Action = ACT "!CC !Opts_C -x c -c !src[1] -o !dst",
                })

                comp:AddMember(Rule "Precompile C Header" {
                    Filter = function(dst) return checkObjectExtension(dst, "h", true) end,

                    Source = sourceArchitecturalHeader,

                    Action = ACT "!CC !Opts_C -x c-header -c !src[1] -o !dst",
                })
            end

            if langsProvided:Contains("C++") then
                comp:AddMember(Rule "Compile C++" {
                    Filter = function(dst) return checkObjectExtension(dst, "cpp", false) end,

                    Source = sourceArchitecturalCode,

                    Action = ACT "!CXX !Opts_CXX -x c++ -c !src[1] -o !dst",
                })

                comp:AddMember(Rule "Precompile C++ Header" {
                    Filter = function(dst) return checkObjectExtension(dst, "hpp", true) end,

                    Source = sourceArchitecturalHeader,

                    Action = ACT "!CXX !Opts_CXX -x c++-header -c !src[1] -o !dst",
                })
            end

            if langsProvided:Contains("GAS") then
                comp:AddMember(Rule "Assemble w/ GAS" {
                    Filter = function(dst) return checkObjectExtension(dst, "S", false) end,

                    Source = sourceArchitecturalCode,

                    Action = ACT "!GAS !Opts_GAS -x assembler-with-cpp -c !src[1] -o !dst",
                })
            end

            if langsProvided:Contains("NASM") then
                comp:AddMember(Rule "Assemble w/ NASM" {
                    Filter = function(dst) return checkObjectExtension(dst, "asm", false) end,

                    Source = sourceArchitecturalCode,

                    Action = ACT "!AS !Opts_NASM !src[1] -o !dst",
                })
            end

            if not targetProvided then
                targetProvided = "Executable"

                MSG("No Target provided for managed project/component \"", name, "\"; assuming 'Executable'.")
            end

            if targetProvided == "Executable" then
                comp:AddMember(Rule "Link Executable" {
                    Filter = function(dst) return BinaryPath end,

                    Source = function(dst)
                        if LinkerScript then
                            return Objects + List { dst:GetParent(), LinkerScript } + BinaryDependencies
                        else
                            return Objects + List { dst:GetParent() } + BinaryDependencies
                        end
                    end,

                    Action = function(dst, src)
                        if LinkerScript then
                            sh.silent(LD, Opts_LD, "-T", LinkerScript, "-o", dst, Objects, Opts_Libraries)
                        else
                            sh.silent(LD, Opts_LD, "-o", dst, Objects, Opts_Libraries)
                        end
                    end,
                })
            elseif targetProvided == "Dynamic Library" then
                comp:AddMember(Rule "Link Dynamic Library" {
                    Filter = function(dst) return BinaryPath end,

                    Source = function(dst)
                        if LinkerScript then
                            return Objects + List { dst:GetParent(), LinkerScript } + BinaryDependencies
                        else
                            return Objects + List { dst:GetParent() } + BinaryDependencies
                        end
                    end,

                    Action = function(dst, src)
                        if LinkerScript then
                            sh.silent(LD, "-shared", Opts_LD, "-T", LinkerScript, "-o", dst, Objects, Opts_Libraries)
                        else
                            sh.silent(LD, "-shared", Opts_LD, "-o", dst, Objects, Opts_Libraries)
                        end
                    end,
                })
            elseif targetProvided == "Static Library" then
                comp:AddMember(Rule "Archive Objects" {
                    Filter = function(dst) return BinaryPath end,

                    Source = function(dst)
                        return Objects + List { dst:GetParent() } + BinaryDependencies 
                    end,

                    Action = ACT "!AR !Opts_AR !dst !Objects",
                })
            elseif targetProvided ~= "Custom" then
                error("vMake error: Unknown complex project/component target: " .. tostring(targetProvided)
                    .. "; Supported values: 'Executable', 'Dynamic Library', 'Static Library', and 'Custom'")
            end

            if excusesHeaders then
                comp:AddMember(ExcuseMissingFilesRule(function()
                    return HeaderExtensions:Select(function(ext)
                        return ext:sub(1)
                        --  Skips the dot.
                    end)
                end))
            end

            data.Languages = langsProvided
            data.Target = targetProvided
            data.ExcusesHeaders = excusesHeaders

            comp.Data = data

            for i = 1, #tab do
                comp:AddMember(tab[i])
            end

            return comp
        end
    end
end

ManagedProject = generateManagedComponent(Project)
ManagedComponent = generateManagedComponent(Component)
