-- 4×4×8×4×4×4×4×4×4 = 524288 个真实落盘的上下文评分参数。
-- 分片按需加载；只保留当前分片，避免 require 永久缓存整个规则库。
local M = {size=8192, count=524288}
function M.Index(c,m)
    local values={c.phase_index or 0,c.season_index or 0,(c.tile or 0)%8,
        math.min(3,math.floor((c.sanity or 1)*3.999)),
        math.min(3,math.floor((c.hunger or 1)*3.999)),
        math.min(3,c.danger or 0),c.snow and 3 or c.rain and 2 or c.night and 1 or 0,
        (m.died_today and 2 or 0)+(m.ate_today and 1 or 0), math.min(3,c.company or 0)}
    local index=values[1]
    for i=2,#values do index=index*(i==3 and 8 or 4)+values[i] end
    return index
end
function M.Score(c,m)
    local index=M.Index(c,m)
    local shard=math.floor(index/M.size)
    if M.shard~=shard then
        local name=string.format("shadowself/data/context_%02d",shard)
        M.values=require(name)
        package.loaded[name]=nil
        M.shard=shard
    end
    return M.values[index%M.size+1]
end
return M
