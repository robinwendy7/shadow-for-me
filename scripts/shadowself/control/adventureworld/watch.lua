-- zom 的背包编号开表约定；表槽1..10对应config的板块，不自动改写表的目的地。
local A=require("shadowself/control/actions")
local C=require("shadowself/control/adventureworld/config")
local W=Class(function(self,p,sector)
    self.player=p;self.sector=sector;self.started=GetTime();self.phase="check";self.token={}
end)
function W.Bag(p)
    local inv=p.replica.inventory;local bag=inv:GetOverflowContainer()
    if bag then return bag end
    local back=inv:GetEquippedItem(EQUIPSLOTS.BACK)
    return back and back.replica and back.replica.container
end
function W.Portals(p)
    local pos=p:GetPosition();local result={}
    for _,e in ipairs(TheSim:FindEntities(pos.x,0,pos.z,10,nil,{"INLIMBO"})) do
        if e:IsValid() and e.prefab=="pocketwatch_portal_entrance" then result[e.GUID]=e end
    end
    return result
end
function W:Cancel()
    self.token=nil
    local inv=self.player.replica.inventory;local active=inv:GetActiveItem()
    if self.own_gem and active and active.prefab=="purplegem" then inv:ReturnActiveItem() end
end
function W:Tick(move)
    local p=self.player;local now=GetTime();local pc=p.components.playercontroller;local inv=p.replica.inventory
    if not self.token then return "failed","开表已取消。" end
    if now-self.started>90 then return "failed","等待裂隙表超时。" end
    if self.phase=="portal" or self.phase=="jump" then
        if self.phase=="jump" and not pc:IsBusy() and p:GetPosition():DistSq(self.origin)>12^2 then
            return "done" -- 只有实际位移并结束忙碌才确认过洞，不以发出请求代替。
        end
        if now-self.cast_at>C.portal_timeout then return "failed","没有确认穿过本次裂隙表入口。" end
        if pc:IsBusy() then return "running" end
        if not self.portal then
            for id,e in pairs(W.Portals(p)) do if not self.before[id] then self.portal=e;break end end
        end
        if self.portal and self.portal:IsValid() then
            if p:GetDistanceSqToInst(self.portal)>4 then move(self.portal:GetPosition())
            elseif now>=(self.next_jump or 0) then
                local token=self.token
                if A.Scene(p,self.portal,ACTIONS.JUMPIN,function() return self.token==token end) then self.phase="jump" end
                self.next_jump=now+1.5
            end
        end
        return "running"
    end
    if pc:IsBusy() then return "running" end
    local bag=W.Bag(p);local item=bag and bag:GetItemInSlot(self.sector)
    if not item or item.prefab~="pocketwatch_portal" and item.prefab~="pocketwatch_recall" then
        return "failed","背包第"..self.sector.."格需要放对应板块的裂隙表或已标记溯源表。"
    end
    if item.prefab=="pocketwatch_recall" then
        if item:HasTag("recall_unmarked") then return "failed","这块溯源表还没有记录目的地。" end
        if self.phase=="converted" then
            if now-self.changed>8 then return "failed","紫宝石转表未得到服务器确认。" end
            return "running"
        end
        local active=inv:GetActiveItem()
        if active and (active.prefab~="purplegem" or not self.own_gem) then return "failed","鼠标上有玩家物品，暂停自动开表。" end
        if not active then
            if self.phase=="gem" then
                if now-self.changed>5 then return "failed","未确认拿到紫宝石。" end
                return "running"
            end
            local holder,slot
            for _,container in ipairs({inv,bag}) do
                for i=1,container:GetNumSlots() do local e=container:GetItemInSlot(i)
                    if e and e.prefab=="purplegem" then holder,slot=container,i;break end end
                if holder then break end
            end
            if not holder then return "failed","没有紫宝石，无法把溯源表转为裂隙表。" end
            if holder==inv then
                if not inv.classified then return "failed","当前无法从物品栏取出紫宝石。" end
                inv.classified:TakeActiveItemFromCountOfSlot(slot,1)
            else holder:TakeActiveItemFromCountOfSlot(slot,1) end
            self.phase="gem";self.own_gem=true;self.changed=now;return "running"
        end
        if inv.classified and inv.classified._busy then return "running" end
        local action=pc:GetItemUseAction(active,item)
        if not action or action.action~=ACTIONS.GIVE then
            if now-self.changed>5 then return "failed","当前无法将紫宝石交给这块表。" end
            return "running"
        end
        inv:ControllerUseItemOnItemFromInvTile(item,active)
        self.phase="converted";self.changed=now;return "running"
    end
    if inv:GetActiveItem() then return "failed","请先放回鼠标上的物品。" end
    if not item:HasTag("pocketwatch_inactive") then return "running" end -- 冷却时等，不连发。
    self.before=W.Portals(p);self.origin=p:GetPosition()
    inv:UseItemFromInvTile(item);self.cast_at=now;self.phase="portal";return "running"
end
return W
