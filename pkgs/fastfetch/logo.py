# Draws pkgs/fastfetch/logo.txt: 并行 ("parallel") in block characters.
#   python3 logo.py <Source Han Sans .ttc> 10 32 > raw.txt   (10 rows, face 32 = SC Bold)
# then prefix each line with $1 (fastfetch colour 1 = the accent) and pad to equal width.
import sys
from PIL import Image, ImageDraw, ImageFont
FONT = sys.argv[1]; rows = int(sys.argv[2]); idx = int(sys.argv[3]) if len(sys.argv) > 3 else 0
QUAD = {(0,0,0,0):" ",(1,0,0,0):"▘",(0,1,0,0):"▝",(1,1,0,0):"▀",(0,0,1,0):"▖",(1,0,1,0):"▌",(0,1,1,0):"▞",(1,1,1,0):"▛",
        (0,0,0,1):"▗",(1,0,0,1):"▚",(0,1,0,1):"▐",(1,1,0,1):"▜",(0,0,1,1):"▄",(1,0,1,1):"▙",(0,1,1,1):"▟",(1,1,1,1):"█"}
text = "并行"
f = ImageFont.truetype(FONT, 400, index=idx)
x0, y0, x1, y1 = f.getbbox(text)
img = Image.new("L", (x1 - x0 + 20, y1 - y0 + 20), 0)
ImageDraw.Draw(img).text((10 - x0, 10 - y0), text, font=f, fill=255)
img = img.crop(img.getbbox())
W, H = img.size
cols = round(2 * rows * W / H)                 # a terminal cell is twice as tall as wide
small = img.resize((cols * 2, rows * 2), Image.LANCZOS)
px = small.load()
th = int(sys.argv[4]) if len(sys.argv) > 4 else 110
for r in range(rows):
    line = ""
    for c in range(cols):
        q = tuple(int(px[c*2+dx, r*2+dy] > th) for dy in (0,1) for dx in (0,1))
        line += QUAD[(q[0], q[1], q[2], q[3])]
    print(line.rstrip())
