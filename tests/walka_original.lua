-- Execute the original and restored methods with identical input; no engine timing guesses.
local original=[====[do --走向和攻击函数
	local function doPredictwalk(x, z)
		SendRPCToServer(RPC.PredictWalking, x, z)
	end
	function HitAndRun:DoPredictWalk(x, z)
		doPredictwalk(x, z)
	end

	function HitAndRun:_PredictWalk(pos)
		local animpos = pos
		local x, z = animpos.x, animpos.z
		doPredictwalk(x, z)
		SendRPCToServer(RPC.LeftClick, ACTIONS.WALKTO.code, x, z)
		doPredictwalk(x, z)
	end

	--原地走位打断后摇
	function HitAndRun:PredictWalk(ppos, mpos, target)
		if HitAndRun.PC:CanLocomote() and not HitAndRun.PC.ismastersim then
			local animpos = POS_util:CalculateAimPos(ppos, mpos, 0, 0.5)
			local action = BufferedAction(HitAndRun.PC.inst, nil, ACTIONS.WALKTO, nil, animpos)
			HitAndRun.PC:DoAction(action)
		else
			if HitAndRun.isserver then
				local animpos = POS_util:CalculateAimPos(ThePlayer:GetPosition(), target:GetPosition(), 0,
					0.01)
				doPredictwalk(animpos.x, animpos.z)
				SendRPCToServer(RPC.LeftClick, ACTIONS.WALKTO.code, animpos.x, animpos.z, ThePlayer)
			else
				HitAndRun:_PredictWalk(ThePlayer:GetPosition())
				--[[local animpos = POS_util:CalculateAimPos(ThePlayer:GetPosition(), target:GetPosition(), 0,
				 0.00001)
				SendRPCToServer(, animpos.x, animpos.z)]]
			end
		end
	end

	--攻击
	function HitAndRun:CloseAndAttack(target, force_force)
		if not target or not ThePlayer then return end
		local pos = target:GetPosition()
		local noforce = true
		if force_force then
			noforce = false
		end
		if ThePlayer:HasTag("weregoose") then
			SendRPCToServer(RPC.ControllerAttackButton, target, true, noforce)
		elseif ThePlayer.components.playercontroller:CanLocomote() and not ThePlayer.components.playercontroller.ismastersim then
			local act = BufferedAction(ThePlayer.components.playercontroller.inst, target, ACTIONS.ATTACK)
			if act ~= nil then
				act.preview_cb = function()
					SendRPCToServer(RPC.LeftClick, ACTIONS.ATTACK.code, pos.x, pos.z, target, true, 10,
						nil, nil)
				end
				ThePlayer.components.playercontroller:DoAction(act)
			end
		else
			local activeitem = INV_util:GetActiveItem()
			local blowdart = HitAndRun.cannomouseatk
			if activeitem or blowdart then
				if blowdart or HitAndRun:DoubleSwitching() then
					SendRPCToServer(RPC.AttackButton, target, true, false)
				else
					SendRPCToServer(RPC.AttackButton, target, true, noforce)
				end
			else
				--SendRPCToServer(RPC.LeftClick, ACTIONS.ATTACK.code, pos.x, pos.z, target, true, 10, true)

				SendRPCToServer(RPC.LeftClick, ACTIONS.ATTACK.code, pos.x, pos.z, target, nil, 10, noforce) --连打
			end
		end
	end

	--走向某个点
	function HitAndRun:WalkTo(startpos, stoppos, walkdistance, checkrange, rangecheck_ent, trydodging)
		local pmdistance = math.sqrt((startpos.x - stoppos.x) * (startpos.x - stoppos.x) +
			(startpos.z - stoppos.z) * (startpos.z - stoppos.z))
		local dx, dz = stoppos.x - startpos.x, stoppos.z - startpos.z
		if dx == 0 and dz == 0 then dx, dz = 1, 1 end
		if pmdistance == 0 then pmdistance = 0.1 end
		local fx, fz = startpos.x + walkdistance * dx / pmdistance, startpos.z + walkdistance * dz / pmdistance
		if checkrange then
			if distsq(HitAndRun.pos.x, HitAndRun.pos.z, fx, fz) > checkrange * checkrange then
				if trydodging and rangecheck_ent then
					return HitAndRun:PredictWalk(HitAndRun.ppos, rangecheck_ent:GetPosition(), rangecheck_ent)
				else
					return HitAndRun:WalkTo(startpos, HitAndRun.pos or stoppos, math.abs(walkdistance))
				end
			end
		end
		local x, z = fx, fz
		local ActiveItem = ThePlayer.replica.inventory:GetActiveItem()
		local playercontroller = ThePlayer.components.playercontroller
		if playercontroller:CanLocomote() then
			local action = BufferedAction(playercontroller.inst, nil, ACTIONS.WALKTO, nil,
				Vector3(x, 0, z))
			playercontroller:DoAction(action)
		else
			local platform, pos_x, pos_z = playercontroller:GetPlatformRelativePosition(x, z)
			SendRPCToServer(RPC.LeftClick, ACTIONS.WALKTO.code, pos_x, pos_z, ActiveItem, nil, nil,
				nil, nil, platform, platform ~= nil)
		end
	end

	function HitAndRun:PredictWalkTo(startpos, stoppos, walkdistance, checkrange, rangecheck_ent, trydodging)
		local pmdistance = math.sqrt((startpos.x - stoppos.x) * (startpos.x - stoppos.x) +
			(startpos.z - stoppos.z) * (startpos.z - stoppos.z))
		local dx, dz = stoppos.x - startpos.x, stoppos.z - startpos.z
		if dx == 0 and dz == 0 then dx, dz = 1, 1 end
		if pmdistance == 0 then pmdistance = 0.1 end
		local fx, fz = startpos.x + walkdistance * dx / pmdistance, startpos.z + walkdistance * dz / pmdistance
		if checkrange then
			if distsq(HitAndRun.pos.x, HitAndRun.pos.z, fx, fz) > checkrange * checkrange then
				if trydodging and rangecheck_ent then
					return HitAndRun:PredictWalk(HitAndRun.ppos, rangecheck_ent:GetPosition(), rangecheck_ent)
				else
					return HitAndRun:PredictWalkTo(startpos, HitAndRun.pos or stoppos, math.abs(walkdistance))
				end
			end
		end
		local x, z = fx, fz
		HitAndRun:_PredictWalk(Vector3(x, 0, z))
	end
end]====]
local file=assert(io.open("scripts/shadowself/native/engine/HitAndRun.lua"));local source=file:read("*a");file:close()
local a=assert(source:find("do --走向和攻击函数",1,true));local z=assert(source:find("\ndo --功能性函数",a,true))
local restored=source:sub(a,z-1)
local oldClock=GetTime;local clock=0;GetTime=function() return clock end
local function run(src,locomote,distance)
 local calls={};local H={pos=Vector3(0,0,0),ppos=Vector3(distance,0,0),isserver=false}
 local foe={GetPosition=function() return H.pos end};H.ent=foe
 local pc={CanLocomote=function() return locomote end,ismastersim=false,
 GetPlatformRelativePosition=function(_,x,z) return nil,x,z end,
 DoAction=function(_,act) calls[#calls+1]={"action",act.pos.x,act.pos.z} end}
 H.PC=pc
 local player={components={playercontroller=pc},replica={inventory={GetActiveItem=function() end}},GetPosition=function() return H.ppos end}
 local env=setmetatable({HitAndRun=H,ThePlayer=player,POS_util={CalculateAimPos=function(_,p,q,angle,d)
  local dx,dz=q.x-p.x,q.z-p.z;local len=math.sqrt(dx*dx+dz*dz);if len==0 then len=1 end
  return Vector3(p.x+d*dx/len,0,p.z+d*dz/len) end},
  RPC={PredictWalking=1,LeftClick=2},ACTIONS={WALKTO={code=3}},
  BufferedAction=function(_,_,_,_,pos) return {pos=pos} end,
  distsq=function(x,z,u,v) return (x-u)^2+(z-v)^2 end,
  SendRPCToServer=function(...) calls[#calls+1]={...} end},{__index=_G})
 local f=assert(loadstring(src));setfenv(f,env);f()
 H:PredictWalkTo(H.ppos,H.pos,-.3,3,foe,true)
 clock=clock+.3 -- compare complete protocols outside the repeat window
 H:WalkTo(H.ppos,H.pos,-.3,3,foe,true)
 return calls
end
for _,locomote in ipairs({true,false}) do
 for _,d in ipairs({1,2.6,2.71,2.99,3,3.1}) do
  local expected,actual=run(original,locomote,d),run(restored,locomote,d)
  assert(#expected==#actual,"original recovery call count at reach "..d)
  for i,c in ipairs(expected) do
   for j,v in pairs(c) do assert(actual[i][j]==v,"original recovery argument "..i..":"..j.." reach "..d) end
  end
 end
end
local c=assert(io.open("scripts/shadowself/control/combat.lua")):read("*a")
assert(not c:find("shadowself_backstep",1,true),"normal attack retreat is no longer rewritten by the secondary navigation filter")
print("PASS: restored movement matches actual 3014 calls at inner/max/outside reach, both remote movement modes; no secondary rewrite")

GetTime=oldClock
