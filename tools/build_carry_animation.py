"""ANIM v4: 按官方 Mod Tools/buildanimation.py 格式制作人形托抱轨道。

被抱者使用原版 wendy_resurrect 的完整水平躺卧动作。
抱人者使用玩家符号骨架、双臂 IK，前后两轨与原版172帧对齐。
只生成变换数据，不复制皮肤或替换角色 build。
"""
from pathlib import Path
import struct,zipfile,math,copy,json
ROOT=Path(__file__).resolve().parents[1]
ANIM=Path(r"D:\Steam\steamapps\common\Don't Starve Together\data\anim")
class Reader:
 def __init__(self,b): self.b=b;self.o=0
 def read(self,fmt):
  v=struct.unpack_from('<'+fmt,self.b,self.o);self.o+=struct.calcsize('<'+fmt);return v[0] if len(v)==1 else v
 def string(self):
  n=self.read('I');s=self.b[self.o:self.o+n].decode();self.o+=n;return s
def decode(b):
 r=Reader(b);assert b[:4]==b'ANIM';r.o=4
 version,els,frames,events,num=r.read('5I');assert version==4
 anims=[]
 for _ in range(num):
  name=r.string();facings,bank,rate,count=r.read('BIfI');fs=[]
  for _ in range(count):
   bbox=r.read('4f');ev=[r.read('I') for _ in range(r.read('I'))]
   elements=[list(r.read('3I7f')) for _ in range(r.read('I'))]
   fs.append({'bbox':bbox,'events':ev,'elements':elements})
  anims.append({'name':name,'facings':facings,'bank':bank,'rate':rate,'frames':fs})
 hashes={}
 for _ in range(r.read('I')):
  h=r.read('I');hashes[h]=r.string()
 assert r.o==len(b),(r.o,len(b))
 assert sum(len(f['elements']) for a in anims for f in a['frames'])==els
 return anims,hashes
def encode(anims,hashes):
 p=lambda fmt,*args:struct.pack('<'+fmt,*args)
 def s(v): b=v.encode();return p('I',len(b))+b
 fs=[f for a in anims for f in a['frames']]
 b=b'ANIM'+p('5I',4,sum(len(f['elements']) for f in fs),len(fs),sum(len(f['events']) for f in fs),len(anims))
 for a in anims:
  b+=s(a['name'])+p('BIfI',a['facings'],a['bank'],a['rate'],len(a['frames']))
  for f in a['frames']:
   b+=p('4f',*f['bbox'])+p('I',len(f['events']))+b''.join(p('I',e) for e in f['events'])
   b+=p('I',len(f['elements']))+b''.join(p('3I7f',*e) for e in f['elements'])
 b+=p('I',len(hashes))
 for h,name in hashes.items():b+=p('I',h)+s(name)
 return b
def load(asset):return decode(zipfile.ZipFile(ANIM/(asset+'.zip')).read('anim.bin'))
def rotate(e,angle,x,y):
 e=copy.copy(e);co,si=math.cos(angle),math.sin(angle)
 a,b,c,d=e[3:7]
 e[3:7]=[co*a-si*b,si*a+co*b,co*c-si*d,si*c+co*d]
 e[7],e[8]=x,y
 return e
def elbow(s,t,l1=32,l2=34):
 dx,dy=t[0]-s[0],t[1]-s[1];dist=max(.01,math.hypot(dx,dy))
 d=min(l1+l2-.1,max(abs(l1-l2)+.1,dist))
 ux,uy=dx/dist,dy/dist
 a=(l1*l1-l2*l2+d*d)/(2*d);h=math.sqrt(max(0,l1*l1-a*a))
 # 肘关节偏下，掌心朝上托住水平身体。
 side=1 if ux>=0 else -1
 return s[0]+ux*a-uy*h*side,s[1]+uy*a+ux*h*side
def generate():
 idle,hashes=load('player_idles');victims,vhash=load('wendy_resurrect');hashes.update(vhash)
 base=next(a for a in idle if a['name']=='idle_loop' and a['facings']==8)
 victim=victims[0];back=[];front=[];tracks=[]
 armnames={'arm_upper','arm_upper_skin','arm_upper_comp','arm_lower','arm_lower_comp','hand'}
 for i,vf in enumerate(victim['frames']):
  seed=base['frames'][i%len(base['frames'])]['elements']
  parts={}
  for el in vf['elements']:parts.setdefault(hashes[el[0]].lower(),el)
  torso=parts.get('torso');head=parts.get('headbase')
  holding=90<=i<=125 and torso is not None and head is not None
  if holding:cx=(torso[7]+head[7])*.5;cy=torso[8]+135
  elif i>125:
   v=max(0,1-(i-125)/36);cx=42*v;cy=-160*v
  else:cx=40*max(0,min(1,(i-65)/25));cy=-25*max(0,min(1,(i-65)/25))
  body=[];arms=[]
  originals={}
  for el in seed:
   n=hashes[el[0]].lower()
   if n in armnames and el[1]==0:
    side=-1 if el[7]<0 else 1;originals[(n,side)]=el
  joints={}
  for side in [-1,1]:
   upper=originals.get(('arm_upper',side));lower=originals.get(('arm_lower',side));hand=originals.get(('hand',side))
   if upper and lower and hand:
    shoulder=(upper[7]+cx,upper[8]+cy)
    wrist=((head[7]+15 if side<0 else torso[7]+35),torso[8]+18) if holding else (hand[7]+cx,hand[8]+cy)
    middle=elbow(shoulder,wrist) if holding else (lower[7]+cx,lower[8]+cy)
    du=math.atan2(middle[1]-shoulder[1],middle[0]-shoulder[0])-math.atan2(lower[8]-upper[8],lower[7]-upper[7])
    dl=math.atan2(wrist[1]-middle[1],wrist[0]-middle[0])-math.atan2(hand[8]-lower[8],hand[7]-lower[7])
    joints[side]=(shoulder,middle,wrist,du,dl)
  for el in seed:
   name=hashes[el[0]].lower()
   if name in armnames:
    if el[1]!=0:continue
    side=-1 if el[7]<0 else 1
    if side not in joints:continue
    shoulder,middle,wrist,du,dl=joints[side]
    if name.startswith('arm_upper'):new=rotate(el,du,*shoulder)
    elif name.startswith('arm_lower'):new=rotate(el,dl,*middle)
    else:new=rotate(el,dl,*wrist)
    arms.append(new)
   else:
    new=copy.copy(el);new[7]+=cx;new[8]+=cy;body.append(new)
  bbox=(50.,-170.,500.,550.)
  back.append({'bbox':bbox,'events':[],'elements':body})
  front.append({'bbox':bbox,'events':[],'elements':arms})
  if holding:tracks.append({'frame':i,'head':head[7:9],'torso':torso[7:9],'carrier_offset':[cx,cy]})
 animations=[{'name':'shadowself_carry_back','facings':255,'bank':base['bank'],'rate':victim['rate'],'frames':back},
             {'name':'shadowself_carry_front','facings':255,'bank':base['bank'],'rate':victim['rate'],'frames':front}]
 data=encode(animations,hashes);decoded,_=decode(data)
 assert len(decoded)==2 and all(len(a['frames'])==172 for a in decoded)
 assert len(tracks)==36 and all(abs(t['head'][1]-t['torso'][1])<35 for t in tracks)
 target=ROOT/'anim/shadowself_carry.zip';target.parent.mkdir(exist_ok=True)
 with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED) as z:z.writestr('anim.bin',data)
 (ROOT/'tests/carry_tracks.json').write_text(json.dumps({'rate':victim['rate'],'frames':172,'horizontal_hold_frames':tracks},indent=2),encoding='utf8')
 print('Built',target.name,'172 frames x 2 tracks; original victim horizontal pose at frames 90-125')
if __name__=='__main__':generate()
