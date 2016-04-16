--[[

.../mods/droplift/
	init.lua = this file

== Droplift ==

VERSION: 1.0

ABOUT:
		Droplift lifts drops out of walkable nodes. ("drop" = "__builtin:item")
		This mod adds no in-world items or blocks, just additional physics.

Droplift also prevents "entombed" drops from sinking below the floor when the game reloads, even if they are defined as non-liftable (see "Options" below).
(If you don't know what I mean: In the default game, drop something on a glass block, put another block on top, reload, and the drop will fall below the top of the glass block.)


Goals:
*	Controlled item elevation through blocks, so it can be used reliably in plans and contraptions.
*	As computationally 'nice' as possible.
*	In balance with game play and physics. Generally handy and fun, but not excessive or distracting.


Choices:
*	Moves by whole nodes only.
*	Treats all nodes as whole cubes.
*	Lifts at about 1 m/s.


Options:
*	Item types can be pre-defined as having non-liftable drops. Intended for other mods that want special item behaviours.


API:

	droplift.delay_s	Set the delay in seconds between lifts. 
	droplift.nolift		Table of item types for Droplift to ignore. Only applied when drops are spawned or the game reloads.

Individual drop properties can also be accessed:

	DROP_ENTITY.is_entombed=(boolean) whether the drop is inside a walkable node AND is liftable.
	DROP_ENTITY.is_liftable=(boolean) whether droplift affects it.

Optional 'nolift' code must be enabled for nolift and is_liftable to be defined.

There are no public functions or methods.



MODIFYING CODE:

Timers:
Two update timer implementations are included. Use only the code for one implementation throughout.
The relevant code blocks are: one in 'disentomb', and one in 'append_to_core_definitions'.
*	'after' is _presumed_ less resource intensive for slow and stoppable cycles, but allows more timing drift.
*	'on_step' keeps everything in sync, and might suit some mod packages better.
A few extra lines in 'disentomb' can also be removed to be thorough, but need not be.

Nolift:
'nolift' is an optional feature, and its code can be enabled/hidden as desired. 
There is one relevant code block in 'wait_itemstring', and individual lines marked '-- % nolift %' in three functions (7 lines = 3 if/end pairs, plus droplift.nolift).

For other modifications, droplift.variant is provided as a standard way to let other mods and developers identify which code they are dealing with.




--]]

--				** GLOBAL **


droplift={
-- core
	delay_s=1.0,		-- Seconds between calls, and also time per node travelled when applicable.

-- options
--	nolift={},  -- % nolift %
		-- Item names as keys e.g. ['mymod:mercury']=true to ignore drops of that item.


-- static metadata
	version=1.0,		-- Numeric value for simple comparisions. Higher is later.
	mtversion="0.4.10",	-- What Minetest version it was coded for.

-- custom metadata
	timer="after",		--'after' or 'on_set' implementation is used.
	variant="",			-- Label for custom code changes.
	}





--				** LOCAL **

local function in_walkable(p)
	local n=minetest.get_node_or_nil(p)
	return n and minetest.registered_nodes[n.name].walkable
end



-- Update drop's physics and flags.

local function disentomb(obj)
	local p = obj:getpos()
	if p then  --('after')
		local ent = obj:get_luaentity()
		if in_walkable(p) then
			local brace=math.floor(p.y)+0.800001
			if ent.is_entombed then
				obj:setpos({x=p.x,y=brace+1,z=p.z})
			-- suppress bouncing
				if not in_walkable(obj:getpos()) then
					ent.is_entombed=false
					ent.entombed_s=0  --('on_step')
				end
			else
				obj:setpos({x=p.x,y=brace,z=p.z})
				ent.is_entombed=true
			end

---[[	#if using 'after' timer.

			if ent.is_entombed then
				minetest.after(droplift.delay_s,disentomb,obj)
			end

--]]--#endif

		else
			ent.is_entombed=false
			ent.entombed_s=0  --('on_step')
		end
	end  --('after')
end




--				* CORE DEFINITIONS *

-- Properties set by on_activate are not accessible until it returns so this function polls until they are before continuing.
local function wait_itemstring(ent,c)
	if ent.itemstring == "" then
		if c < 10 then
			minetest.after(0.1,wait_itemstring,ent,c+1)  -- 2 ticks
		end
		return
	end

--[[	#if using % nolift %
	local i=string.find(ent.itemstring,' ')	local s
	if i then s=string.sub(ent.itemstring,1,i-1) else s=ent.itemstring end
	ent.is_liftable = not droplift.nolift[s]
--]]--#endif


	local obj = ent.object

--	if ent.is_liftable then  -- % nolift %
		disentomb(obj)
--	end  -- % nolift %


	-- stabilise entombed spawns
	if in_walkable(obj:getpos()) then
		obj:setvelocity({x=0,y=0,z=0})
		obj:setacceleration({x=0,y=0,z=0})
	end
end



local function append_to_core_defns()
	local dropentity=minetest.registered_entities["__builtin:item"]

	dropentity.is_entombed=false

-- Update drops when reloaded or spawned to maintain consistent behaviour.

	local on_activate_copy=dropentity.on_activate
	dropentity.on_activate
			=function(ent,staticdata,dtime_s)
				local r = {on_activate_copy(ent,staticdata,dtime_s)}


				wait_itemstring(ent,0)


				return unpack(r)
			end



--[[	#if using 'on_step' timer.

	dropentity.entombed_s=0


-- Timed conditional calls to disentomb.

	local on_step_copy=dropentity.on_step
	dropentity.on_step
			=function(ent,dtime_s)
				local r = {on_step_copy(ent,dtime_s)}


--				if ent.is_liftable then  -- % nolift %
					if ent.is_entombed then
						local et = ent.entombed_s+dtime_s
						local d = droplift.delay_s
						if et >= d then
							if et < d*2 then
								et = et-d   -- keeps residue to reduce drift.
							else
								et = 0      -- but rejects excess as bad dtime.
							end
							ent.entombed_s = et
							disentomb(ent.object)
						else
							ent.entombed_s=et
						end
					end
--				end  -- % nolift %


				return unpack(r)
			end

--]]--#endif



-- Update drops inside newly placed (including fallen) nodes.

	local add_node_copy=minetest.add_node
	minetest.add_node
			=function(pos,node)
				local r = {add_node_copy(pos,node)}


				local a = minetest.get_objects_inside_radius(pos,0.87)  -- Radius must include cube corners. 
				for _,obj in ipairs(a) do
					local ent = obj:get_luaentity()
					if ent and ent.name == "__builtin:item" then
--						if ent.is_liftable then  -- % nolift %
							disentomb(obj)
--						end  -- % nolift %
					end
				end


				return unpack(r)
			end
end



append_to_core_defns()




--				* END OF CODE *


--[[

LICENSE OF SOURCE CODE:

-----------------------
Copyright (C) 2016 Aftermoth, Zolan Davis

This program is free software; you can redistribute it and/or modify it under the terms of 
the GNU Lesser General Public License as published by the Free Software Foundation; 
either version 2.1 of the License, or (at your option) version 3 of the License.

http://www.gnu.org/licenses/lgpl-2.1.html
-----------------------
--]]
