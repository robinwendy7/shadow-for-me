name = "如影随形(测试版)"
description = "安静地跟着你的另一个自己。纯客户端本地影子与离线对话。\n仅聊天输入栏：右键拖动，回车发送。护甲槽上方可战斗接管。"
author = "舒晴伊子"
version = "0.12.25"
api_version = 10
dst_compatible = true
client_only_mod = true
all_clients_require_mod = false
server_only_mod = false
configuration_options = {
    {name="speech_color",label="影子说话字体颜色",options={{description="红",data="red"},{description="橙",data="orange"},{description="黄",data="yellow"},{description="绿",data="green"},{description="青",data="cyan"},{description="蓝",data="blue"},{description="紫",data="purple"}},default="red"},
    {name="speech_voice",label="影子说话是否有声音",options={{description="是",data=true},{description="否",data=false}},default=true},
    {name="battle_music",label="接管战斗后燃起来",hover="接管战斗时播放所提供的雨爱BGM，停止战斗时关闭。",options={{description="是",data=true},{description="否",data=false}},default=true},
    {name="leash", label="自主活动范围（码）", options={{description="5",data=5},{description="8",data=8},{description="10",data=10},{description="12",data=12},{description="15",data=15}}, default=15},
    {name="frequency", label="主动对话间隔", options={{description="安静（45秒）",data=45},{description="默认（25秒）",data=25},{description="健谈（12秒）",data=12}}, default=25},
    {name="ceremony", label="本地复活演出", options={{description="开启",data=true},{description="关闭",data=false}}, default=true},
}
