--这个表记录了人物的攻击关键帧
HitAndRun.PlayerAnim = {
	['atk'] = {
		anim = function()
			return ThePlayer:HasTag("beaver") and 3 or 2
		end,
		require_attack_tag = true,
	}, --8
	slingshot = {
		anim = function(target)
			local isadmin = HitAndRun.isadmin and TUNING.Kahaithread and not HitAndRun.isserver
			local extra = HitAndRun.isserver and 1 or 0
			return (isadmin and 2 or 3) + extra
		end,
	},
	['punch'] = { anim = 7 },        --8
	['pocketwatch_atk'] = { anim = 2 }, --10
	['punch_a'] = {
		anim = 7,
		--[[cancelfn = function() --woodie_curse_epic_moose
			local skill = ThePlayer and ThePlayer.components.skilltreeupdater
			if skill and skill:IsActivated("woodie_curse_epic_moose") then
				return true
			end
		end]]
	}, --9
	--[[['moose_slam'] = {
		anim = 6,
	},]]
	['whip'] = { anim = 4 }, --11
	['toolpunch'] = {
		anim = 6,
		cancelfn = function()
			return HitAndRun.hand and HitAndRun.hand:HasTag('canshieldatk')
		end
	},
	['spearjab'] = { anim = 1 },
	['lancejab'] = { anim = 1 },
	['attack_book'] = { anim = 8 },
	['krm_hand_shoot'] = { anim = 9 },   --狂三

	['player_atk'] = { anim = 2 },       --骑牛
	['dart'] = { anim = 0 },             --吹箭
	['chop_loop'] = { anim = 0 },        --露西斧子
	--枕头
	['atk_pillow'] = { anim = 0 },       --枕头S
	['atk_pillow_pre'] = { anim = 4 or 2 }, --枕头S 6 -- laglength = 0.20, 6frame handpillow_steelwool
	atk_pillow_hold = { anim = 0 },
}
local aliases={}
for k,v in pairs(HitAndRun.PlayerAnim) do aliases['e'..k]=v end
for k,v in pairs(aliases) do HitAndRun.PlayerAnim[k]=v end
