-- 15关补给和打法提示；实际库存取舍统一由arena_inventory按本局掉落决定。
local Data=require("shadowself/data/arena_classic")
local P={waves={
 [1]={name="基础近战",keep={"spear","armorgrass"},note="先拾矛与草甲；逐个近身反打。"},
 [2]={name="生物群战",keep={"panflute","whip","torch","armorwood"},note="海象先冰狗；滑行企鹅拉远催眠；排箫留给后段。"},
 [3]={name="发条组合",keep={"cane","tentaclespike","rainhat","cookiecutterhat"},note="手杖移动，优先近身主教/骑士，战车排最后且保留冲撞预警。"},
 [4]={name="早期Boss",keep={"footballhat","nightsword"},note="按实际Boss复用独立走位；大理石甲移速不适合赶路和追击。"},
 [5]={name="群怪与兔王",keep={"hambat","nightstick","armorsnurtleshell","staff_tornado"},note="海盗猴首轮15秒三风；沼泽首轮7秒两风打蚊子，清蚊后鱼人→青蛙→触手；兔王使用专属流程。"},
 [6]={name="特殊群怪",keep={"rainhat","slurtlehat","panflute"},note="电羊巡游15秒六风后直接近战；蝾螈/蠕虫首轮15秒三风，后续7秒一风直至清杂；蝙蝠王先解除套头，再用近战武器处理。"},
 [7]={name="鲨鱼或戍卫塔",keep={"ruins_bat","cane"},note="鲨鱼贴身侧绕并躲钻出/冰封；戍卫塔扇形侧绕。"},
 [8]={name="帝王蟹",keep={"panflute","boat_item","boat_grass_item","oar_driftwood"},note="保留船套；冰陆小蟹催眠，破冰后只输出蟹王。"},
 [9]={name="远古守护者",keep={"firestaff","icestaff","yellowamulet","armordragonfly"},note="有柱诱撞，晕眩输出；先避大跳再引触手。"},
 [10]={name="龙蝇",keep={"armorskeleton","armorruins","nightmarefuel","nightsword"},note="龙蝇全走位，倒地持续输出；骨甲留后续，不用它换血。"},
 [11]={name="路线分流",keep={"voltgoatjelly_spice_chili","wathgrithr_improvedhat","firestaff","icestaff"},note="先装备女武神头盔并确认辣冻；鱼人先杀，普通线巡游清螨后只打进食蠕虫。"},
 [12]={name="蜂后或裂隙",keep={"panflute","icestaff","firestaff","icestaff3","sword_lunarplant","voidcloth_scythe","houndstooth_blowpipe"},note="蜂后沿用冻蜂/排箫/冲锋拉扯；裂隙敌人按位面伤害选武器。"},
 [13]={name="暗影棋子或新生灵",keep={"glasscutter","sword_lunarplant","voidcloth_scythe","bugnet","houndstooth_blowpipe"},note="位面护甲和武器优先；当前ASTRA适配取消新生灵捕获，击败本体后等死亡动画和服务器确认。"},
 [14]={name="双子/天体/织影者",keep={"orangestaff","skeletonhat","armorskeleton","glasscutter"},note="双子冲撞独立检查；天体二暂停攻击钻月灵缝；织影者处理囚笼与召唤。"},
 [15]={name="克劳斯或战争瓦器人后裔",keep={"armorsnurtleshell","orangestaff","armorskeleton","nightmarefuel","icestaff3"},note="克劳斯按骨甲冷却应对扑咬；机器人导弹传送锁壳；等待后裔阶段真实结束。"},
}}
P.reserve={cane=true,nightstick=true,panflute=true,icestaff=true,icestaff2=true,firestaff=true,icestaff3=true,armorsnurtleshell=true,orangestaff=true,armorskeleton=true,bugnet=true,houndstooth_blowpipe=true,
 boat_item=true,boat_grass_item=true,oar_driftwood=true,nightmarefuel=true,lunarplant_kit=true,voidcloth_kit=true}
P.known={};P.monsters={}
for _,name in ipairs({"voidcloth_boomerang","voidclothhat","voidcloth_scythe","voidcloth_kit","shroomcake","queen_torch","frogfishbowl_spice_garlic","purpleamulet","armorsnurtleshell"}) do P.known[name]=true end
for _,routes in pairs(Data.supplies) do for _,sets in pairs(routes) do for _,set in ipairs(sets) do for _,v in ipairs(set) do P.known[v.prefab]=true end end end end
for _,routes in pairs(Data.encounters) do for _,choices in pairs(routes) do for _,choice in ipairs(choices) do
 for _,list in ipairs({choice.monsters or {},choice.monster_options or {}}) do for _,v in ipairs(list) do
  P.monsters[v.prefab]=true;for _,name in ipairs(v.phase_chain or {}) do P.monsters[name]=true end
 end end
end end end
for _,name in ipairs({"bat_boss","beeguard","crabking_mob","crabking_mob_knight","crabking_icewall","worm_boss_dirt","wagdrone_rolling","wagdrone_flying","lunarthrall_plant_vine","stalker_minion1","stalker_minion2","klaus","deer_red","deer_blue"}) do P.monsters[name]=true end
-- 双子经服务器 soldierschanged 接管的召唤物不在初始 monsters 中。
-- 仅补第14关；普通世界和前十关的选敌范围不变。
function P.Monster(name,wave)
 if wave==12 and ({gestalt_guard_evolved=true,mutatedbuzzard_gestalt=true})[name]
  or wave==13 and ({bat_boss_shadow=true,rocky_boss_shadow=true,worm_boss_shadow=true,worm_boss_shadow_dirt=true,worm_boss_shadow_head=true})[name]
  or wave==14 and name=="lunarfrog" or wave==15 and (name=="alterguardian_phase4_lunarrift" or name=="wagboss_robot") then return true end
 return P.monsters[name] or wave==14 and (name=="eyeofterror_mini" or name=="eyeofterror_mini_grounded")
  or (wave==12 or wave==13) and name=="lunar_grazer"
  or wave==13 and name=="worm_boss_shadow_dirt" or false
end
-- 二、三关场景法杖是猎狗陷阱，清怪和普通补给结束后才允许拾取。
function P.TrapLoot(item,wave)
 return (wave==2 or wave==3) and (item.prefab=="firestaff" or item.prefab=="icestaff")
end
function P.DormantTrapGuard(e,wave)
 if (wave~=2 and wave~=3) or (e.prefab~="icehound" and e.prefab~="firehound") then return false end
 local a=e.AnimState
 return e:HasTag("sleeping") or a and (a:IsCurrentAnimation("sleep_pre") or a:IsCurrentAnimation("sleep_loop") or a:IsCurrentAnimation("sleep_pst")) or false
end
function P.Keep(name,wave)
 if P.reserve[name] then return true end
 for i=wave or 1,15 do for _,v in ipairs(P.waves[i].keep) do if v==name then return true end end end
 return false
end
function P.Upgrade(item,owned,wave)
 if P.Keep(item.prefab,wave) then return false end
 local superseded={spear={"tentaclespike","hambat","nightsword","ruins_bat","sword_lunarplant","voidcloth_scythe"},armorgrass={"armorwood","armorruins","armordragonfly"},footballhat={"ruinshat","dreadstonehat","lunarplanthat","voidclothhat"}}
 for _,name in ipairs(superseded[item.prefab] or {}) do if owned[name] then return true end end
 return false
end
-- 巡游和旋风阶段不让普通护甲自动选择减速的大理石甲；大副独处仍走专属换装。
function P.PickupAllowed(item,wave,player)
 if wave==5 and item.prefab=="armormarble" then return false end
 local doc=require("shadowself/control/arena_doc_inventory")
 local owner=doc.Owner(player)
 if owner and doc.Drop(owner,item,require("shadowself/control/actions").Items(player)) then return false end
 if doc.Protected(player,item) then return true end
 local arena=player and player._shadowself_arena_move_owner
 local frog=arena and arena.wave==2 and arena.frog_loot
 if wave==2 and frog and not frog.released and (frog.owned[item]
  or frog.prefabs and frog.prefabs[item.prefab] and not frog.initial_ground[item]) then
  local ii=item.replica and item.replica.inventoryitem
  if not ii or not ii:IsHeld() then return false end
 end
 if wave and wave>=10 then
  if item.prefab=="armor_sanity" or item.prefab=="yellowamulet" then return false end
  if item.prefab=="staff_tornado" and require("shadowself/control/arena_inventory").Condition(item)<.3 then return false end
  if item.prefab=="footballhat" and player then
   for _,other in ipairs(require("shadowself/control/actions").Items(player)) do
    local eq=other.replica and other.replica.equippable
    if other~=item and eq and eq:EquipSlot()==EQUIPSLOTS.HEAD and not other:HasTag("broken")
     and P.ArmorScore(other,EQUIPSLOTS.HEAD,{}) and require("shadowself/control/arena_inventory").Condition(other)>0 then return false end
   end
  end
 end
 if item.prefab=="meatballs" then return false end
 if item.prefab=="armorsnurtleshell" then return false end
 if wave and wave>=10 and (item.prefab=="armorruins" or item.prefab=="ruinshat" or item.prefab=="armorwood") then return false end
 return not (wave and wave>=9 and (item.prefab=="nightstick" or item.prefab=="armormarble"))
end
function P.AllowArmor(item,wave,enemies)
 if item.prefab~="armormarble" then return true end
 if wave==5 then return false end
 if wave and wave>=9 then return false end
 for _,e in ipairs(enemies or {}) do
  local health=e.replica and e.replica.health
  if e:IsValid() and not e:HasTag("dead") and not e:HasTag("isdead") and not (health and health.IsDead and health:IsDead()) then
   if wave==5 and ({powder_monkey=true,merm=true,frog=true,tentacle=true,mosquito=true})[e.prefab] then return false end
   if wave==6 and ({lightninggoat=true,fruitdragon=true,worm=true,mutatedhound=true,mutated_penguin=true,spider_moon=true,slurper=true,monkey=true})[e.prefab] then return false end
  end
 end
 return true
end
function P.ArmorScore(item,slot,enemies)
 local n=item.prefab;local score=({armorgrass=10,armorwood=30,armormarble=15,armordragonfly=65,armorruins=70,armordreadstone=75,armorwagpunk=85,armor_lunarplant=90,armor_voidcloth=90,
 footballhat=30,cookiecutterhat=40,slurtlehat=60,wathgrithr_improvedhat=65,ruinshat=75,dreadstonehat=80,lunarplanthat=90,voidclothhat=90})[n]
 local planar,electric=false,false
 for _,e in ipairs(enemies or {}) do
  if e:HasTag("lunar_aligned") or e:HasTag("shadow_aligned") or (e.prefab or ""):find("thrall",1,true) then planar=true end
  if e.prefab=="lightninggoat" and (e:HasTag("charged") or e:HasTag("electricdamage")) then electric=true end
 end
 if electric then if n=="rainhat" then return 1000 end;if n=="eyebrellahat" then return 900 end end
 if not score then return nil end
 if planar and (n=="lunarplanthat" or n=="voidclothhat" or n=="armor_lunarplant" or n=="armor_voidcloth") then score=score+200 end
 return score
end
P.known.rainhat=true;P.known.eyebrellahat=true
P.known.alterguardianhat=true;P.known.lunar_seed=true;P.known.staff_lunarplant=true
return P
