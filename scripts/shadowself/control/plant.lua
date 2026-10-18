-- Visual states/builds are available on remote clients even when server flags are not.
local P={}
function P.Animation(e)
 return require("shadowself/native").Get().ENT_util:GetAnimation(e) or ""
end
function P.Weak(e)
 if not e or not e.HasTag or not e:HasTag("lunarthrall_plant") then return false end
 if not e:IsValid() or e:HasTag("isdead") or e:HasTag("dead") then return false end
 local name=P.Animation(e)
 return name:find("tired_",1,true)~=nil and not name:find("tired_wakeup",1,true) and not name:find("tired_pst",1,true) or false
end
function P.Middle(e)
 if not e or not e:IsValid() then return false end
 local build=e.AnimState and e.AnimState.GetBuild and e.AnimState:GetBuild()
 if build=="lunarthrall_plant_vine_big" then return true end
 return (e:HasTag("weakvine") or e:HasTag("lunarthrall_plant_segment")) and not e:HasTag("NOCLICK") or false
end
return P
