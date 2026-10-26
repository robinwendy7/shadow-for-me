-- 两次真正投币、读取新同步箭头；不从服务端 Ents 偷读远处 Boss 坐标。
local A=require("shadowself/control/actions")
local C=require("shadowself/control/adventureworld/config")
local L=Class(function(self,p,grade) self.player=p;self.grade=grade;self.phase="prepare";self.started=GetTime() end)
function L.Intersect(a,b)
    local cross=a.dx*b.dz-a.dz*b.dx
    if math.abs(cross)<C.min_cross then return end
    local x,z=b.x-a.x,b.z-a.z
    local t=(x*b.dz-z*b.dx)/cross;local u=(x*a.dz-z*a.dx)/cross
    if t<0 or u<0 then return end
    local px,pz=a.x+t*a.dx,a.z+t*a.dz
    if math.abs(px)>10000 or math.abs(pz)>10000 then return end
    return {x=px,z=pz}
end
function L.Sector(point)
    local best,distance
    for i,s in ipairs(C.sectors) do local d=(s[1]-point.x)^2+(s[2]-point.z)^2
        if not distance or d<distance then best,distance=i,d end end
    return best
end
function L:Coin()
    for _,e in ipairs(A.Items(self.player)) do
        if e.prefab=="pig_coin" then local n=e.replica.stackable and e.replica.stackable:StackSize() or 1
            if n==self.grade or self.grade==4 and n>=4 then return e end
        end
    end
end
function L.CanGrade(p,grade)
    for _,e in ipairs(A.Items(p)) do if e.prefab=="pig_coin" then
        local n=e.replica.stackable and e.replica.stackable:StackSize() or 1
        if n==grade or grade==4 and n>=4 then return true end
    end end
    local inv=p.replica.inventory;local source,empty
    for i=1,inv:GetNumSlots() do local e=inv:GetItemInSlot(i)
        if not e then empty=true
        elseif e.prefab=="pig_coin" and e.replica.stackable and e.replica.stackable:StackSize()>grade then source=true end
    end
    return source and empty and inv.classified~=nil and inv:GetActiveItem()==nil or false
end
function L:Markers()
    local pos=self.player:GetPosition();local result={}
    for _,e in ipairs(TheSim:FindEntities(pos.x,0,pos.z,7,nil,{"INLIMBO"})) do
        if e.prefab=="archive_resonator_base" and e:IsValid() then result[e.GUID]=e end
    end
    return result
end
function L:Baseline(ray)
    local p=self.player:GetPosition()
    for _,dist in ipairs(C.baselines) do for _,side in ipairs({1,-1}) do
        local x,z=p.x-ray.dz*dist*side,p.z+ray.dx*dist*side;local safe=true
        for step=1,dist do
            if not TheWorld.Map:IsPassableAtPoint(p.x-ray.dz*step*side,0,p.z+ray.dx*step*side) then safe=false;break end
        end
        if safe then return Vector3(x,0,z) end
    end end
end
function L:Tick(move)
    local p=self.player;local inv=p.replica.inventory;local now=GetTime()
    if now-self.started>75 then return "failed","猪币测向超时。" end
    if self.phase=="marker" then
        for id,e in pairs(self:Markers()) do if not self.before[id] then
            local pos=e:GetPosition();local angle=math.rad(e.Transform:GetRotation()+90)
            local ray={x=pos.x,z=pos.z,dx=math.cos(angle),dz=-math.sin(angle)}
            if not self.ray then
                self.ray=ray;self.origin=p:GetPosition();self.destination=self:Baseline(ray)
                if not self.destination then return "failed","附近没有可通行的第二测量点。" end
                self.phase="move"
            else
                self.result=L.Intersect(self.ray,ray)
                if not self.result then return "failed","两次箭头交点不可靠，等待重新测向。" end
                self.result.grade=self.grade;self.result.sector=L.Sector(self.result)
                A.Stop(p);return "done",self.result
            end
            return "running"
        end end
        if now-self.cast_at>4 then return "empty","没有观察到该等级的新方向箭头。" end
        return "running"
    elseif self.phase=="move" then
        if p:GetDistanceSqToPoint(self.destination:Get())<1 and p:GetDistanceSqToPoint(self.origin:Get())>=16 then
            A.Stop(p);self.phase="prepare";self.preparing=nil
        else move(self.destination) end
        return "running"
    end
    if p.components.playercontroller:IsBusy() then return "running" end
    if inv:GetActiveItem() then
        if self.preparing=="take" then
            local active=inv:GetActiveItem()
            if active.prefab~="pig_coin" then return "failed","拆币期间鼠标物品改变，暂停测向。" end
            inv:PutAllOfActiveItemInSlot(self.empty);self.preparing="put"
        elseif not self.preparing then return "failed","请先放回鼠标上的物品，再开启自动冒险。" end
        if now-(self.split_at or now)>5 then return "failed","猪币拆叠未确认，已暂停测向。" end
        return "running"
    end
    local coin=self:Coin()
    if not coin then
        if self.preparing then
            if now-self.split_at>5 then return "failed","猪币拆叠未确认。" end
            return "running"
        end
        local slot,empty
        for i=1,inv:GetNumSlots() do
            local e=inv:GetItemInSlot(i)
            if not e then empty=empty or i
            elseif e.prefab=="pig_coin" and e.replica.stackable and e.replica.stackable:StackSize()>self.grade then slot=i end
        end
        if not slot or not empty or not inv.classified then return "failed","需要对应枚数的猪鼻铸币，或在主物品栏留空格拆币。" end
        self.empty=empty;self.preparing="take";self.split_at=now
        inv.classified:TakeActiveItemFromCountOfSlot(slot,self.grade);return "running"
    end
    self.before=self:Markers();inv:UseItemFromInvTile(coin)
    self.cast_at=now;self.phase="marker";return "running"
end
return L
