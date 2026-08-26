#!/usr/bin/env python3
"""Generate OpenPose skeleton images (1024x1024) for distinct animation poses, so a
ControlNet-OpenPose pass forces the SAME character into genuinely different poses
(fixes the img2img 'every frame looks the same' problem). Standard 18-keypoint COCO
format with the canonical OpenPose colors ControlNet was trained on."""
import os
from PIL import Image, ImageDraw

OUT = "/run/media/mhintermeister/secondary_drive1/comfy/out/poses"
os.makedirs(OUT, exist_ok=True)
W = H = 1024

# canonical 18-keypoint colors (RGB)
COL = [(255,0,0),(255,85,0),(255,170,0),(255,255,0),(170,255,0),(85,255,0),(0,255,0),
       (0,255,85),(0,255,170),(0,255,255),(0,170,255),(0,85,255),(0,0,255),(85,0,255),
       (170,0,255),(255,0,255),(255,0,170),(255,0,85)]
# limb pairs (0-indexed into the 18 keypoints) + the color index for each limb
LIMBS = [(1,2),(1,5),(2,3),(3,4),(5,6),(6,7),(1,8),(8,9),(9,10),(1,11),(11,12),
         (12,13),(1,0),(0,14),(14,16),(0,15),(15,17)]

# keypoint order: 0 nose,1 neck,2 Rsho,3 Relb,4 Rwri,5 Lsho,6 Lelb,7 Lwri,
# 8 Rhip,9 Rkne,10 Rank,11 Lhip,12 Lkne,13 Lank,14 Reye,15 Leye,16 Rear,17 Lear
POSES = {
 "idle": {0:(512,210),1:(512,300),2:(447,312),3:(432,420),4:(427,522),5:(577,312),
   6:(592,420),7:(597,522),8:(472,542),9:(468,682),10:(464,820),11:(552,542),
   12:(556,682),13:(560,820),14:(498,200),15:(526,200),16:(478,212),17:(546,212)},
 "walk": {0:(516,214),1:(514,302),2:(449,314),3:(422,410),4:(408,500),5:(579,314),
   6:(604,404),7:(620,484),8:(474,544),9:(506,664),10:(548,782),11:(554,544),
   12:(540,686),13:(505,832),14:(502,204),15:(530,204),16:(482,216),17:(548,216)},
 "attack": {0:(556,224),1:(538,306),2:(474,314),3:(548,296),4:(636,272),5:(590,320),
   6:(578,430),7:(566,528),8:(486,540),9:(540,656),10:(600,770),11:(556,548),
   12:(548,690),13:(520,824),14:(544,214),15:(572,214),16:(526,224),17:(590,222)},
 "hit": {0:(470,236),1:(494,314),2:(430,318),3:(392,240),4:(360,168),5:(560,320),
   6:(600,250),7:(636,182),8:(486,548),9:(474,686),10:(460,822),11:(560,548),
   12:(576,682),13:(596,816),14:(456,226),15:(484,224),16:(444,238),17:(508,232)},
 # death: lying FLAT on the back (supine), body fully horizontal - head far left,
 # feet far right, spine + legs along a horizontal line so ControlNet renders a
 # prone corpse, not a seated figure.
 "death": {0:(250,545),1:(340,550),2:(350,510),3:(410,480),4:(470,462),5:(350,590),
   6:(410,620),7:(470,640),8:(530,535),9:(650,528),10:(786,522),11:(530,575),
   12:(650,585),13:(786,592),14:(240,535),15:(246,558),16:(258,528),17:(264,566)},
}

def draw(pose, kp):
    img = Image.new("RGB",(W,H),(0,0,0)); d = ImageDraw.Draw(img)
    for i,(a,b) in enumerate(LIMBS):
        if a in kp and b in kp:
            d.line([kp[a],kp[b]], fill=COL[i%len(COL)], width=14)
    for i,(x,y) in kp.items():
        d.ellipse([x-9,y-9,x+9,y+9], fill=COL[i%len(COL)])
    img.save(f"{OUT}/{pose}.png")
    return pose

if __name__ == "__main__":
    for p,kp in POSES.items():
        print("wrote", draw(p,kp))
    print("DONE", OUT)
