"""复用阿比盖尔抱起轨道的ghost符号变换，使用玩家自己的ghost build。
标准玩家 ghost_eyes 只有0..3帧，将阿比盖尔专属第4帧映射到3。
"""
from pathlib import Path
import copy,zipfile
from build_carry_animation import load,encode,decode
ROOT=Path(__file__).resolve().parents[1]
def generate():
 source,hashes=load('ghost_abigail_resurrect')
 original=source[0];frames=[]
 for i in range(172):
  index=i if i<86 else int(86+(i-86)*.5) if i<126 else int(106+(i-126)*7/46)
  frame=copy.deepcopy(original['frames'][min(index,113)])
  for element in frame['elements']:
   if hashes[element[0]].lower()=='ghost_eyes':element[1]=min(3,element[1])
  frame['events']=[];frames.append(frame)
 anim={'name':'shadowself_ghost_carry','facings':255,'bank':original['bank'],'rate':30.,'frames':frames}
 data=encode([anim],hashes);result,_=decode(data)
 assert len(result[0]['frames'])==172
 path=ROOT/'anim/shadowself_ghost_carry.zip'
 with zipfile.ZipFile(path,'w',zipfile.ZIP_DEFLATED) as z:z.writestr('anim.bin',data)
 print('Built ghost-bank carrier: 172 frames; own ghost build; no Abigail-exclusive eye frames')
if __name__=='__main__':generate()
