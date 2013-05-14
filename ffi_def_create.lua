--  ffi_def_create.lua

print()
print(" -- ffi_def_create.lua start -- ")
print()

local arg = {...}
local util = require "lib_util"
local JSON = require "JSON"
local osname
if true then -- keep ffi valid only inside if to make ZeroBrane debugger work
	local ffi = require("ffi")
	osname = string.lower(ffi.os)
end
-- osname = "linux" -- if you want to create linux with osx

local timeUsed = util.seconds()

local openResult, openPrf
if arg[1] then
  openResult = string.lower(arg[1]) == "o"
  openPrf = string.lower(arg[1]) == "p"
end
local prfFileName = "ffi_def_create_prf.json"
local basic_types = {
	"void", "...", "double", "char",
	"short", "int", "long", "long int", "long long", 
	"unsigned", --"unsigned short int", "unsigned int", "unsigned long", "unsigned long int", "unsigned long long", 
	"__int8", "__int16", "__int32", "__int64",
	"int8_t", "int16_t", "int32_t", "int64_t", 
	"uint8_t", "uint16_t", "uint32_t", "uint64_t",
	"__int8_t", "__int16_t", "__int32_t", "__int64_t", 
	"__uint8_t", "__uint16_t", "__uint32_t", "__uint64_t",
	"intptr_t", "uintptr_t",
	"ptrdiff_t", "size_t", "wchar_t",
	"va_list", "__builtin_va_list", "__gnuc_va_list",
}
local not_found_basic_types = {}

local replace_pattern = {
	[" __asm(.-);"] = ";",
	[" __attribute__(.-);"] = ";",
	["%*__restrict "] = "*",
  ["__restrict"] = "",
  ["extern "] = "",
  ["__extension__ "] = "",
  ["__extension__"] = "",
  ["__const"] = "const",
}
local replace_pattern_param = {
}
--[[
  ["const"] = "",
	[" __asm(.-);"] = ";",
	[" __attribute__(.-);"] = ";",
	["%*__restrict "] = "*",
  ["__restrict"] = "",
  ["extern "] = "",
  ["__routine"] = "",
}]]

-- name_separator, separating chars before and after function or definition name
local name_separator = "[^_%w]" 
local c_call_patterns = {
	"%WC%.([_%w]*)",
	--"%Ws%.([_%w]*)",
	--"%Wwin32%.([_%w]*)",
}
local c_type_patterns = {
	"ffi.new%(%'(.-)%'", 
	"ffi.new%(%\"(.-)%\"", 
	"ffi.cast%(%'(.-)'",
	"ffi.cast%(%\"(.-)\"",
}
-- http://lua-users.org/wiki/StringRecipes

--[[
-- c_type_patterns test
local source ="  	local kev = ffi.new('struct kevent[1]')"
local source = source..'\n  	local kev = ffi.new("struct kevent[1]")'
local source = source..'\n  local err_c = ffi.cast("int", err)")'
	for _,patt in pairs(c_type_patterns) do
		local txt = source:match(patt)
		for params in source:gmatch(patt) do
			print(params, patt)
		end
	end
]]

local generated_start = "-- generated code start --"
local sourcefiles = {
	"lib_date_time.lua", "lib_http.lua", "lib_kqueue.lua", "lib_poll.lua",
	"lib_shared_memory.lua", "lib_signal.lua", 	"lib_socket.lua", 
	"lib_tcp.lua", "lib_thread.lua", "lib_util.lua",

	"TestAddrinfo.lua", "TestAll.lua", "TestKqueue.lua",
	"TestLinux.lua", "TestSharedMemory.lua", "TestSignal.lua",
	"TestSignal_bad.lua", "TestSocket.lua", "TestThread.lua",
}
local headerfile = "c_include/_system_/ffi_types.h"
local target_ffi_file = "ffi_def__system_.lua"
local pref = {
	["basic_types"] = basic_types,
	["name_separator"] = name_separator,
	["c_call_patterns"] = c_call_patterns,
	["c_type_patterns"] = c_type_patterns,
	["replace_pattern"] = replace_pattern,
	["replace_pattern_param"] = replace_pattern_param,
	["generated_start"] = generated_start,
	["sourcefiles"] = sourcefiles,
	["headerfile"] = headerfile,
	["target_ffi_file"] = target_ffi_file,
}

if not util.file_exists(prfFileName) then
	local jsonTxt = JSON:encode_pretty(pref)
	io.output(prfFileName)
	io.write(jsonTxt)
	io.output():close()
else
	io.input(prfFileName)
	local jsonTxt = io.read("*all")
	io.input():close()
	local pref = JSON:decode(jsonTxt)
	if pref.basic_types then basic_types = pref.basic_types end
	if pref.name_separator then name_separator = pref.name_separator end
	if pref.c_call_patterns then c_call_patterns = pref.c_call_patterns end
	if pref.c_type_patterns then c_type_patterns = pref.c_type_patterns end
	if pref.replace_pattern then replace_pattern = pref.replace_pattern end
	if pref.replace_pattern_param then replace_pattern_param = pref.replace_pattern_param end
	if pref.generated_start then generated_start = pref.generated_start end
	if pref.sourcefiles then sourcefiles = pref.sourcefiles end
	if pref.headerfile then headerfile = pref.headerfile end
	if pref.target_ffi_file then target_ffi_file = pref.target_ffi_file end
end
headerfile = headerfile:gsub("_system_", osname)
target_ffi_file = target_ffi_file:gsub("_system_", osname)
basic_types = util.table_invert(basic_types)
local type_done = {
	["struct"] = 0, -- prevent addind basic types, mark as already done
}
local type_defines = {}

if #sourcefiles < 1 then
	print("error: no input files given")
	os.exit()
end

local file,err = io.input(headerfile)
if err then
	print(headerfile.." does not exist, error: "..err)
	os.exit()
end
local header = io.read("*all")
io.input():close()
print(headerfile.." size: "..#header.." bytes")
	
-- read target ffi.cdef file
local code
if util.file_exists(target_ffi_file) then
	file = io.input(target_ffi_file)
	code = io.read("*all")
	io.input():close()
	if generated_start then
		local posStart,posEnd = code:find(generated_start)
		code = code:sub(1, posEnd+1).."\n"
	end
else
	code = ""
end
	
local function replaceLine(line)
	-- replace not-wanted parts. __asm, __attribute__, ...
	for pat,repl in pairs(replace_pattern) do
		if repl ~= "delete" then
			line = line:gsub(pat, repl)
		elseif line:find(pat) then
			line = ""
			break
		end
	end
	return line
end
			
local function validType(def)
	local s = def:find(" ")
	if s then  -- define must not contain space
		def = def:sub(1, s - 1) -- return part before space
	end
	local first_char = def:sub(1, 1)
	if first_char == "(" or first_char == "[" or first_char == "{" or first_char == "*" then
	  return ""
	end
	return def
end			
local function stringBetweenPosition(str, startpos, endpos, startstr, endstr)
	-- loop startpos backwards to startstr
	local findlen = startstr:len() - 1
	while startpos > 0 do
		local str = str:sub(startpos, startpos + findlen)
		if str == startstr then
			break
		else
			startpos = startpos - 1
		end
	end
	-- find endstr in forward direction, set endpos
	local s,e = str:find(endstr, endpos)
	if e then 
		endpos = e
	end
	return startpos, endpos
end

local function paramsAdd(params_orig, sep)
	local findpos = 1
	local params = params_orig
	while #params > 0 do
		local def
		local s,e = params:find(sep, findpos, true)
		if s then
			def = params:sub(1, s - 1)
			params = params:sub(e + 1)
		else
			def = params
			params = ""
		end
		local basetype = ""
		if def then
			
			if not def:find("static const ") then
				def = def:gsub("\n", "")
				-- replase not-wanted parts. __asm, __attribute__, ...
				for pat,repl in pairs(replace_pattern_param) do
					def = def:gsub(pat, repl)
				end
				def = def:gsub("const", "")
				def = def:gsub(" %*", " ")
				def = def:gsub("%* ", " ")
				def = def:gsub("%*", "")
				def = def:gsub("%(%)", " ")
				repeat
					--[[while def:sub(1, 1) == " " do -- remove leading spaces
						def = def:sub(2)
					end
					while def:sub(-1) == " " do -- remove trailing spaces
						def = def:sub(1, def:len() - 1)
					end]]
					def = def:match( "^%s*(.-)%s*$" ) -- http://rosettacode.org/wiki/Strip_whitespace_from_a_string/Top_and_tail#Lua
					local posStart,posEnd = def:find(name_separator)
					if posStart then
						basetype = def:sub(1, posStart - 1)
						def = def:sub(posStart)
					end
				until posStart == nil or posStart == 1 or def == ""
				if basetype ~= "" and basetype ~= "struct" then
					def = basetype
				end
				def = def:gsub("%(void %)", "")
				def = def:gsub("%(void%)", "")
				def = def:gsub("%(%)", "")
				def = def:match( "^%s*(.-)%s*$" ) -- remove leading and trailin whitespace
				def = validType(def)
				if def ~= "" and not basic_types[def] and not type_defines[def] then
					if not basic_types[basetype] then -- def is just a name
						print("    parameter type added: '"..def.."'")
						type_defines[def] = 0
					end
				end
			end
			
		end
	end
end


local not_found_calls = {}
-- main loop, go through all files
for _,sourcefile in pairs(sourcefiles) do
	local file,err = io.input(sourcefile)
	if err then
		print(sourcefile.." does not exist, error: "..err)
		os.exit()
	end
	local source = io.read("*all")
	io.input():close() 

	print()
	print("*** "..sourcefile.." size: "..#source.." bytes")
	-- Lua pattern for matching Lua multi-line comment.
	source = source:gsub("(%-%-%[(=*)%[.-%]%2%])", "") -- remove block comments
	
	-- Lua pattern for matching Lua single line comment.
	source = source:gsub("(%-%-[^\n]*)", "")-- remove single line comments
	
	for _,patt in pairs(c_type_patterns) do
		for params in source:gmatch(patt) do
			s = params:find("%[")
			if s then
				params = params:sub(1, s - 1)
			end
			paramsAdd(params, ",")
		end
	end
	
	local calls = {}
	local count = 0
	for _,patt in pairs(c_call_patterns) do
		for call in source:gmatch(patt) do
			if call ~= "" and not calls[call] then
				count = count + 1
				calls[call] = count
			end
		end
	end

	calls = util.table_invert(calls)
	table.sort(calls, function(a,b) -- case-insensitive sort
			return a:lower() < b:lower() 
		end
	)
	print(util.table_show(calls, "calls"))

	-- create not-found new definitions table "new_calls"
	local new_calls = {}
	for i=1,#calls do
		local call = calls[i]
		local pattern = name_separator..call..name_separator
		if call == "recv" then -- for trace
			call = "recv"
		end
		local posStart,posEnd = code:find(pattern)
		
		-- check if function was already defined as struct
		if posStart then
			local code_call = code:sub(posStart - 7, posEnd) -- 7 = #("struct ")
			if code_call:find("struct "..call) then
				posStart = nil -- add function
			end
		end 
		
		if not posStart then
			table.insert(new_calls, call) --code:sub(posStart, posEnd))
		end
	end
	
	print("new calls found: "..#new_calls)
	-- create missing definitions from header file
	local function_lines = {}
	local static_const_lines = {}
	for i=1,#new_calls do
		local findpos = 1
		local findcall = new_calls[i]
		if findcall:find("recv") then -- for trace
			findcall = findcall .. ""
		end
		local pattern = name_separator..findcall..name_separator --"%f[%a]"..findcall.."%f[%A]"
		local startpos,endpos = header:find(pattern, findpos)
		while startpos do
			local line_start,line_end = stringBetweenPosition(header, startpos, endpos, ";", ";")
			local pragma_pack
			if line_start then
				local line = header:sub(line_start + 1, line_end)
				
				-- skip comment lines
				repeat
					local s,e = line:find("\n//")
					if e then
						local s2,e2 = line:find("\n", e + 1)
						if s2 then
							line_start = line_start + s2 - 1
							line = header:sub(line_start + 1, line_end)
						end
					end
				until not e
				
				-- skip wrong finds
				local s,e = line:find(pattern) -- re-find after removing comments
				if not s then
					line_start = nil -- wrong -> find next
					findpos = endpos + 1  -- set next find pos
				end
				
				if line_start then
					-- function name is same struct name (osx kevent and struct kevent)
					local pos_struct = line:find("%Wstruct "..findcall.."%W")
					if pos_struct then
						local pos_call = line:find(findcall.."%W")
						if pos_call > pos_struct then
							line_start = nil -- wrong -> find next
							findpos = endpos + 1  -- set next find pos
						end
					end
				end
				
				 -- function on the right side of "=" fix (osx pthread_self)
				if line_start then
					local s,e = line:find("= "..findcall)
					if s then
						line_start = nil -- wrong -> find next
						findpos = endpos + 1  -- set next find pos
					end
				end
					
				if line_start then
					 -- pragma pack fix
					local s,e = line:find("pragma pack")
					if e then
						local s = line:find("\n", e)
						pragma_pack = header:sub(line_start + 2, line_start + s - 1)
						line_start = line_start + s - 1
						local s2,e2 = header:find("pragma pack%(%)", line_start + e)
						line_end = e2
						line = header:sub(line_start, line_end)
					end
				end
			end
					
			if line_start then
				line_start = line_start + 1 -- remove next "\n"
				local line = header:sub(line_start + 1, line_end)
				findpos = line_end + 1  -- set next find pos
				-- remove front linefeeds
				while line:sub(1, 1) == "\n" do 
					line = line:sub(2)
				end
					
				-- replace not-wanted parts. __asm, __attribute__, ...
				line = replaceLine(line)
				
				new_calls[i] = "" -- mark as used
				if line ~= "" then
					local def = header:sub(line_start + 1, startpos - 1)
					repeat
						while def:sub(-1) == " " do -- remove trailing spaces
							def = def:sub(1, def:len() - 1)
						end
						local posStart,posEnd = def:find(name_separator)
						if posStart then
							def = def:sub(posStart)
						end
					until posStart == nil or posStart == 1
						
					if pragma_pack then
						line = pragma_pack.."\n"..line
						line = line:gsub("\n", "\n\t")
						line = line:gsub("#pragma pack", "// #pragma pack")
					end
					print("  "..line)
					local static_const = line:find("static const ")
					if static_const == 1 then
						table.insert(static_const_lines, line)
					else
						table.insert(function_lines, line)
					
						def = def:gsub("const ", "")
						def = def:gsub("^%s+", "")
						def = def:gsub("\n", "")
						def = validType(def)
						
						if def ~= "" and not basic_types[def] and not type_done[def] then			
							if line:find("enum") == 1 then
								def = def..""  -- for trace
							else
								print("    type added: '"..def.."'")
								type_defines[def] = 0
							end
						end
						
						local param_delim
						local param_start, param_end = line:find("%{.-%}") -- struct params
						if param_start then
							param_delim = ";"
						else
							param_start, param_end = line:find("%(.-%)") -- function params
							param_delim = ","
						end
						if param_start then
							if line:find("enum") == 1 then
								param_delim = "" -- for trace
							else
								local params = line:sub(param_start + 1, param_end - 1)
								paramsAdd(params, param_delim)
							end
						end
					end
				end -- if line ~= "" then
				
				break -- break out of inner loop
			end
			startpos,endpos = header:find(pattern, findpos)
		end
	end
	
	-- collect not found calls
	table.insert(not_found_calls, "--- "..sourcefile.." ---")
	for i=1,#new_calls do
		if new_calls[i] ~= "" then
			table.insert(not_found_calls, new_calls[i])
		end
	end
	
	-- convert types to basic types
	local type_lines = {}
	local struct_lines = {}
	local type_lines_content = {}
	local type_not_found = {}
	local loopCount = 0
	while next(type_defines) do
		print()
		loopCount = loopCount + 1 
		print(loopCount..". convert types to basic types:")
		for type_str,_ in pairs(type_defines) do
			if type_done[type_str] then
				type_defines[type_str] = nil 
			else
				print("  '"..type_str.."'")
				
				if type_str:find("recv") then -- for trace
					type_str = type_str .. ""
				end
		
				-- find type from target ffi.cdef file
				local pattern = name_separator..type_str..name_separator
				local posStart, posEnd = code:find(pattern)
				if posStart then
					print("  previous type found: "..pattern, code:sub(posStart-20, posEnd+20))
					type_defines[type_str] = nil  -- was already in target ffi.cdef file
				else
					if type_not_found[type_str] then			
						print("    type_not_found: '"..type_str.."'")
						type_defines[type_str] = nil
						basic_types[type_str] = 0 -- add to basic types
						table.insert(not_found_basic_types, type_str)
						break
					else
						
						type_not_found[type_str] = 0
						local findpos = 1
						local startpos,endpos = header:find(pattern, findpos)
						while startpos do
							local line_start,line_end = stringBetweenPosition(header, startpos, endpos, ";", ";")
							if line_start then
								line_start = line_start + 1 -- remove next "\n"
								local line = header:sub(line_start + 1, line_end)
								
								local line_pos = line:find(type_str)
								local curly_end = line:find("}")
								if curly_end and curly_end < line_pos then
									-- find previous "typedef union" or "typedef struct", use later found
									local s,e = stringBetweenPosition(header, startpos, endpos, "typedef union", ";")
									line_start,line_end = stringBetweenPosition(header, startpos, endpos, "typedef struct", ";")
									if s > line_start then
										line_start,line_end = s,e
									end
									line = header:sub(line_start , line_end)
								else
									local curly_start = line:find("{")
									if curly_start then
										curly_start = curly_start + line_start
										local curly_end= header:find("};", curly_start)
										if curly_end then
											line_end = curly_end + 2 -- "};" is 2 chars
										end
										line = header:sub(line_start + 1, line_end)
									end
								end
							
								findpos = line_end + 1  -- set next find pos
								local line_orig = line
								line_orig = line_orig:gsub("\n", "\n\t")
								
								line = replaceLine(line) 
								line = line:gsub("\n", "")
								while line:find("  ") do -- remove double spaces
									line = line:gsub("  ", " ")
								end
								
								local posStart,posEnd
								if line:find("static const(.-)"..type_str..";") then
									posStart = nil -- part of some other static const
									-- continue and find next
								else
									posStart,posEnd = line:find(pattern)
								end
								
								-- part of another definition on the right side of statement
								if line:find("%("..type_str) then -- Linux __sighandler_t
									posStart = nil -- part of some other static const
									-- continue and find next
								end
									
								if posStart then
									local def = line:sub(1, posStart - 1)
									repeat
										while def:sub(-1) == " " do -- remove trailing spaces
											def = def:sub(1, def:len() - 1)
										end
										local posStart,posEnd = def:find(name_separator)
										if posStart then
											def = def:sub(posStart + 1)
										end
									until posStart == nil or posStart == 1
										
									def = def:match( "^%s*(.-)%s*$" ) -- remove leading and trailing whitespace
									if not type_lines_content[line] then
										type_lines_content[line] = 1
										if def:find("pragma pack(.-)struct") then
											def = ""
											if not line_orig:find("pragma pack%(%)") then
												line_orig = line_orig.."\n\t#pragma pack()"
												line_orig = line_orig:gsub("#pragma pack", "// #pragma pack")
											end
										end
										
										def = validType(def)
										if def == "" then
											type_done[type_str] = 0
										elseif not basic_types[def] and not type_done[def] then	
											print("    new type found: '"..def.."'") --, line)
											type_defines[def] = 0
										else
											type_done[type_str] = 0
										end
										
										
										-- replace not-wanted parts. __asm, __attribute__, ...
										line_orig = replaceLine(line_orig)
										--if line_orig:find("typedef ") == 1 then
											table.insert(type_lines, 1, line_orig) -- add to start
										--else
										--	table.insert(struct_lines, 1, line_orig) -- add to start
										--end
										
										local static_const = line:find("static const ")
										if static_const == 1 then
											static_const = 1
										else
											local param_start, param_end = line:find("%{.-%}")
											if param_start then
												local params = line:sub(param_start + 1, param_end - 1)
												paramsAdd(params, ";")
											end
										end
									end
																			
									type_defines[type_str] = nil --table.remove(type_defines, i)
									type_not_found[type_str] = nil
									startpos = nil -- break out of inner loop
								else
									startpos,endpos = header:find(pattern, findpos)
								end
							end
						end -- while
						
					end
				end
			end
			
		end -- for
	end -- while next(type_defines) do
	
	-- add new definitions to target ffi.cdef file 
	code = code.."\n--[[ "..sourcefile.." ]]"
	if #static_const_lines > 0 or #type_lines > 0 or #struct_lines > 0 or #function_lines > 0 then
		code = code.."\nffi.cdef[[\n\t"
		
		if #static_const_lines > 0 then
			-- code = code.."\t// defines"
			code = code..table.concat(static_const_lines, "\n\t")
			if #type_lines > 0 or #struct_lines > 0 or #function_lines > 0 then
				code = code.."\n\t\n\t" -- .."\t// types"
			end
		end
		
		if #type_lines > 0 then
			code = code..table.concat(type_lines, "\n\t")
			if #struct_lines > 0 or #function_lines > 0 then
				code = code.."\n\t\n\t" -- .."\t// methods"
			end
		end
		
		if #struct_lines > 0 then
			code = code..table.concat(struct_lines, "\n\t")
			if #function_lines > 0 then
				code = code.."\n\t\n\t" -- .."\t// methods"
			end
		end
		
		if #function_lines > 0 then
			code = code..table.concat(function_lines, "\n\t")
		end
		code = code.."\n]]\n"
	end
	
	file = io.output(target_ffi_file)
	io.write(code)
	io.output():close()
		
end
	

--local src = util.table_show(sourcefiles)
if #not_found_calls - #sourcefiles > 0 then
		-- print not found calls
		code = code.."\n\n--[[\n"..util.table_show(not_found_calls, "not found calls").."]]"
		io.output(target_ffi_file)
		io.write(code)
		io.output():close()
		print("\n\n"..util.table_show(not_found_calls, "not found calls"))
end
				
print()
print(util.table_show(not_found_basic_types, "not found basic types"))
	
timeUsed = util.seconds(timeUsed)
print()
print("created: '"..target_ffi_file.."' from "..#sourcefiles.." files in "..util.format_num(timeUsed, 3).." seconds")
print()

if openResult then
	os.execute("open "..target_ffi_file)
end
if openPrf then
	os.execute("open "..prfFileName)
end

print()
print(" -- ffi_def_create.lua end -- ")
print()

