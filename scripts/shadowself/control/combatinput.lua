local M={}
function M.Typing(player)
 if not player then return false end
 local screen=TheFrontEnd and TheFrontEnd.GetActiveScreen and TheFrontEnd:GetActiveScreen()
 if screen and screen~=player.HUD and screen.name~="ChatInputScreen" and screen.name~="PlayerHud" then return false end
 if screen and screen.name=="ChatInputScreen" then return true end
 local rt=player._shadowself
 return rt and rt.panel and rt.panel.input and rt.panel.input.editing==true or false
end
function M.Owned(player)
 local rt=player and player._shadowself;local takeover=rt and rt.takeover
 return takeover and takeover.combat and takeover.combat:Running() or false
end
function M.AllowTyping(player) return M.Typing(player) and M.Owned(player) end
return M
