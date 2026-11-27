# Original icon and GP4 manifest; no external artwork or proprietary files.
from pathlib import Path
import sys
import datetime
import xml.etree.ElementTree as ET
from PIL import Image

root = Path(sys.argv[1])
cid = sys.argv[2]
mode = sys.argv[3] if len(sys.argv) > 3 else "frontend"
# Original app icon from Tailscale's own Android repository, pinned revision.
# CI supplies the official PNG; preserve its artwork and aspect ratio.
icon = Path(__file__).with_name("tailscale-official.png")
with Image.open(icon) as source:
    assert source.width == source.height, "official app icon must be square"
    im = source.convert("RGBA").resize((512, 512), Image.Resampling.LANCZOS)
    background = Image.new("RGBA", im.size, "white")
    background.alpha_composite(im)
    background.convert("RGB").save(root/"sce_sys/icon0.png")
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
