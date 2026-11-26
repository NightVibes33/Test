# Generate an ASCII bitmap font and an explicitly non-authenticating fixture.
from PIL import Image, ImageDraw, ImageFont
import qrcode, pathlib
font = ImageFont.load_default()
rows=[]
for code in range(32,127):
    im=Image.new("1",(8,12))
    ImageDraw.Draw(im).text((0,0),chr(code),font=font,fill=1)
    rows.append("{"+",".join(str(sum((1<<(7-x)) for x in range(8) if im.getpixel((x,y)))) for y in range(12))+"}")
qr=qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M,border=4)
qr.add_data("https://example.com/ps4-tailscale-emulator-fixture")
qr.make(fit=True)
matrix=qr.get_matrix()
lines=["PS4TS1","NeedsLogin","-", "0",str(len(matrix))]+["".join("1" if b else "0" for b in r) for r in matrix]
out="static const unsigned char font[95][12]={\n"+",\n".join(rows)+"\n};\n"
out+="static const char fixture[]=\n"+ "\n".join('"'+l+'\\n"' for l in lines)+";\n"
pathlib.Path(__file__).with_name("generated.h").write_text(out)
