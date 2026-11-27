from PIL import Image
from pathlib import Path
import math,sys

source,target=map(Path,sys.argv[1:])
with Image.open(source) as im:
    image=im.convert("RGB")
w,h=image.size
assert (w,h)==(1254,1254), (w,h)
# Crop the thin outer white frame. Extend the original interior edge colors
# into the corners to produce an opaque, full-bleed iOS asset.
# Never alter the original JPEG or draw a second rounded mask.
bleed=round(w*0.034)
inset=round(w*0.022)
radius=round(w*0.255)
low=inset+radius
high=w-1-low
original=image.load()
canvas=image.copy()
pixels=canvas.load()
for y in range(bleed,h-bleed):
    cy=min(max(y,low),high)
    for x in range(bleed,w-bleed):
        cx=min(max(x,low),high)
        dx=x-cx
        dy=y-cy
        d=math.hypot(dx,dy)
        if d<=radius:
            continue
        sx=round(cx+dx*radius/d)
        sy=round(cy+dy*radius/d)
        color=original[sx,sy]
        f=1-math.exp(-(d-radius)/(w*0.055))
        dark=(7,12,28)
        pixels[x,y]=tuple(round(v*(1-f)+b*f) for v,b in zip(color,dark))
canvas=canvas.crop((bleed,bleed,w-bleed,h-bleed))
canvas=canvas.resize((1024,1024),Image.Resampling.LANCZOS)
assert canvas.mode=="RGB"
assert all(max(canvas.getpixel(p))<150 for p in [(0,0),(1023,0),(0,1023),(1023,1023)])
canvas.save(target,format="PNG")
print("PASS: full-bleed opaque 1024px icon; original artwork retained, native iOS mask only")
