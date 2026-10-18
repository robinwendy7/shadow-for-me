-- 参考 Auto Cooking 2033458869 的原生容器/按钮流程，独立状态机，不载入其线程。
local A=require("shadowself/control/actions")
local Food=require("shadowself/control/foodplan")
local Cook=Class(function(self,p,plan,report)
    self.p=p;self.plan=plan;self.report=report;self.phase="discover";self.since=GetTime();self.token={};self.opened={};self.ignored={};self.completed=0;self.collected=0;self.stores={};self.inflight={};self.last_used={}
end)
function Cook:Stage(name) self.phase=name;self.since=GetTime();self.sent=nil end
-- 原版 stewer 不同步 cooking 标签；煮制期间同步的是 container.canbeopened=false。
function Cook:IsCooking(e)
    local c=e.replica and e.replica.container
    return not e:HasTag("donecooking") and c and c.CanBeOpened and not c:CanBeOpened() or false
end
function Cook:Snapshot(c)
    local out={}
    for _,item in pairs(c:GetItems()) do
        out[item.prefab]=(out[item.prefab] or 0)+(item.replica.stackable and item.replica.stackable:StackSize() or 1)
    end
    return out
end
function Cook:IsStore(e)
    local c=e.replica and e.replica.container
    -- 当前随身背包由 inventory.GetOverflowContainer 单独计数；不动别的锅料。
    local inv=self.p.replica.inventory
    local bag=inv:GetOverflowContainer()
    return e~=self.p and c and c~=bag and not e:HasTag("stewer")
        and e.prefab~="cookpot" and e.prefab~="portablecookpot" and e.prefab~="archive_cookpot"
        and e.prefab~="portablespicer" and e.prefab~="portableblender"
        and not (c.IsReadOnlyContainer and c:IsReadOnlyContainer())
end
function Cook:Stores()
    local pos=self.p:GetPosition();local out={}
    local known={};for _,store in ipairs(self.stores) do known[store.inst]=store end
    for _,e in ipairs(TheSim:FindEntities(pos.x,pos.y,pos.z,20,nil,{"INLIMBO","burnt"})) do
        if e:IsValid() and self:IsStore(e) then
            out[#out+1]=known[e] or {inst=e,counts={}}
        end
    end
    table.sort(out,function(a,b) return self.p:GetDistanceSqToInst(a.inst)<self.p:GetDistanceSqToInst(b.inst) end)
    return out
end
-- 打开成功后给容器格子/实体同步留出时间，关闭的储物容器不能直接 GetItems。
function Cook:ReadStore(store)
    local e=store.inst
    if not e:IsValid() then store.counts={};return nil end
    if not e.replica.container:IsOpenedBy(self.p) then self.read_store=nil;store.read_ready=nil end
    if not self:Open(e) then self.read_store=nil;return false end
    if not store.read_ready then
        if self.read_store~=store then self.read_store=store;self.read_since=GetTime();return false end
        if GetTime()-self.read_since<.5 then return false end
    end
    store.counts=self:Snapshot(e.replica.container);store.inspected=true;store.read_ready=true
    return true
end
function Cook:Finish(reason)
    if self.collected>0 and self.completed==0 then return "done","已收好"..self.collected.."锅现成料理。"..reason end
    if self.completed>0 then return "done","已做好"..self.completed.."份"..self.plan.target.."。"..reason end
    return "failed",reason
end
function Cook:Pending()
    local any=false
    for e,job in pairs(self.inflight) do
        if not e:IsValid() or not e:HasTag("donecooking") and not self:IsCooking(e) and GetTime()-job.start>2 then
            self.inflight[e]=nil
        else any=true end
    end
    return any
end
function Cook:ReservedPowder()
    local n=0
    if self.plan.dish.spice then for _,job in pairs(self.inflight) do if job.product==self.plan.dish.base then n=n+1 end end end
    return n
end
function Cook:PrepareNext()
    self:CloseCookware();self.token={};self.grab=nil;self.transfer=nil;self.feed=nil;self.deposit=nil;self.destination=nil;self.read_store=nil
    self.need_powder=nil;self.powder_ingredients=nil;self.powder_before=nil;self.grind_near=nil
    self.solver=nil;self.ingredients=nil;self.required=nil;self.expected=nil;self.before_product=nil
    self.source=nil;self.started_cooking=nil;self.ignored={};self.collecting=nil;self.output_product=nil;self.output_remaining=nil;self.before_harvest=nil
    self.cooker=nil;self:Stage("discover")
end
function Cook:NoMaterials(reason)
    if self:Pending() or self:FindCooked(true) then
        self.exhausted=reason;self:CloseCookware();self:Stage("await_work");return "running"
    end
    return self:Finish(reason)
end
function Cook:RememberStarted()
    self.inflight[self.cooker]={product=self.expected,start=GetTime()}
    self.last_used[self.cooker]=GetTime()
end
function Cook:NextBatch()
    if self.collecting then self.report("已收好现成料理，继续检查其他锅。")
    else self.report("已收好第"..self.completed.."份："..self.plan.target.."，继续做下一份。") end
    self:CloseCookware();self.token={};self.grab=nil;self.transfer=nil;self.feed=nil;self.deposit=nil;self.destination=nil;self.read_store=nil
    self.need_powder=nil;self.powder_ingredients=nil;self.powder_before=nil;self.grind_near=nil
    self.solver=nil;self.ingredients=nil;self.required=nil;self.expected=nil;self.before_product=nil
    self.source=nil;self.started_cooking=nil;self.ignored={};self.collecting=nil;self.output_product=nil;self.output_remaining=nil;self.before_harvest=nil
    self:Stage("next_batch")
end
function Cook:Find(prefabs)
    local pos=self.p:GetPosition();local best,d,used
    for _,e in ipairs(TheSim:FindEntities(pos.x,pos.y,pos.z,20,nil,{"INLIMBO","burnt"})) do
        local distance=self.p:GetDistanceSqToInst(e)
        if prefabs[e.prefab] and e:IsValid() and not self.ignored[e] and not self:IsCooking(e) and not e:HasTag("donecooking")
            then
            local stamp=self.last_used[e] or 0
            if not best or stamp<used or stamp==used and distance<d then best,d,used=e,distance,stamp end
        end
    end
    return best
end
local cookware={cookpot=true,portablecookpot=true,archive_cookpot=true,portablespicer=true}
function Cook:FindCooked(busy)
    local pos=self.p:GetPosition();local best,distance
    for _,e in ipairs(TheSim:FindEntities(pos.x,pos.y,pos.z,20,nil,{"INLIMBO","burnt"})) do
        local job=self.inflight[e]
        local needs_spicer=job and self.plan.dish.spice and job.product==self.plan.dish.base
        local blocked=e:HasTag("donecooking") and needs_spicer and not self:Find({portablespicer=true})
        if cookware[e.prefab] and e:IsValid() and not blocked and (e:HasTag("donecooking") or busy and self:IsCooking(e)) then
            local d=self.p:GetDistanceSqToInst(e)
            if not distance or d<distance then best,distance=e,d end
        end
    end
    return best
end
function Cook:InventoryCounts()
    local counts={}
    for _,source in ipairs(self:Sources()) do for _,item in pairs(source:GetItems()) do
        counts[item.prefab]=(counts[item.prefab] or 0)+(item.replica.stackable and item.replica.stackable:StackSize() or 1)
    end end
    return counts
end
function Cook:BeginHarvest(e,expected,collecting)
    local job=self.inflight[e]
    if job then expected=job.product;collecting=false end
    self.cooker=e;self.expected=expected;self.collecting=collecting
    if expected==self.plan.dish.base and self.plan.dish.spice then self.spicer=self:Find({portablespicer=true}) end
    self.before_harvest=self:InventoryCounts();self:Stage("harvest")
end
function Cook:ReceivedFood()
    local counts=self:InventoryCounts()
    if self.expected then
        local n=(counts[self.expected] or 0)-(self.before_harvest[self.expected] or 0)
        if n>0 then return self.expected,n end
    else
        -- 已经做好的锅不能从纯客户端读取服务器stewer.product，收菜后比对料理增量。
        local recipes=require("cooking").recipes[self.cooker.prefab] or {}
        local product,amount
        for prefab,n in pairs(counts) do
            local delta=n-(self.before_harvest[prefab] or 0)
            if delta>0 and recipes[prefab] then
                if product then return nil end -- 同时有多种新料理时不猜是哪一道。
                product,amount=prefab,delta
            end
        end
        return product,amount
    end
end
function Cook:Near(e)
    if not e or not e:IsValid() then return false end
    if self.p:GetDistanceSqToInst(e)<=6.25 then return true end
    if GetTime()-(self.moved or -100)>.8 then A.Move(self.p,e:GetPosition());self.moved=GetTime() end
    return false
end
function Cook:Open(e)
    if not e or not e:IsValid() then return false end
    local c=e.replica and e.replica.container
    if not c then return false end
    -- 已打开的容器由原版三码自动关闭规则管理，不再强制走近/重开。
    if c:IsOpenedBy(self.p) then return true end
    for _,store in ipairs(self.stores) do if store.inst==e then store.read_ready=nil end end
    if not self:Near(e) then return false end
    if GetTime()-(self.sent or -100)>1 then
        local token=self.token
        if A.Scene(self.p,e,ACTIONS.RUMMAGE,function() return self.token==token end) then self.sent=GetTime();self.opened[e]=true end
    end
    return false
end
-- 批次切换只收起厨具，食材箱保持打开；停止接管才清理本流程打开的箱子。
function Cook:CloseCookware()
    for e in pairs(self.opened) do
        if e:IsValid() and not self:IsStore(e) and e.replica.container:IsOpenedBy(self.p) then e.replica.container:Close() end
    end
end
function Cook:Close()
    for e in pairs(self.opened) do
        if e:IsValid() and e.replica.container:IsOpenedBy(self.p) then e.replica.container:Close() end
    end
    self.opened={}
end
function Cook:Sources()
    local inv=self.p.replica.inventory;local out={inv};local bag=inv:GetOverflowContainer()
    if bag then out[#out+1]=bag end

    return out
end
function Cook:Counts()
    local counts={}
    for _,c in ipairs(self:Sources()) do for _,e in pairs(c:GetItems()) do counts[e.prefab]=(counts[e.prefab] or 0)+(e.replica.stackable and e.replica.stackable:StackSize() or 1) end end
    for _,store in ipairs(self.stores) do
        if store.inst:IsValid() then for key,n in pairs(store.counts) do counts[key]=(counts[key] or 0)+n end end
    end
    if self.plan.dish.spice then
        local spice=self.plan.dish.spice;counts[spice]=math.max(0,(counts[spice] or 0)-self:ReservedPowder())
    end
    return counts
end
function Cook:Grab(prefab,amount)
    if self.grab then
        local g=self.grab
        if A.Count(self.p,g.prefab)>g.before then
            self.grab=nil;self.since=GetTime()
            if g.store.inst:IsValid() and g.store.inst.replica.container:IsOpenedBy(self.p) then
                g.store.counts=self:Snapshot(g.store.inst.replica.container)
            else g.store.counts[g.prefab]=math.max(0,(g.store.counts[g.prefab] or 0)-(g.amount or 1)) end
        elseif GetTime()-g.time>8 then return nil,"取料没有同步，可能背包已满或储物容器被关闭。"
        else return false end
    end
    local before=A.Count(self.p,prefab)
    if before>=amount then return true end
    local source=self.source
    if not source or not source.inst:IsValid() or (source.counts[prefab] or 0)<1 then
        source=nil
        for _,store in ipairs(self.stores) do
            if store.inst:IsValid() and (store.counts[prefab] or 0)>0 then source=store;break end
        end
        if source~=self.source then self:CloseCookware();self.read_store=nil end
        self.source=source
    end
    if not source then return nil,"附近已检查的储物容器和背包缺少食材："..(STRINGS.NAMES[prefab:upper()] or prefab) end
    local ready=self:ReadStore(source)
    if not ready then return false end
    for slot,item in pairs(source.inst.replica.container:GetItems()) do
        if item.prefab==prefab then
            local amount=math.min(amount-before,item.replica.stackable and item.replica.stackable:StackSize() or 1)
            source.inst.replica.container:MoveItemFromCountOfSlot(slot,self.p,amount)
            self.last_source=source
            self.grab={prefab=prefab,before=before,time=GetTime(),store=source,amount=amount};return false
        end
    end
    -- 其他玩家取走或食材变质后，更新快照再尝试下一台储物容器。
    source.counts[prefab]=nil;self.source=nil;self.read_store=nil;return false
end
-- 食材箱和锅在原版可同时打开的范围内时，直接箱子 -> 锅。
-- 太远或容器类型互斥时，一次取足本锅该食材，再正常走回锅边。
function Cook:FeedStorage(target,key,amount)
    local f=self.feed
    if not f then
        local store
        for _,v in ipairs(self.stores) do
            if v.inst:IsValid() and (v.counts[key] or 0)>0 then
                if not store or v.inst.replica.container:IsOpenedBy(self.p) then store=v end
                if v.inst.replica.container:IsOpenedBy(self.p) then break end
            end
        end
        if not store then return nil,"食材数量变了，缺少："..key end
        local a,b=store.inst:GetPosition(),target:GetPosition()
        local dx,dz=a.x-b.x,a.z-b.z
        f={store=store,key=key,amount=amount,target=target,
            direct=dx*dx+dz*dz<=25,mid={x=(a.x+b.x)/2,y=a.y,z=(a.z+b.z)/2}}
        self.feed=f
    end
    if not f.direct then
        local ready,why=self:Grab(f.key,f.amount)
        if ready then self.feed=nil end
        return ready,why
    end
    local pos=self.p:GetPosition();local dx,dz=pos.x-f.mid.x,pos.z-f.mid.z
    if dx*dx+dz*dz>.16 and (self.p:GetDistanceSqToInst(target)>6.25 or self.p:GetDistanceSqToInst(f.store.inst)>6.25) then
        if GetTime()-(self.moved or -100)>.8 then A.Move(self.p,Vector3(f.mid.x,f.mid.y,f.mid.z));self.moved=GetTime() end
        return false
    end
    if not f.read then
        if not self:ReadStore(f.store) then return false end
        if (f.store.counts[f.key] or 0)==0 then self.feed=nil;return false end
        f.read=true;self.sent=nil
    end
    if not self:Open(target) then return false end
    local source=f.store.inst.replica.container
    if not source:IsOpenedBy(self.p) then
        -- 原版同类型容器会互相关闭；不反复争抢打开，改为背包中转。
        f.direct=false;self.read_store=nil;return false
    end
    if (self:Snapshot(source)[f.key] or 0)==0 then
        f.store.counts[f.key]=nil;self.feed=nil;return false
    end
    self.last_source=f.store;self.feed=nil;return true
end
-- 先按槽位库存预留，再一次提交本锅所有当前可取的食材；等待整批同步，绝不逐帧重发。
function Cook:BuildBatch(target,requirements,existing)
    local sources={}
    for _,c in ipairs(self:Sources()) do sources[#sources+1]={source=c,inst=c.inst,inventory=c==self.p.replica.inventory} end
    for _,store in ipairs(self.stores) do
        local c=store.inst:IsValid() and store.inst.replica.container
        if c and c:IsOpenedBy(self.p) then
            store.counts=self:Snapshot(c)
            sources[#sources+1]={source=c,inst=store.inst,store=store}
        end
    end
    local steps,expected,changes={}, {},{}
    local all=true
    for key,n in pairs(requirements) do
        local need=n-(existing[key] or 0);expected[key]=existing[key] or 0
        for _,entry in ipairs(sources) do
            if need<=0 then break end
            for slot,item in pairs(entry.source:GetItems()) do
                if item.prefab==key then
                    local take=math.min(need,item.replica.stackable and item.replica.stackable:StackSize() or 1)
                    for _=1,take do
                        steps[#steps+1]={source=entry.source,inst=entry.inst,inventory=entry.inventory,slot=slot}
                    end
                    if entry.store then
                        local v=changes[entry.store] or {};changes[entry.store]=v
                        v[key]=(v[key] or 0)+take;self.last_source=entry.store
                    end
                    need=need-take;expected[key]=expected[key]+take
                end
                if need<=0 then break end
            end
        end
        if need>0 then all=false end
    end
    return steps,expected,changes,all
end
function Cook:ConfirmBatch()
    local batch=self.transfer
    if not batch then return end
    for store,used in pairs(batch.stores) do
        for key,n in pairs(used) do store.counts[key]=math.max(0,(store.counts[key] or 0)-n) end
    end
    self.transfer=nil;self.since=GetTime()
end
function Cook:Fill(target,requirements,product)
    if self.feed then
        local ready,why=self:FeedStorage(target)
        if ready==nil then return nil,why end
        if not ready then return false end
    end
    local c=target.replica.container
    if not self:Open(target) then return false end
    local existing=self:Snapshot(c)
    for key,n in pairs(existing) do if n>(requirements[key] or 0) then return nil,"锅中内容已改变，停止自动加料。" end end
    if self.transfer then
        local batch=self.transfer;local confirmed=true
        for key,n in pairs(batch.expected) do if (existing[key] or 0)<n then confirmed=false;break end end
        if confirmed then self:ConfirmBatch()
        elseif GetTime()-batch.time>8 then return nil,"批量入锅没有全部确认，停止重复发送；食材保留在当前容器中。"
        else return false end
    end
    local complete=true
    for key,n in pairs(requirements) do if (existing[key] or 0)<n then complete=false;break end end
    if complete then return true end
    local steps,expected,stores,all=self:BuildBatch(target,requirements,existing)
    if #steps>0 then
        local token=self.token
        if not A.TransferBatch(self.p,target,steps,function() return self.token==token end) then return false end
        self.transfer={expected=expected,stores=stores,time=GetTime()}
        -- 与203相同，完整一锅时紧接着提交原版按钮，不等四次往返。
        return product and all and "submitted" or false
    end
    for key,n in pairs(requirements) do
        if (existing[key] or 0)<n then
            local ready,why=self:FeedStorage(target,key,n-(existing[key] or 0))
            if ready==nil then return nil,why end
            if ready then return self:Fill(target,requirements,product) end
            return false
        end
    end
    return true
end
function Cook:StartPot(target,requirements,product)
    local filled,why=self:Fill(target,requirements,product)
    if filled==nil then return "failed",why end
    if not filled then return "running" end
    local c=target.replica.container;local button=c.widget and c.widget.buttoninfo
    if not button or not button.fn or filled~="submitted" and button.validfn and not button.validfn(target) then return "failed","这个厨具没有可用的烹饪按钮。" end
    self.before_product=A.Count(self.p,product);self.expected=product
    button.fn(target,self.p);self.cook_requirements=requirements;self.last_button=GetTime();self.cooker=target;self.started_cooking=false;self:Stage("waiting");self.report("已经下锅："..(STRINGS.NAMES[product:upper()] or product))
    return "running"
end
function Cook:Tick()
    local p=self.p;local now=GetTime();local dish=self.plan.dish
    if Food.RequiresWarly(dish) then if p.prefab~="warly" then return "failed","这道料理需要沃利和他的便携厨具。" end end
    if not self.token then return "failed","做饭已停止。" end
    if now-self.since>((self.phase=="waiting" or self.phase=="waiting_existing" or self.phase=="await_work") and 360 or 80) then return "failed","这一步没有完成："..self.phase.."。食材没有被自动丢弃。" end
    local pc=p.components.playercontroller;if pc:IsBusy() then return "running" end
    if self.phase=="next_batch" then
        -- 收菜数量和锅的可开状态可能分两次同步，不能立刻把原锅误判成不可用。
        if now-self.since<.75 then return "running" end
        local old=self.cooker
        if old and old:IsValid() and (old:HasTag("donecooking") or self:IsCooking(old)) then return "running" end
        self.cooker=nil;self:Stage("discover")
    elseif self.phase=="discover" then
        if p.replica.inventory:GetActiveItem() then return "failed","先放下鼠标上的物品，再让我做饭。" end
        self.stores=self:Stores();self.source=nil;self.read_store=nil
        for _,store in ipairs(self.stores) do
            if store.inst.replica.container:IsOpenedBy(p) then self.output_store=store;break end
        end
        local ready=self:FindCooked(false)
        if ready then self:CloseCookware();self:BeginHarvest(ready,nil,true);return "running" end
        self:Pending()
        local special=not require("cooking").recipes.cookpot[dish.base]
        self.pot=self:Find(special and {portablecookpot=true} or (p.prefab=="warly" and {cookpot=true,portablecookpot=true} or {cookpot=true}))
        if not self.pot then
            local busy=self:FindCooked(true)
            if busy then self.cooker=busy;self:Stage("waiting_existing");return "running" end
            return self:Finish("附近20码内没有空闲的合适烹饪锅。")
        end
        if dish.spice then
            self.spicer=self:Find({portablespicer=true})
            if not self.spicer then return self:NoMaterials("没有空闲的调味站。") end
        end
        self:Stage("inspect_pot")
    elseif self.phase=="inspect_pot" then
        if not self:Open(self.pot) then return "running" end
        if next(self.pot.replica.container:GetItems()) then
            self.ignored[self.pot]=true;self:CloseCookware();self:Stage("discover");return "running"
        end
        self:CloseCookware();self.scan_index=1;self.scan_since=now;self:Stage("inspect_fridges")
    elseif self.phase=="inspect_fridges" then
        local store=self.stores[self.scan_index]
        if store then
            if store.inspected then
                if store.inst.replica.container:IsOpenedBy(p) then store.counts=self:Snapshot(store.inst.replica.container) end
                self.scan_index=self.scan_index+1;self.scan_since=now;return "running"
            end
            local ready=self:ReadStore(store)
            if ready or ready==nil or now-self.scan_since>15 then
                if not ready then store.counts={} end
                self:CloseCookware();self.read_store=nil;self.scan_index=self.scan_index+1;self.scan_since=now;self.since=now
            end
            return "running"
        end
        local available=self:Counts()
        self.powder_ingredients=nil
        if dish.spice and (available[dish.spice] or 0)<1 then
            self.powder_ingredients=Food.PowderIngredients(dish.spice)
            if not self.powder_ingredients then return "failed","没有找到这种调味粉的研磨配方。" end
            for key,n in pairs(self.powder_ingredients) do
                available[key]=(available[key] or 0)-n
                if available[key]<0 then return self:NoMaterials("调味粉缺少材料："..(STRINGS.NAMES[key:upper()] or key)) end
            end
        end
        self.solver=Food.Solver(self.pot.prefab,dish.base,available);self:Stage("solve")
    elseif self.phase=="solve" then
        local ok,result=coroutine.resume(self.solver)
        if not ok then return "failed","本地配方检查失败。" end
        if coroutine.status(self.solver)~="dead" then return "running" end
        if not result then return self:NoMaterials("背包和附近已检查的储物容器里，食材不足以继续做"..self.plan.target.."。") end
        self.ingredients={};for _,key in ipairs(result) do self.ingredients[key]=(self.ingredients[key] or 0)+1 end
        self.required={}
        if self.powder_ingredients then
            self.grinder=self:Find({portableblender=true})
            if not self.grinder then return "failed","没有所需调味粉，也没有附近的研磨器。" end
            for key,n in pairs(self.powder_ingredients) do self.required[key]=n end;self.need_powder=true
        end
        self:Stage("gather")
    elseif self.phase=="gather" then
        for key,n in pairs(self.required) do
            local ready,why=self:Grab(key,n)
            if ready==nil then return "failed",why end
            if not ready then return "running" end
        end
        self:Stage(self.need_powder and "grind" or "fill")
    elseif self.phase=="grind" then
        if not self:Near(self.grinder) then self.grind_near=nil;return "running" end
        local builder=p.replica.builder;local recipe=GetValidRecipe(dish.spice)
        if not self.sent then
            self.grind_near=self.grind_near or now
            local ready,reason,code=require("shadowself/control/grinding").Check(p,recipe)
            if not ready then
                if code=="recipe" or code=="role" or now-self.grind_near>5 then return "failed",reason end
                -- 科技扫描/网络更新不是刚走到范围内就完成；靠近研磨器，避免选中更近的其他科技站。
                if code=="technology" and p:GetDistanceSqToInst(self.grinder)>2.25 and now-(self.moved or -100)>.8 then
                    A.Move(p,self.grinder:GetPosition());self.moved=now
                end
                return "running"
            end
            self.powder_before=A.Count(p,dish.spice);builder:MakeRecipeFromMenu(recipe);self.sent=now
        elseif A.Count(p,dish.spice)>self.powder_before then self.grind_near=nil;self:Stage("fill")
        elseif now-self.sent>12 then return "failed","已提交研磨请求，但未收到调味粉；请检查背包空间或地面掉落。" end
    elseif self.phase=="fill" then
        return self:StartPot(self.pot,self.ingredients,dish.base)
    elseif self.phase=="waiting_existing" or self.phase=="await_work" then
        local ready=self:FindCooked(false)
        if ready then self:BeginHarvest(ready,nil,true)
        elseif not self:Pending() and not self:FindCooked(true) then
            if self.phase=="await_work" then return self:Finish(self.exhausted or "食材不足。") end
            self:Stage("discover")
        end
    elseif self.phase=="waiting" then
        if not self.cooker:IsValid() then return "failed","厨具消失了。" end
        -- 记住煮制期间新打开的存储，避免去锅边收菜时自动关箱丢失目的地。
        for _,store in ipairs(self.stores) do
            if store.inst:IsValid() and store.inst.replica.container:IsOpenedBy(p) then self.output_store=store;break end
        end
        if self.cooker:HasTag("donecooking") then self:ConfirmBatch();self:RememberStarted();self:BeginHarvest(self.cooker,self.expected,false)
        elseif self:IsCooking(self.cooker) then
            -- 仅等待开煮确认，不站在这一口锅旁等熟；记录后立即轮转下一口空锅。
            self:ConfirmBatch();self:RememberStarted();self:PrepareNext()
        elseif now-self.since>12 and not self.started_cooking then
            return "failed","烹饪请求未被确认，厨具仍可打开；已停止。"
        elseif self.cook_requirements and now-(self.last_button or now)>.5 and self.cooker.replica.container:IsOpenedBy(p) then
            local counts=self:Snapshot(self.cooker.replica.container);local full=true
            for key,n in pairs(self.cook_requirements) do if (counts[key] or 0)~=n then full=false;break end end
            local button=self.cooker.replica.container.widget.buttoninfo
            if full and (not button.validfn or button.validfn(self.cooker)) then
                button.fn(self.cooker,p);self.last_button=now
            end
        end
    elseif self.phase=="harvest" then
        if not self.cooker:IsValid() then return self:Finish("要收菜的锅消失了。") end
        if not self.cooker:HasTag("donecooking") then
            local product,amount=self:ReceivedFood()
            if product then
                self.inflight[self.cooker]=nil
                if not self.collecting and product~=dish.product then
                    self:Stage("season");return "running"
                end
                if self.collecting then self.collected=self.collected+1 else self.completed=self.completed+amount end
                self.output_product=product;self.output_remaining=amount
                self.deposit=nil;self.destination=nil;self.read_store=nil;self:Stage("store_output");return "running"
            end
            if self.sent and now-self.sent>8 then
                return self:Finish("锅已收空，但未确认料理进入背包；请检查背包空间和锅边掉落。")
            end
            return "running"
        end
        if self:Near(self.cooker) and now-(self.sent or -100)>1 then
            local token=self.token;local target=self.cooker
            if A.HarvestCooked(p,target,function() return self.token==token and self.phase=="harvest" and self.cooker==target end) then self.sent=now end
        end
    elseif self.phase=="store_output" then
        return self:StoreOutput()
    elseif self.phase=="season" then
        if not self.spicer or not self.spicer:IsValid() then return self:Finish("调味站消失了，基础料理保留在背包。") end
        return self:StartPot(self.spicer,{[dish.base]=1,[dish.spice]=1},dish.product)
    end
    return "running"
end
-- 当前打开的普通存储优先；若开锅使其关闭，回到先前打开/取料的容器。
function Cook:OutputDestination()
    for _,store in ipairs(self:Stores()) do
        if store.inst.replica.container:IsOpenedBy(self.p) then return store end
    end
    for _,store in ipairs({self.output_store or false,self.last_source or false}) do
        if store and store.inst:IsValid() then return store end
    end
end
function Cook:StoreOutput()
    local product=self.output_product or self.plan.dish.product
    if not self.destination then
        self.destination=self:OutputDestination()
        if not self.destination then
            -- 周围没有任何存储时仍可持续使用随身材料，成品留在背包。
            self:NextBatch();return "running"
        end
    end
    local store=self.destination;local e=store.inst
    if not e:IsValid() then return self:Finish("存放容器消失了，成品留在背包。") end
    if not self:ReadStore(store) then return "running" end
    local c=e.replica.container
    if self.deposit then
        if (store.counts[product] or 0)>self.deposit.before and A.Count(self.p,product)<self.deposit.inventory then
            self.output_store=store;self.output_remaining=(self.output_remaining or 1)-1;self.deposit=nil
            if self.output_remaining<=0 then self:NextBatch() else self.since=GetTime() end
            return "running"
        elseif GetTime()-self.deposit.time>8 then
            return self:Finish("成品未确认存入容器，可能已满或不接受这道菜；停止继续烹饪。")
        end
        return "running"
    end
    for _,source in ipairs(self:Sources()) do for slot,item in pairs(source:GetItems()) do
        if item.prefab==product then
            if c.CanTakeItemInSlot and not c:CanTakeItemInSlot(item) then
                return self:Finish("当前容器不接受这道菜，成品留在背包。")
            end
            self.deposit={before=store.counts[product] or 0,inventory=A.Count(self.p,product),time=GetTime()}
            source:MoveItemFromCountOfSlot(slot,e,1);return "running"
        end
    end end
    return self:Finish("刚做好的成品已不在背包中，停止继续存放。")
end
function Cook:Pause()
    if not self.paused then self.paused=GetTime();self.token=nil end
end
function Cook:Resume()
    if self.paused then
        local elapsed=GetTime()-self.paused;self.since=self.since+elapsed
        if self.transfer then self.transfer.time=self.transfer.time+elapsed end
        if self.grab then self.grab.time=self.grab.time+elapsed end
        if self.deposit then self.deposit.time=self.deposit.time+elapsed end
        if self.scan_since then self.scan_since=self.scan_since+elapsed end
        if self.read_since then self.read_since=self.read_since+elapsed end
        if self.grind_near then self.grind_near=self.grind_near+elapsed end
        self.token={};self.paused=nil
    end
end
function Cook:Cancel() self.token=nil;self:Close() end
return Cook
