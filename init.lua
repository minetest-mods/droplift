
--[[

Copyright (C) 2016 Aftermoth, Zolan Davis

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU Lesser General Public License as published
by the Free Software Foundation; either version 2.1 of the License,
or (at your option) version 3 of the License.

http://www.gnu.org/licenses/lgpl-2.1.html


--]]


local function in_walkable(p)
	local n = minetest.get_node_or_nil(p)
	return n and minetest.registered_nodes[n.name].walkable
end


-- Update drop physics and flags.
local function disentomb(obj)
	local p = obj:getpos()
	if p then

		local ent = obj:get_luaentity()
		local w = in_walkable(p)
		local brace = math.floor(p.y) + 0.800001

		if ent.is_entombed then
			local p2 = p
			if w then
				p2 = {x = p.x, y = brace + 1, z = p.z}
				obj:setpos(p2)
			end
			ent.is_entombed = in_walkable(p2)
		else
			if w then
				obj:setpos({x = p.x, y = brace, z = p.z})
				ent.is_entombed = true
			end
		end

		if ent.is_entombed then
			obj:setvelocity({x = 0, y = 0, z = 0})
			obj:setacceleration({x = 0, y = 0, z = 0})
			minetest.after(1.0, disentomb, obj)
		end

	end
end



-- Poll until defaults are ready before continuing.
local function wait_itemstring(ent, c)
	if ent.itemstring == "" then
		if c < 10 then
			minetest.after(0.1, wait_itemstring, ent, c + 1)
		end
		return
	end

	if ent.is_entombed then
		disentomb(ent.object)
	end
end



local function append_to_core_defns()
	local dropentity=minetest.registered_entities["__builtin:item"]

	-- Ensure consistency across reloads.
	local on_activate_copy = dropentity.on_activate
	dropentity.on_activate = function(ent, staticdata, dtime_s)
		on_activate_copy(ent, staticdata, dtime_s)
		if staticdata ~= "" then
			ent.is_entombed = minetest.deserialize(staticdata).is_entombed
		end
		wait_itemstring(ent, 0)
	end

	-- Preserve state across reloads
	local get_staticdata_copy = dropentity.get_staticdata
	dropentity.get_staticdata = function(ent)
		local s = get_staticdata_copy(ent)
		if ent.is_entombed then
			local r = {}
			if s ~= "" then
				r = minetest.deserialize(s)
			end
			r.is_entombed=true
			return minetest.serialize(r)
		end
		return s
	end

	-- Update drops inside newly placed (including fallen) nodes.
	local add_node_copy = minetest.add_node
	minetest.add_node = function(pos,node)
		add_node_copy(pos, node)
		local a = minetest.get_objects_inside_radius(pos, 0.87)
		for _,obj in ipairs(a) do
			local ent = obj:get_luaentity()
			if ent and ent.name == "__builtin:item" then
				disentomb(obj)
			end
		end
	end

end



append_to_core_defns()
