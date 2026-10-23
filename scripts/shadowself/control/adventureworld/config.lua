-- 2067228865/scripts/adventure/main.lua：level1..4，投币箭头旋转 angle+90，5秒移除。
-- 板块与背包表槽沿用用户 zom 的约定；改图后只需维护此文件。
return {
    world_ids={["7"]=true}, -- zom WorldInfo 的冒险分片；其他部署可在这里调整。
    grades={"旅者","专家","大师","传奇"},
    sectors={{488.31,-324.14},{483.30,-52.92},{515.18,202.72},{334.49,368.68},
        {21.90,263.32},{-130.54,50.34},{-392.30,28.19},{-170.05,-289.60},
        {157.91,-461.01},{-504.40,463.97}},
    baselines={12,8,20}, min_cross=.008, scan_radius=60, scan_interval=.3,
    probe_interval=60, movement_interval=.45, stalled_timeout=20,
    watch_distance=90, portal_timeout=18,
}
