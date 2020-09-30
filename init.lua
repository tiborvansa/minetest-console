--------------------------------------------------------
-- Minetest :: Debug Console Mod (console)
--
-- See README.txt for licensing and release notes.
-- Copyright (c) 2020, Leslie E. Krause
--
-- ./games/minetest_game/mods/console/init.lua
--------------------------------------------------------

local config = minetest.load_config( {
	default_size = "none",
	max_output_lines = 17,
	max_review_lines = 100,
	has_line_numbers = false,
} )
local player_huds = { }
local buffer = { }
local output = ""
local pipes = { }
local log_file

local unsafe_funcs = {
	["pairs"] = true,
	["ipairs"] = true,
	["next"] = true,
	["tonumber"] = true,
	["tostring"] = true,
	["printf"] = true,
	["assert"] = true,
	["error"] = true,
}

----------------

local gsub = string.gsub
local join = table.join
local max = math.max
local sprintf = string.format
local insert = table.insert

function printf( str, ... )
	if type( str ) == "table" then
		str = join( str, " ", function ( i, v )
			return tostring( v )
		end, true )
	elseif type( str ) ~= "string" then
		str = tostring( str )
	end
	if #{ ... } > 0 then
		str = sprintf( str, ... )
	end

	gsub( str .. "\n", "(.-)\n", function ( line )
		insert( buffer, line )
	end )

	output = ""

	for i = max( 1, #buffer - config.max_output_lines + 1 ), #buffer do
		if config.has_line_numbers then
			output = output .. sprintf( "%03d: %s\n", i, buffer[ i ], "\n" )
		else
			output = output .. buffer[ i ] .. "\n"
		end
	end

	for name, data in pairs( player_huds ) do
		if data.size ~= "none" then
			data.player:hud_change( data.refs.body_text, "text", output )
		end
	end
end

----------------

local _ = nil

local function is_match( text, glob )
     -- use underscore variable to preserve captures
     _ = { string.match( text, glob ) }
     return #_ > 0
end

local function parse_id( param )
	if is_match( param, "^([a-zA-Z][a-zA-Z0-9_]+)$" ) then
		return { method = _[ 1 ] }
	elseif is_match( param, "^([a-zA-Z][a-zA-Z0-9_]+)%.([a-zA-Z][a-zA-Z0-9_]+)$" ) then
		return { parent = _[ 1 ], method = _[ 2 ] }
	end
	return nil
end

local function resize_hud( name, size )
	local data = player_huds[ name ]
	local player = data.player
	local refs = data.refs

	if size == data.size then return end

	if refs then
		player:hud_remove( refs.head_bg )
		player:hud_remove( refs.head_text )
		player:hud_remove( refs.head_icon )
		player:hud_remove( refs.body_bg )
		player:hud_remove( refs.body_text )
	end

	if size == "none" then
		refs = nil
	else
		refs = { }

		refs.body_bg = player:hud_add( {
			hud_elem_type = "image",
			text = "default_cloud.png^[colorize:#000000DD",
			position = { x = size == "full" and 0.0 or 0.6, y = 0.5 },
			scale = { x = -100, y = -50 },
			alignment = { x = 1, y = 0 },
		} )

		refs.body_text = player:hud_add( {
			hud_elem_type = "text",
			text = output,
			number = 0xFFFFFF,
			position = { x = size == "full" and 0.0 or 0.6, y = 0.25 },
			alignment = { x = 1, y = 1 },
			offset = { x = 8, y = 38 },
		} )

		refs.head_bg = player:hud_add( {
			hud_elem_type = "image",
			text = "default_cloud.png^[colorize:#222222CC",
			position = { x = size == "full" and 0.0 or 0.6, y = 0.25 },
			scale = { x = -100, y = 2 },
			alignment = { x = 1, y = 1 },
		} )

		refs.head_text = player:hud_add( {
			hud_elem_type = "text",
			text = "Debug Console",
			number = 0x999999,
			position = { x = size == "full" and 0.0 or 0.6, y = 0.25 },
			alignment = { x = 1, y = 1 },
			offset = { x = 36, y = 8 },
		} )

		refs.head_icon = player:hud_add( {
			hud_elem_type = "image",
			text = "debug.png",
			position = { x = size == "full" and 0.0 or 0.6, y = 0.25 },
			scale = { x = 1, y = 1 },
			alignment = { x = 1, y = 1 },
			offset = { x = 6, y = 4 },
		} )
	end

	data.refs = refs
	data.size = size
end

----------------

minetest.register_privilege( "debug", {
	description = "Manage and review the debugging console.",
	give_to_singleplayer = true,
} )

minetest.register_on_joinplayer( function( player )
	local pname = player:get_player_name( )

	if minetest.check_player_privs( pname, "debug" ) then
		player_huds[ pname ] = { player = player }
		resize_hud( pname, config.default_size )
	end
end )

minetest.register_on_leaveplayer( function( player )
	local pname = player:get_player_name( )

	if player_huds[ pname ] then
		player_huds[ pname ] = nil
	end
end )

----------------

minetest.register_chatcommand( "debug", {
	description = "Open the debug history viewer",
	privs = { server = true },
	func = function( name, param )
		local formspec = "size[11.0,7.8]"
			.. minetest.gui_bg
			.. minetest.gui_bg_img

		formspec = formspec .. "textarea[0.3,0.5;11.0,7.5;buffer;Debug History;"

		for i = max( 1, #buffer - config.max_review_lines + 1 ), #buffer do
			formspec = formspec .. minetest.formspec_escape( buffer[ i ] ) .. "\n"
		end

		formspec = formspec .. "]"
			.. "label[9.0,0.0;" .. os.date( "%X" ) .. "]"
			.. "button_exit[0.0,7.1;2.0,1.0;clear;Clear]"
			.. "button_exit[9.0,7.1;2.0,1.0;close;Close]"

		minetest.create_form( nil, name, formspec, function( state, player, fields )
			if fields.clear then
				buffer = { }
				output = ""

				for name, data in pairs( player_huds ) do
					if data.size ~= "none" then
						data.player:hud_change( data.refs.body_text, "text", "" )
					end
				end
			end
		end )
	end,
} )

minetest.register_chatcommand( "tail", {
	description = "Continuously follow the output stream of a plain-text log file",
	privs = { server = true },
	func = function( name, param )
		if param == "" then
			if log_file then
				log_file:close( )
				log_file = nil

				return true, "Log file closed."
			end
		else
			log_file = io.open( param, "r" )

			if not log_file then
				return false, "Failed to open log file"
			end

			log_file:seek( "end", 0 )
			return true, "Log file opened."
		end
	end
} )

minetest.register_chatcommand( "unpipe", {
	description = "Unpipe a function from the debugging console",
	privs = { server = true },
	func = function( name, param )
		if param == "" then
			for k, v in pairs( pipes ) do
				if v.class.parent then
					_G[ v.class.parent ][ v.class.method ] = v.func
				else
					_G[ v.class.method ] = v.func
				end
			end
			pipes = { }

			return true, "Removed all function pipes."

		elseif pipes[ param ] then
			local v = pipes[ param ]

			if v.class.parent then
				_G[ v.class.parent ][ v.class.method ] = v.func
			else
				_G[ v.class.method ] = v.func
			end
			pipes[ param ] = nil

			return true, "Removed function pipe."
		else

			return false, "Failed to remove function pipe."
		end
	end,
} )

minetest.register_chatcommand( "pipe", {
	description = "Pipe a function to the debugging console",
	privs = { server = true },
	func = function( name, param )
		if param == "" then
			local list = { }
			for k, v in pairs( pipes ) do
				table.insert( list, k )
			end
			table.sort( list )
			return true, "Piped Functions: " .. table.concat( list, ", " )

		elseif not unsafe_funcs[ param ] then
			local class = parse_id( param )

			if class and not pipes[ param ] then
				local func

				if not class.parent then
					func = _G[ class.method ]
				elseif _G[ class.parent ] then
					func = _G[ class.parent ][ class.method ]
				end

				if func then
					pipes[ param ] = { func = func, class = class }

					local new_func = function( ... )
						local args = { "[" .. param .. "]", ... }
						for i = 2, #args do
							args[ i ] = tostring( args[ i ] )
						end
						printf( args )
		
						return func( ... )
					end

					if class.parent then
						_G[ class.parent ][ class.method ] = new_func
					else
						_G[ class.method ] = new_func
					end

					return true, "Function pipe created."
				end
			end
		end

		return false, "Failed to create function pipe."
	end
} )

globaltimer.start( 1.0, "console:slurp_file", function ( )
	if log_file then
		local str = log_file:read( "*a" )
		if str ~= "" then
			printf( string.match( str, "(.-)\n?$" ) )  -- remove trailing newline
		end
	end
end )

globaltimer.start( 0.2, "console:resize_huds", function( )
	for name, data in pairs( player_huds ) do
		local controls = data.player:get_player_control( )

		if controls.sneak and controls.aux1 then
			if data.size == "half" then
				resize_hud( name, "full" )
			elseif data.size == "full" then
				resize_hud( name, "none" )
			else
				resize_hud( name, "half" )
			end

		end
	end
end )
