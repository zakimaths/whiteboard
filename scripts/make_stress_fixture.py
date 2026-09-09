"""Create a labelled, isolated drawing workload for local performance checks."""
import json
import math
import pathlib
import struct
import zlib
import argparse
import uuid

project = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--library",type=pathlib.Path,default=project/"build/Performance Library")
args = parser.parse_args()
destination = args.library / "Archive/Performance fixture.whiteboard"
destination.mkdir(parents=True, exist_ok=False)
assets = destination / "assets"
assets.mkdir()
# Synthetic 708 × 1000 reference; no screenshots or personal files are read.
def chunk(kind,data):
    return struct.pack(">I",len(data))+kind+data+struct.pack(">I",zlib.crc32(kind+data)&0xffffffff)
rows = bytearray()
for y in range(1000):
    rows.append(0)
    for x in range(708):
        line = (y%60 < 3 and 55 < x < 650) or (x%80 < 2 and 300 < y < 900)
        rows.extend((60,110,190) if line else (249,247,240))
source = b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",708,1000,8,2,0,0,0))+chunk(b"IDAT",zlib.compress(rows))+chunk(b"IEND",b"")
board = {"version":1,"id":str(uuid.uuid4()),"ink":[],"images":[],"texts":[],"viewport":{"zoom":1,"origin":{"x":0,"y":0}},"background":"paper","recognisedText":""}
for i in range(2000):
    x = (i % 40) * 100 + 100
    y = (i // 40) * 95 + 190
    points = [{"x":x+j*1.1,"y":y+math.sin(j/6)*14} for j in range(60)]
    board["ink"].append({"id":str(uuid.uuid4()),"points":points,"colour":"blue" if i%4 == 0 else "ink","width":2,"highlighter":False})
for i in range(8):
    name = f"reference-{i}.png"
    (assets/name).write_bytes(source)
    board["images"].append({"id":str(uuid.uuid4()),"asset":name,"frame":{"x":170+(i%4)*285,"y":200+(i//4)*360,"width":240,"height":339},"locked":False})
board["texts"].append({"id":str(uuid.uuid4()),"text":"Performance fixture · 2,000 strokes · 120,000 points · 8 images","origin":{"x":180,"y":155},"size":20})
(destination/"board.json").write_text(json.dumps(board,separators=(",",":")))
print(destination)
