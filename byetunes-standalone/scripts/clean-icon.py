"""Remove only the connected white exterior of the original supplied icon."""
from pathlib import Path
from collections import deque
import sys
from PIL import Image

source, target = map(Path,sys.argv[1:])
im=Image.open(source).convert("RGB")
w,h=im.size
px=im.load()
# Do not touch the central white skull or colored highlights. Only the neutral,
# light pixels connected to the exterior, within the corner/perimeter band.
seen=set()
queue=deque()
def candidate(x,y):
    r,g,b=px[x,y]
    outer=(x<w*.18 or x>=w*.82 or y<h*.18 or y>=h*.82)
    return outer and min(r,g,b)>=145 and max(r,g,b)-min(r,g,b)<=55
def add(x,y):
    if 0<=x<w and 0<=y<h and (x,y) not in seen and candidate(x,y):
        seen.add((x,y))
        queue.append((x,y))
for x in range(w):
    add(x,0);add(x,h-1)
for y in range(h):
    add(0,y);add(w-1,y)
while queue:
    x,y=queue.popleft()
    for dx,dy in ((1,0),(-1,0),(0,1),(0,-1)):
        add(x+dx,y+dy)
for x,y in seen:
    # Match the icon's dark navy base, with its cyan/violet corner tint.
    fx=x/max(1,w-1);fy=y/max(1,h-1)
    px[x,y]=(int(5+13*fx),int(12+12*(1-fx)*(1-fy)),int(26+19*fx))
# The icon is deliberately opaque. iOS applies its own rounded mask.
out=im.resize((1024,1024),Image.Resampling.LANCZOS)
out.save(target,format="PNG")
assert out.mode=="RGB" and out.size==(1024,1024)
assert all(max(out.getpixel(p))<100 for p in [(0,0),(1023,0),(0,1023),(1023,1023)])
print(f"PASS: removed {len(seen)} exterior pixels; 1024px opaque icon")
