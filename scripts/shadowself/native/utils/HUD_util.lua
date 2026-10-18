local ImageButton = require("widgets/imagebutton")
local UIAnim = require "widgets/uianim"
local UIAnimButton = require "widgets/uianimbutton" --(self, bank, build, idle_anim, focus_anim, disabled_anim, down_anim, selected_anim)
local HUD_util = {
}
HUD_util.screen_w, HUD_util.screen_h = TheSim:GetScreenSize()
function HUD_util:MakeImageButton(parenthud, params)
	--{name="name",atlas="atlas",image="image",x=0,z=0,onclickfn=fn,hovertext="text"}
	params = params or {}
	params.name = params.name or "imagebutton"
	params.atlas = params.atlas or "images/button_icons.xml"
	params.image = params.image or "announcement.tex"

	parenthud[params.name] = parenthud:AddChild(ImageButton(params.atlas, params.image))
	if params.onclickfn then
		parenthud[params.name]:SetOnClick(function()
			params.onclickfn()
		end)
	end
	if params.oncontrolfn then
		local button = parenthud[params.name]
		local oldoncontrol = button.OnControl
		function button:OnControl(control, down)
			params.oncontrolfn(control, down)
			return oldoncontrol(button, control, down)
		end
	end
	parenthud[params.name]:SetPosition(params.x or 0, params.z or 0)
	parenthud[params.name]:SetScale(params.scale or 1)
	if params.tooltips then
		parenthud[params.name]:SetTooltip(params.tooltips)
	elseif params.hovertext then
		parenthud[params.name]:SetHoverText(params.hovertext)
	end
	--右键拖拽
	if params.dragable then
		HUD_util:ActivateUIDraggable(parenthud[params.name])
	end
	return parenthud[params.name]
end

function HUD_util:MakeUIAnim(parenthud, params)
	--{build="build",bank="bank",anim="anim",scale=1,x=0,y=0}
	params = params or {}
	local Anim = parenthud:AddChild(UIAnim())
	local animstate = Anim:GetAnimState()
	animstate:SetBuild(params.build or "wilson")
	animstate:SetBank(params.bank or "wilson")
	animstate:PlayAnimation(params.anim or "idle_loop", true)
	Anim:SetFacing(params.facing or FACING_DOWN)
	Anim:SetScale(params.scale or 1)
	local scale = 1 / (parenthud:GetScale().x or 1)
	Anim:SetPosition((params.x or 0) / scale, (params.y or 0) / scale)
	if params.absx then
		HUD_util:Setabspos(Anim, params.absx, params.absy)
	end
	--Anim:MoveToBack()
	return Anim
end

function HUD_util:MakeUIAnimButton(parenthud, params)
	--{build="build",bank="bank",anim="anim",scale=1,x=0,y=0}
	params = params or {}
	local Anim_button = parenthud:AddChild(UIAnimButton(params.bank or "wilson", params.build or "wilson",
		params.anim or "idle_loop",
		params.focus_anim,
		params.disabled_anim, params.down_anim,
		params.selected_anim))
	--Anim_button:SetFacing(params.facing or FACING_DOWN)
	Anim_button:SetLoop(params.anim or "idle_loop", true)
	Anim_button:SetLoop(params.focus_anim or "idle_loop", true)
	Anim_button:SetScale(params.scale or 1)
	if params.oncontrolfn then
		local root = Anim_button
		local oldcontrol = root.OnControl
		function root:OnControl(control, down)
			params.oncontrolfn(root, control, down)
			return oldcontrol(root, control, down)
		end
	end
	if params.hovertext then
		Anim_button:SetHoverText(params.hovertext)
	end
	--position
	local scale = 1 / (parenthud:GetScale().x or 1)
	Anim_button:SetPosition((params.x or 0) / scale, (params.y or 0) / scale)
	if params.absx then
		HUD_util:Setabspos(Anim_button, params.absx, params.absy)
	end
	return Anim_button
end

function HUD_util:Setabspos(hud, x, y)
	local scale = 1 / (hud.parent:GetScale().x or 1)
	local parentpos = hud.parent:GetWorldPosition()
	hud:SetPosition((x - parentpos.x) * scale, (y - parentpos.y) * scale)
end

-- 使得不是全局对齐的ui可以拖动，func_stop用来执行拖动结束位置的事件
-- 当存在UI_follow时，UI_follow为拖动的实体，但他会使得UI跟着移动
function HUD_util:ActivateUIDraggable(UI, isleft, func_stop, UI_follow)
	UI_follow = UI_follow or UI
	local pos_last = UI:GetPosition()
	local followhandler
	local function FollowMouse(ui)
		if followhandler == nil then
			local cur_pos = TheInput:GetScreenPosition()
			local scale = 1 / ui.parent:GetScale().x
			local ori_pos = pos_last
			followhandler = TheInput:AddMoveHandler(function(x, y)
				pos_last = (Vector3(x, y, 0) - cur_pos) * scale + ori_pos
				ui:SetPosition(pos_last)
			end)
		end
	end


	local _OnMouseButton = UI_follow.OnMouseButton
	UI_follow.OnMouseButton = function(ui, press, down, ...)
		local result = _OnMouseButton(ui, press, down, ...)
		if ui.focus then
			if press == (isleft == "middle" and MOUSEBUTTON_MIDDLE or isleft and MOUSEBUTTON_LEFT or MOUSEBUTTON_RIGHT) then
				if down then
					UI_follow:MoveToFront()
					pos_last = UI:GetPosition()
					return FollowMouse(UI)
				else
					if followhandler ~= nil then
						followhandler:Remove()
						followhandler = nil
					end
					UI:SetPosition(pos_last)
					if type(func_stop) == "function" then
						func_stop(pos_last)
					end
				end
			end
		end
		if followhandler ~= nil then
			followhandler:Remove()
			followhandler = nil
		end
		return result
	end
end

function HUD_util:HasScreenByName(name)
	for k, v in pairs(TheFrontEnd.screenstack) do
		if v.name == name then
			return true
		end
	end
end

return HUD_util
