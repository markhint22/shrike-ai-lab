#!/usr/bin/env python3
"""OpenPose skeletons for xlite animation frames. Poses are drawn to read CLEARLY as
their action (v2 after feedback that attack/hit/death didn't convey the action):
  idle  - standing at the ready
  walk  - big mid-stride (exaggerated so it doesn't read as idle)
  walk2 - opposite stride
  attack- bladed firing stance, both arms extended out holding a weapon (reads as
          shooting for soldiers / lunging swipe for melee aliens)
  hit   - violent backward recoil, both arms flailing up, head thrown back, stumbling
  death - lying FLAT on the ground, head kept close to the neck (no detached head)
"""
import os
from PIL import Image, ImageDraw

OUT = "/run/media/mhintermeister/secondary_drive1/comfy/out/poses"
os.makedirs(OUT, exist_ok=True)
W = H = 1024
COL = [(255,0,0),(255,85,0),(255,170,0),(255,255,0),(170,255,0),(85,255,0),(0,255,0),
       (0,255,85),(0,255,170),(0,255,255),(0,170,255),(0,85,255),(0,0,255),(85,0,255),
       (170,0,255),(255,0,255),(255,0,170),(255,0,85)]
LIMBS = [(1,2),(1,5),(2,3),(3,4),(5,6),(6,7),(1,8),(8,9),(9,10),(1,11),(11,12),
         (12,13),(1,0),(0,14),(14,16),(0,15),(15,17)]
# 0 nose 1 neck 2 Rsho 3 Relb 4 Rwri 5 Lsho 6 Lelb 7 Lwri 8 Rhip 9 Rkne 10 Rank
# 11 Lhip 12 Lkne 13 Lank 14 Reye 15 Leye 16 Rear 17 Lear
POSES = {
 "idle": {0:(512,210),1:(512,300),2:(447,312),3:(432,420),4:(427,522),5:(577,312),
   6:(592,420),7:(597,522),8:(472,542),9:(468,682),10:(464,820),11:(552,542),
   12:(556,682),13:(560,820),14:(498,200),15:(526,200),16:(478,212),17:(546,212)},
 # big stride: R leg well forward, L leg well back, arms swing opposite + wide
 "walk": {0:(520,214),1:(516,302),2:(451,316),3:(410,398),4:(388,476),5:(581,316),
   6:(618,396),7:(642,470),8:(476,544),9:(524,656),10:(576,760),11:(556,544),
   12:(528,690),13:(486,838),14:(506,204),15:(534,204),16:(486,216),17:(552,216)},
 "walk2": {0:(504,214),1:(508,302),2:(443,316),3:(406,396),4:(382,470),5:(573,316),
   6:(614,398),7:(636,476),8:(468,544),9:(496,690),10:(454,838),11:(548,544),
   12:(600,656),13:(648,760),14:(490,204),15:(518,204),16:(472,216),17:(538,216)},
 # bladed FIRING stance: both arms extended right holding a weapon horizontal,
 # legs braced (front foot forward), head turned to aim
 "attack": {0:(545,222),1:(516,306),2:(474,318),3:(548,326),4:(628,330),5:(556,320),
   6:(600,336),7:(624,332),8:(486,542),9:(508,664),10:(548,772),11:(560,546),
   12:(560,684),13:(566,822),14:(560,214),15:(572,216),16:(536,220),17:(566,220)},
 # MELEE attack (aliens): a lunging strike to the right - the near arm THROWN
 # forward (punch/claw), the far arm coiled back, front leg lunging. No weapon.
 "attack_melee": {0:(548,224),1:(516,308),2:(474,318),3:(548,338),4:(628,354),
   5:(556,318),6:(516,362),7:(486,394),8:(486,542),9:(508,664),10:(548,772),
   11:(560,546),12:(560,684),13:(566,822),14:(560,216),15:(572,218),16:(536,222),17:(566,222)},
 # violent RECOIL: head back, both arms flung up-and-out, stumbling back off one leg
 "hit": {0:(462,258),1:(500,322),2:(444,326),3:(398,268),4:(360,222),5:(560,326),
   6:(610,272),7:(650,228),8:(496,548),9:(476,680),10:(458,816),11:(566,548),
   12:(598,674),13:(632,800),14:(450,248),15:(478,252),16:(442,262),17:(512,256)},
 # DEAD, lying flat on back: head LEFT + close to neck, body + legs horizontal
 "death": {0:(300,655),1:(366,660),2:(376,630),3:(440,616),4:(506,610),5:(378,690),
   6:(442,704),7:(506,712),8:(500,656),9:(616,650),10:(730,648),11:(500,682),
   12:(616,688),13:(730,690),14:(290,648),15:(298,668),16:(304,644),17:(310,672)},
}

def draw(pose, kp):
    img = Image.new("RGB",(W,H),(0,0,0)); d = ImageDraw.Draw(img)
    for i,(a,b) in enumerate(LIMBS):
        if a in kp and b in kp:
            d.line([kp[a],kp[b]], fill=COL[i%len(COL)], width=14)
    for i,(x,y) in kp.items():
        d.ellipse([x-9,y-9,x+9,y+9], fill=COL[i%len(COL)])
    img.save(f"{OUT}/{pose}.png"); return pose

if __name__ == "__main__":
    for p,kp in POSES.items():
        print("wrote", draw(p,kp))
    print("DONE", OUT)
