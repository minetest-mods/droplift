
--[[

Copyright (C) 2016 Aftermoth, Zolan Davis

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU Lesser General Public License as published
by the Free Software Foundation; either version 2.1 of the License,
or (at your option) version 3 of the License.

http://www.gnu.org/licenses/lgpl-2.1.html


--]]


local function in_walkable(p)
	local n=minetest.get_node_or_nil(p)
	return n and minetest.registered_nodes[n.name].walkable
end

-- Update drop's physics and flags.
local function disentomb(obj)
	local p = obj:getpos()
	if p then
		local ent = obj:get_luaentity()

		if in_walkable(p) then
			local brace = math.floor(p.y) + 0.800001
			if ent.is_entombed then
				obj:setpos({x = p.x, y = brace + 1, z = p.z})
				-- suppress bouncing
				if not in_walkable(obj:getpos()) then
					ent.is_entombed = false
				end
			else
				obj:setpos({x = p.x, y = brace, z = p.z})
				ent.is_entombed = true
			end

			if ent.is_entombed then
				minetest.after(1.0, disentomb, obj)
			end
		else
			ent.is_entombed = false
		end
	end
end


-- Properties set by on_activate are not accessible until it returns
-- so this function polls until they are before continuing.
local function wait_itemstring(ent, c)
	if ent.itemstring == "" then
		if c < 10 then
			minetest.after(0.1, wait_itemstring, ent, c + 1)  -- 2 ticks
		end
		return
	end

	local obj = ent.object
	disentomb(obj)

	-- stabilise entombed spawns
	if in_walkable(obj:getpos()) then
		obj:setvelocity({x = 0, y = 0, z = 0})
		obj:setacceleration({x = 0,y = 0, z = 0})
	end
end


local function append_to_core_defns()
	local dropentity=minetest.registered_entities["__builtin:item"]

	dropentity.is_entombed = false

	-- Update drops when reloaded or spawned to maintain consistent behaviour.
	local on_activate_copy = dropentity.on_activate
	dropentity.on_activate = function(ent, staticdata, dtime_s)
		local r = {on_activate_copy(ent, staticdata, dtime_s)}
		wait_itemstring(ent,0)
		return unpack(r)
	end

	-- Update drops inside newly placed (including fallen) nodes.
	local add_node_copy = minetest.add_node
	minetest.add_node = function(pos,node)
		local r = {add_node_copy(pos, node)}

		local a = minetest.get_objects_inside_radius(pos, 0.87)  -- Radius must include cube corners.
		for _,obj in ipairs(a) do
			local ent = obj:get_luaentity()
			if ent and ent.name == "__builtin:item" then
				disentomb(obj)
			end
		end

		return unpack(r)
	end
end


append_to_core_defns()

