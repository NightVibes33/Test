# Original icon and GP4 manifest; no external artwork or proprietary files.
from pathlib import Path
import sys
import datetime
import xml.etree.ElementTree as ET
from PIL import Image, ImageDraw, ImageFont

root = Path(sys.argv[1])
cid = sys.argv[2]
im = Image.new("RGB", (512, 512), "#101827")
d = ImageDraw.Draw(im)
d.rounded_rectangle((28,28,484,484), radius=70, fill="#192538", outline="#55a9ff", width=5)
for y in range(3):
    for x in range(3):
        cx, cy = 160 + x * 96, 134 + y * 96
        d.ellipse((cx-24,cy-24,cx+24,cy+24),fill="#e2e8f0" if (x+y)%2==0 else "#55a9ff")
font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 48)
small = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 24)
d.text((256, 375), "PS4 TAILNET", anchor="mm", font=font, fill="#f1f5f9")
d.text((256, 429), "FRONTEND TEST", anchor="mm", font=small, fill="#94a3b8")
im.save(root/"sce_sys/icon0.png")
project = ET.Element("psproject", fmt="gp4", version="1000")
volume = ET.SubElement(project, "volume")
ET.SubElement(volume,"volume_type").text = "pkg_ps4_app"
ET.SubElement(volume,"volume_id").text = "PS4VOLUME"
ET.SubElement(volume,"volume_ts").text = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
ET.SubElement(volume,"package",content_id=cid,passcode="0"*32,storage_type="digital50",app_type="full")
chunks = ET.SubElement(volume,"chunk_info",chunk_count="1",scenario_count="1")
ET.SubElement(ET.SubElement(chunks,"chunks"),"chunk",id="0",layer_no="0",label="Chunk #0")
ET.SubElement(ET.SubElement(chunks,"scenarios",default_id="0"),"scenario",id="0",type="sp",initial_chunk_count="1",label="Scenario #0").text="0"
files=ET.SubElement(project,"files",img_no="0")
for name in ("eboot.bin","sce_sys/param.sfo","sce_sys/icon0.png"):
    assert (root/name).is_file()
    ET.SubElement(files,"file",targ_path=name,orig_path=name)
ET.SubElement(ET.SubElement(project,"rootdir"),"dir",targ_name="sce_sys")
ET.ElementTree(project).write(root/"project.gp4", encoding="utf-8",xml_declaration=True)
