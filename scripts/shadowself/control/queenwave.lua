-- 原版SGbeequeen：command2 -> command1 -> command2 -> command1 -> command3第23帧结束。
local W={LEAD=1}
function W.Start(state)
 state.wave_anim=nil;state.wave_frame=nil;state.command1_count=0
end
function W.Remaining(state,queen)
 local a=queen.AnimState;local frame=a.GetCurrentAnimationFrame and a:GetCurrentAnimationFrame() or 0
 local name=a:IsCurrentAnimation("command1") and "command1" or a:IsCurrentAnimation("command2") and "command2" or a:IsCurrentAnimation("command3") and "command3" or "other"
 local changed=name~=state.wave_anim or frame+2<(state.wave_frame or 0)
 if changed and name=="command1" then state.command1_count=(state.command1_count or 0)+1 end
 state.wave_anim=name;state.wave_frame=frame
 if name=="command3" then return math.max(0,(23-frame)*(FRAMES or 1/30)),"command3" end
 if name=="command1" and (state.command1_count or 0)>=2 and a.GetCurrentAnimationLength then
  local length=a:GetCurrentAnimationLength()
  if type(length)=="number" and length>0 then
   return math.max(0,length-frame*(FRAMES or 1/30))+23*(FRAMES or 1/30),"last_command1"
  end
 end
 return nil
end
return W
