-- 独立真实模块测试：原生点击参数、禁锢检测、预判、补控与协程优先级。
package.loaded["shadowself/control/actions"]=nil;package.loaded["shadowself/control/maxwell"]=nil
local A=require("shadowself/control/actions")
local Maxwell=require("shadowself/control/maxwell")
local now=100;GetTime=function() return now end
local function point(x,z)
    local p={x=x,y=0,z=z};function p:DistSq(q) return (self.x-q.x)^2+(self.z-q.z)^2 end
    function p:Get() return self.x,self.y,self.z end;return p
end
Vector3=function(x,y,z) return point(x,z) end
local function entity(prefab,x,z,tags)
    local e={prefab=prefab,GUID=x*100+z,valid=true,pos=point(x,z),tags=tags or {},replica={}}
    function e:IsValid() return self.valid end;function e:HasTag(tag) return self.tags[tag] or false end
    function e:GetPosition() return self.pos end;function e:GetBasicDisplayName() return self.prefab end
    return e
end
ACTIONS.CASTAOE={id="CASTAOE",code=143}
RPC.LeftClick="bookclick"
local sent={};SendRPCToServer=function(...) sent[#sent+1]={...} end
local pc={enabled=true,busy=false,aoe=nil}
function pc:IsEnabled() return self.enabled end;function pc:IsBusy() return self.busy end
function pc:IsAOETargeting() return self.aoe~=nil end
function pc:GetActiveSpellBook() return self.aoe end;function pc:CancelAOETargeting() self.aoe=nil end
local platform={};function pc:GetPlatformRelativePosition(x,z) return platform,x+100,z+200 end
function pc:GetGroundUseAction(p,b) self.lastpoint=p;return {action=ACTIONS.CASTAOE,invobject=b} end
function pc:DoAction(act) self.host=act end
local book=entity("waxwelljournal",0,0)
local spell={selected=2,items={}}
function spell:SelectSpell(id) self.selected=id;return true end
function spell:GetSelectedSpell() return self.selected end
spell.items[4]={execute=function(b) pc.aoe=b end}
book.components={spellbook=spell}
local player=entity("waxwell",0,0)
player.components={playercontroller=pc}
local inventory={items={book},equips={}}
function inventory:GetItems() return self.items end;function inventory:GetEquips() return self.equips end
function inventory:GetOverflowContainer() return nil end;function inventory:GetActiveItem() return self.active end
player.replica.inventory=inventory
local boss=entity("deerclops",10,0,{epic=true,hostile=true})
local mob=entity("spider",4,0,{monster=true,hostile=true})
local entities={boss,mob}
TheSim={FindEntities=function(_,x,y,z,r,required,excluded)
    local result={}
    for _,e in ipairs(entities) do
        local allowed=e:GetPosition():DistSq(point(x,z))<=r*r
        for _,tag in ipairs(required or {}) do if not e:HasTag(tag) then allowed=false end end
        for _,tag in ipairs(excluded or {}) do if e:HasTag(tag) then allowed=false end end
        if allowed then result[#result+1]=e end
    end
    return result
end}
local c={player=player,h={ent=mob},bridge={allowed=function(e) return e.tags.hostile end}}
local m=Maxwell(c)
assert(m:Tick(false) and #sent==1,"Maxwell combat actually submits native spell click")
local rpc=sent[1]
assert(rpc[1]==RPC.LeftClick and rpc[2]==ACTIONS.CASTAOE.code and rpc[3]==106.5 and rpc[4]==200,"native platform-relative ground click")
assert(rpc[10]==platform and rpc[11]==true and rpc[12]==book and rpc[13]==4,"spellbook and SHADOW_PILLARS id encoded in native slots")
assert(m.pending.target==boss and not pc:IsAOETargeting(),"Boss priority and no targeting cursor leak")
now=100.2;boss.pos=point(10.5,0);m:Tick(false)
assert(m.samples[boss.GUID].vx>2 and #sent==1,"movement sampled during cast cooldown without extra requests")
local pillar=entity("shadow_pillar",10,0,{shadow_pillar=true});pillar.AnimState={IsCurrentAnimation=function() return false end}
entities={boss,pillar};now=102
assert(not m:Tick(false) and #sent==1 and m.misses[boss.GUID]==0,"existing stable pillars suppress recast and confirm control")
pillar.AnimState.IsCurrentAnimation=function(_,name) return name=="shake1" end
now=102.2;assert(m:Tick(false) and #sent==2,"shaking pillars trigger renewal")
m:Stop();assert(spell.selected==2,"stop restores owned previous spell selection")
-- 未观察到柱子连续三次之后，退回脚下但不会永久放弃。
entities={mob};local retry=Maxwell(c)
for i=1,3 do retry.pending={target=mob,time=now-2};retry:Track(nil,now);now=now+2 end
assert(retry.misses[mob.GUID]==3 and retry:Point(mob,now).x==0,"three misses fall back to player feet")
assert(retry:Tick(false) and sent[#sent][3]==100,"ordinary enemy is controlled using fallback instead of disabled")
retry:Stop()
local excluded=entity("shadow_knight",2,0,{hostile=true});entities={mob,excluded}
local blocked=Maxwell(c);now=now+2
local n=#sent;assert(not blocked:Tick(false) and #sent==n,"area exclusion prevents catching shadow chess pieces")
entities={mob};pc.busy=true
assert(not blocked:Tick(false) and #sent==n,"busy player does not submit another spell")
pc.busy=false;assert(not blocked:Tick(true) and #sent==n,"native imminent dodge has priority")
player.prefab="wilson";assert(not blocked:Tick(false) and #sent==n,"other characters do not use Maxwell ability")
player.prefab="waxwell";inventory.active=book
assert(not blocked:Tick(false) and #sent==n,"manual cursor-held item is preserved")
inventory.active=nil;pc.aoe=excluded
assert(not A.CastBook(player,book,point(0,0),4) and pc.aoe==excluded,"manual targeting mode is preserved")
pc.aoe=nil;pc.ismastersim=true
assert(A.CastBook(player,book,point(0,0),4) and pc.host.action==ACTIONS.CASTAOE and #sent==n,"host uses native DoAction rather than RPC")
pc.ismastersim=false;pc.GetGroundUseAction=function() return nil,nil end
assert(not A.CastBook(player,book,point(0,0),4) and pc.aoe==nil,"unavailable point action cleans owned targeting")
print("PASS: Maxwell native CASTAOE slots, Boss/mob control, velocity sampling, pillars renewal, miss fallback, exclusions, host and cancel")
-- 只有书时沿用控怪距离，不让原生近战入口把人带去拳击。
c.gear={Weapon=function() return nil end};c.h.ent=mob;c.enemies={mob};c.observed={}
local range_point
c.ClearApproach=function() return true end;c.Move=function(_,p) range_point=p end
local ranged=Maxwell(c)
assert(ranged:ControlOnly() and ranged:MaintainRange() and math.abs(math.sqrt(range_point:DistSq(mob:GetPosition()))-10.4)<.001,"book-only Maxwell keeps control distance")
c.gear.Weapon=function() return book end
assert(not ranged:ControlOnly(),"equipped combat weapon returns melee to native 3014")
print("PASS: book-only range and armed native combat mode")
