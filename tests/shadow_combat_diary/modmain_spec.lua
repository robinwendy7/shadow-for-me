-- Simulate the ordinary client mod loader and HUD widget integration.
local G={};local periodic={};local events={};local buttons={};local clicked={}
G.TheNet={IsDedicated=function() return false end}
G.TheWorld={DoPeriodicTask=function(_,interval,fn) periodic[#periodic+1]=fn;assert(interval==.25) end,
    ListenForEvent=function(_,name,fn) events[name]=fn end}
local recorder={interval=.25,enabled=true,deaths=0,Safe=function(self,fn,...) return fn(self,...) end,
    Tick=function() clicked.tick=true end,Unbind=function(_,reason) clicked.reason=reason end,
    Toggle=function() clicked.toggle=true end,Export=function() clicked.export=true end}
local screen={AddChild=function(_,b) buttons[#buttons+1]=b;return b end,
    inst={DoPeriodicTask=function(_,interval,fn) assert(interval==.5);clicked.refresh=fn end}}
local function button(name)
    return {name=name,SetPosition=function() end,SetTextSize=function() end,
        SetText=function(self,t) self.text=t end,SetOnClick=function(self,fn) self.onclick=fn end}
end
local initialized,hud_callback
local env={GLOBAL=G,GetModConfigData=function() end,
    AddSimPostInit=function(fn) initialized=fn end,
    AddClassPostConstruct=function(path,fn) assert(path=='widgets/controls');hud_callback=fn end,
    require=function(name)
        if name=='scd_recorder' then return {New=function() return recorder end} end
        assert(name=='widgets/textbutton');return button
    end}
setmetatable(env,{__index=_G})
local fn=assert(loadstring(modmain_source));setfenv(fn,env);fn()
assert(G.SHADOW_COMBAT_DIARY==recorder)
initialized();periodic[1]();assert(clicked.tick)
hud_callback(screen);assert(#buttons==2)
buttons[1].onclick();buttons[2].onclick();clicked.refresh();events.onremove()
assert(clicked.toggle and clicked.export and clicked.reason=='world_removed' and buttons[1].text:find('记录中',1,true))
G.TheNet.IsDedicated=function() return true end;initialized=nil;hud_callback=nil;fn()
assert(not initialized and not hud_callback,'dedicated servers must receive no hooks')
print('PASS client mod startup, HUD actions, world cleanup and dedicated-server exclusion')
