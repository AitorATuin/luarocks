
--- Sandboxed test of build/install of all packages in a repository (unfinished and disabled).
module("luarocks.validate", package.seeall)

local fs = require("luarocks.fs")
local dir = require("luarocks.dir")
local path = require("luarocks.path")
local cfg = require("luarocks.cfg")
local build = require("luarocks.build")
local install = require("luarocks.install")
local util = require("luarocks.util")

help_summary = "Sandboxed test of build/install of all packages in a repository."

help = [[
<argument>, if given, is a local repository pathname.
]]

local function save_settings(repo)
   local protocol, path = dir.split_url(repo)
   table.insert(cfg.rocks_servers, 1, protocol.."://"..path)
   return {
      root_dir = cfg.root_dir,
      rocks_dir = cfg.rocks_dir,
      deploy_bin_dir = cfg.deploy_bin_dir,
      deploy_lua_dir = cfg.deploy_lua_dir,
      deploy_lib_dir = cfg.deploy_lib_dir,
   }
end

local function restore_settings(settings)
   cfg.root_dir = settings.root_dir
   cfg.rocks_dir = settings.rocks_dir
   cfg.deploy_bin_dir = settings.deploy_bin_dir
   cfg.deploy_lua_dir = settings.deploy_lua_dir
   cfg.deploy_lib_dir = settings.deploy_lib_dir
   cfg.variables.ROCKS_TREE = settings.rocks_dir
   cfg.variables.SCRIPTS_DIR = settings.deploy_bin_dir
   table.remove(cfg.rocks_servers, 1)
end

local function prepare_sandbox(file)
   local root_dir = fs.make_temp_dir(file):gsub("/+$", "")
   cfg.root_dir = root_dir
   cfg.rocks_dir = path.rocks_dir(root_dir)
   cfg.deploy_bin_dir = path.deploy_bin_dir(root_dir)
   cfg.variables.ROCKS_TREE = cfg.rocks_dir
   cfg.variables.SCRIPTS_DIR = cfg.deploy_bin_dir
   return root_dir
end

local function validate_rockspec(lr, file)
   local ok, err, errcode = build.build_rockspec(lr, file, true)
   if not ok then
      util.printerr(err)
   end
   return ok, err, errcode
end

local function validate_src_rock(lr, file)
   local ok, err, errcode = build.build_rock(lr, file, false)
   if not ok then
      util.printerr(err)
   end
   return ok, err, errcode
end

local function validate_rock(file)
   local ok, err, errcode = install.install_binary_rock(file)
   if not ok then
      util.printerr(err)
   end
   return ok, err, errcode
end

local function validate(lr, repo, flags)
   local results = {
      ok = {}
   }
   local settings = save_settings(repo)
   local sandbox
   if flags["quick"] then
      sandbox = prepare_sandbox("luarocks_validate")
   end
   if not fs.exists(repo) then
      return nil, repo.." is not a local repository."
   end
   for _, file in pairs(fs.list_dir(repo)) do for _=1,1 do
      if file == "manifest" or file == "index.html" then
         break -- continue for
      end
      local pathname = fs.absolute_name(dir.path(repo, file))
      if not flags["quick"] then
         sandbox = prepare_sandbox(file)
      end
      local ok, err, errcode
      util.printout()
      util.printout("Verifying "..pathname)
      if file:match("%.rockspec$") then
         ok, err, errcode = validate_rockspec(lr, pathname)
      elseif file:match("%.src%.rock$") then
         ok, err, errcode = validate_src_rock(lr, pathname)
      elseif file:match("%.rock$") then
         ok, err, errcode = validate_rock(pathname)
      end
      if ok then
         table.insert(results.ok, {file=file} )
      else
         if not errcode then
            errcode = "misc"
         end
         if not results[errcode] then
            results[errcode] = {}
         end
         table.insert(results[errcode], {file=file, err=err} )
      end
      util.run_scheduled_functions()
      if not flags["quick"] then
         fs.delete(sandbox)
      end
      repeat until not fs.pop_dir()
   end end
   if flags["quick"] then
      fs.delete(sandbox)
   end
   restore_settings(settings)
   util.printout()
   util.printout("Results:")
   util.printout("--------")
   util.printout("OK: "..tostring(#results.ok))
   for _, entry in ipairs(results.ok) do
      util.printout(entry.file)
   end
   for errcode, errors in pairs(results) do
      if errcode ~= "ok" then
         util.printout()
         util.printout(errcode.." errors: "..tostring(#errors))
         for _, entry in ipairs(errors) do
            util.printout(entry.file, entry.err)
         end
      end
   end

   util.printout()
   util.printout("Summary:")
   util.printout("--------")
   local total = 0
   for errcode, errors in pairs(results) do
      util.printout(errcode..": "..tostring(#errors))
      total = total + #errors
   end
   util.printout("Total: "..total)
   return true
end

--- Driver function for "validate" command.
-- @param lr table: LuaRocks context object.
function run(lr, ...)
   cfg.assert_lr(lr)
   local flags, repo = util.parse_flags(...)
   repo = repo or cfg.rocks_dir

   util.printout("Verifying contents of "..repo)

   return validate(lr, repo, flags)
end

