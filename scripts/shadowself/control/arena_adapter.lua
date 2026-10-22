-- 使用服务器模组自身的客户端协议封装，保留请求ID、版本检查、限流和拒绝响应。
local Adapter=Class(function(self,player)
 self.player=player
 local ok,L=pcall(require,"astra/ui/lobby_client")
 local good,H=pcall(require,"astra/ui/mode_hud_client")
 if not ok or not good then self.error="当前服务器没有可用的ASTRA角斗场客户端协议。";return end
 self.lobby=L.New(player);self.hud=H.New(player)
 self.settlement=H.New(player,"settlement_hud",require("astra/net/settlement_hud_state"))
end)
function Adapter:Snapshot()
 if self.error then return nil,self.error end
 self.lobby:Refresh();self.hud:Refresh();self.settlement:Refresh()
 if not self.lobby:IsAvailable() then return nil,"正在等待ASTRA大厅状态同步。" end
 local state=self.lobby:GetState();local model=self.hud:GetModel();local id,generation,kind=self.hud:GetTarget()
 local wave,route
 for _,row in ipairs(model and model.rows or {}) do
  if row.id=="wave" then wave=tonumber((row.value or ""):match("^(%d+)")) end
  if row.id=="route" then route=({["普通线"]="default",["暗影线"]="shadow",["天体线"]="lunar"})[row.value] end
 end
 local settlement=self.settlement:GetModel()
 return {state=state,model=model,instance=id,generation=generation,kind=kind,wave=wave,route=route,
  arena=model and model.visible~=false and (model.title or ""):find("角斗场",1,true)~=nil,
  settlement=settlement and settlement.visible~=false and settlement.mode_id=="ARENA" and settlement or nil}
end
function Adapter:SoloFields(state)
 local party=state.party
 if party and (#(party.members or {})>1 or party.leader_userid~=self.player.userid) then
  return nil,"单人循环不能接管当前多人队伍，请先自行退出队伍。"
 end
 return {mode_id="ARENA",mode_version=1,variant_id="ARENA_CLASSIC_SOLO",party_id=party and party.party_id,party_revision=party and party.revision}
end
function Adapter:Send(action,fields)
 local now=GetTime()
 if now<(self.next_send or 0) or self.lobby:IsActionPending(action) then return false end
 local ok,id=self.lobby:Send(action,fields)
 if ok then self.next_send=now+.8;self.last_request=id end
 return ok,id
end
function Adapter:Prepare(snapshot)
 local s=snapshot.state;local fields,why=self:SoloFields(s)
 if not fields then return "failed",why end
 local reply=self.lobby:GetLastResponse()
 if reply and reply.request_id==self.last_request and reply.ok==false then
  self.rejections=(self.rejections or 0)+1;self.last_request=nil
  if self.rejections>=3 then return "failed","角斗场开局被服务器拒绝："..tostring(reply.error_code or reply.code or reply.reason) end
 end
 if s.match and s.match.state=="READY_CHECK" then
  if s.match.captain_userid~=self.player.userid or #(s.match.confirmations or {})>1 then return "failed","已有多人匹配，单人循环停止。" end
  local f={match_id=s.match.match_id,match_revision=s.match.revision}
  self:Send(s.match.all_ready and "MATCH_START" or "READY_CONFIRM",f);return "running"
 end
 if s.ticket or s.party and s.party.state~="OPEN" then return "running" end
 if s.lobby_state~="LOBBY" and s.lobby_state~="IDLE" then return "running" end
 local prep=s.preparation or {};local selection=prep.selection or {}
 if selection.mode_id~="ARENA" or selection.variant_id~="ARENA_CLASSIC_SOLO" then
  self:Send("LOBBY_CONFIGURE",fields)
 elseif not (prep.ready or {})[self.player.userid] then
  fields.ready=true;self:Send("LOBBY_READY",fields)
 elseif prep.all_ready==true then
  fields.direct_start=true;self:Send("QUEUE_JOIN",fields)
 end
 return "running"
end
function Adapter:Cancel()
 -- 只取消自己仍在排队的单人票，不发踢人、退队或退出副本指令。
 if not self.lobby then return end
 self.lobby:Refresh();local s=self.lobby:GetState();local p=s.party
 if s.ticket and p and p.leader_userid==self.player.userid and #(p.members or {})==1 and p.state=="QUEUED" then
  self.lobby:Send("QUEUE_CANCEL",{party_id=p.party_id,party_revision=p.revision})
 end
end
return Adapter
