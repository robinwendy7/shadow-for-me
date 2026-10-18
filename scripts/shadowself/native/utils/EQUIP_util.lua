local EQUIP_util = {}
local EquipSlot = require("equipslotutil")
function EQUIP_util:ToID(name)
	return EquipSlot.ToID(name)
end

function EQUIP_util:IsEquipped(item)
	return item and item.replica and item.replica.equippable and item.replica.equippable:IsEquipped()
end

function EQUIP_util:IsEquipingPrefab(prefab)
	--prefab = prefab and prefab.prefab or prefab
	for k, v in pairs(ThePlayer and ThePlayer.replica.inventory:GetEquips() or {}) do
		if v.prefab == prefab then
			return true
		end
	end
end

function EQUIP_util:CanEquip(item)
	if not item then return end
	if item:HasTag('broken') then return end
	return not self:IsRestricted(item)
end

function EQUIP_util:IsRestricted(item)
	if not item then return end
	local IsRestricted = item and item.replica.equippable ~= nil and
		item.replica.equippable:IsRestricted(ThePlayer) or nil
	return IsRestricted
end

function EQUIP_util:GetChargeTime(item)
	if not item or not item.replica then return end
	local inventoryitem = item and item.replica and item.replica._.inventoryitem
	local classify = inventoryitem and inventoryitem.classified
	if not classify then return end
	local recharge = classify and classify.recharge:value()
	local percent = (recharge or 180) / 180
	return percent
end

function EQUIP_util:GetCD(item)
	if not item or not item.replica then return end
	local inventoryitem = item and item.replica and item.replica._.inventoryitem
	local classify = inventoryitem and inventoryitem.classified
	if not classify then return end
	local cd = classify and classify.rechargetime:value()
	if cd < 0 then return end
	local percent = (classify._recharge or 180) / 180
	return cd * (1 - percent), percent
end

local cddata = {}
if TUNING.FORGE then
	for k, v in pairs(TUNING.FORGE) do
		if v and type(v) == 'table' and v.COOLDOWN then
			cddata[string.lower(k)] = v.COOLDOWN
		end
	end
end
function EQUIP_util:GetTotalCD(prefab)
	return cddata[prefab]
end

return EQUIP_util
