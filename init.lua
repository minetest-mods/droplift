	
--[[

Copyright (C) 2016 Aftermoth, Zolan Davis

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU Lesser General Public License as published
by the Free Software Foundation; either version 2.1 of the License,
or (at your option) version 3 of the License.

http://www.gnu.org/licenses/lgpl-2.1.html


--]]

droplift = {}

local function in_walkable(p)
	local n = minetest.get_node_or_nil(p)
	return n and minetest.registered_nodes[n.name].walkable
end


-- * Local escape *

-- get nearest player in range (taxicab)
local function near_player(dpos)
	local near = 8.5
	local pp, d, ppos
	for _,player in ipairs(minetest.get_connected_players()) do
		pp = player:getpos()
		pp.y = pp.y + 1
		d = math.abs(pp.x-dpos.x) + math.abs(pp.y-dpos.y) + math.abs(pp.z-dpos.z)
		if d < near then
			near = d
			ppos = pp
		end
	end
	if near < 8.5 then return ppos else return false end
end


local function usign(r)
	if r < 0 then return -1 else return 1 end
end


local function quick_escape(ent,pos)

	local bias = {x = 1, y = 1, z = 1}
	local o = {a="x", b="y", c="z"}

	local pref = near_player(pos)
	if pref then
		bias = {x = usign(pref.x - pos.x), y = usign(pref.y - pos.y), z = usign(pref.z - pos.z)}
		local mag={x=math.abs(pref.x - pos.x), y=math.abs(pref.y - pos.y), z=math.abs(pref.z - pos.z)}
		if mag.z > mag.y then
			if mag.y > mag.x then
				o={a="z",b="y",c="x"}
			elseif mag.z > mag.x then
				o={a="z",b="x",c="y"}
			else
				o={a="x",b="z",c="y"}
			end
		else
			if mag.z > mag.x then
				o={a="y",b="z",c="x"}
			elseif mag.y > mag.x then
				o={a="y",b="x",c="z"}
			end
		end
	end

	local p
	for a = pos[o.a] + bias[o.a], pos[o.a] - bias[o.a], -bias[o.a] do
		for b = pos[o.b] + bias[o.b], pos[o.b] - bias[o.b], -bias[o.b] do
			for c = pos[o.c] + bias[o.c], pos[o.c] - bias[o.c], -bias[o.c] do
				p = {[o.a]=a, [o.b]=b, [o.c]=c}
				if not in_walkable(p) then
					ent.object:setpos(p)
					return p
				end
			end
		end
	end

	return false
end


-- * Entombment physics *


local function disentomb(obj, reset)
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
		elseif w and not (reset and quick_escape(ent,p)) then
			obj:setpos({x = p.x, y = brace, z = p.z})
			ent.is_entombed = true
		end

		if ent.is_entombed then
			obj:setvelocity({x = 0, y = 0, z = 0})
			obj:setacceleration({x = 0, y = 0, z = 0})
			minetest.after(1.0, disentomb, obj, false)
		end

	end
end

function droplift.invoke(obj, entomb)
	disentomb(obj, not entomb)
end



-- * Events *


-- Poll until defaults are ready before continuing.
local function wait_itemstring(ent, c)
	if ent.itemstring == "" then
		if c < 10 then
			minetest.after(0.1, wait_itemstring, ent, c + 1)
		end
		return
	end

	disentomb(ent.object, false)
end


local function append_to_core_defns()
	local dropentity=minetest.registered_entities["__builtin:item"]

	-- Ensure consistency across reloads.
	local on_activate_copy = dropentity.on_activate
	dropentity.on_activate = function(ent, staticdata, dtime_s)
		on_activate_copy(ent, staticdata, dtime_s)
		if staticdata ~= "" then 
			if minetest.deserialize(staticdata).is_entombed then
				ent.is_entombed = true
				minetest.after(0.1, wait_itemstring, ent, 1)
			else
				ent.object:setvelocity({x = 0, y = 0, z = 0})
			end
		end
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

	-- Update drops inside newly placed nodes.
	local add_node_copy = minetest.add_node
	minetest.add_node = function(pos,node)
		add_node_copy(pos, node)
		local a = minetest.get_objects_inside_radius(pos, 0.87)
		for _,obj in ipairs(a) do
			local ent = obj:get_luaentity()
			if ent and ent.name == "__builtin:item" then
				disentomb(obj, true)
			end
		end
	end

end



append_to_core_defns()
