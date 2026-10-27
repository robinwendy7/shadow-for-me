-- 外形来自当前AnimState；角色prefab只给原版服装算法提供角色规则，不能覆盖当前build。
local M={}
local function value(s) return type(s)=="string" and s~="" and s or nil end
function M.Read(owner)
    local a=owner.AnimState
    local build=value(a:GetBuild()) or owner.prefab
    local skin=value(a.GetSkinBuild and a:GetSkinBuild())
    local data=TheNet:GetClientTableForUser(owner.userid or "")
    local base,clothing
    if data and GetSkinsDataFromClientTableData then base,clothing=GetSkinsDataFromClientTableData(data) end
    clothing=clothing or {}
    local metadata=base and GetSkinData and GetSkinData(base)
    local mode,bank="normal_skin","wilson"
    if metadata and metadata.skins then
        for kind,source in pairs(metadata.skins) do
            if source==(skin or build) then mode=kind;break end
        end
    end
    if GetSkinModes then for _,v in ipairs(GetSkinModes(owner.prefab)) do
        if v.type==mode then bank=v.anim_bank or "wilson";break end
    end end
    for _,form in ipairs({"werebeaver","weregoose","weremoose"}) do
        if build:find(form,1,true)==1 or skin and skin:find(form,1,true)==1 then bank=form;break end
    end
    local signature=table.concat({build,skin or "",mode,bank,base or "",clothing.body or "",clothing.hand or "",clothing.legs or "",clothing.feet or ""},"|")
    return {build=build,skin=skin or build,mode=mode,bank=bank,base=base,clothing=clothing,signature=signature}
end
return M
