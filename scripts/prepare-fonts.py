#!/usr/bin/env python3
"""Recreate compact embedded DejaVu subsets. Requires FontTools and full DejaVu.
Normal builds use the checked-in TTFs. Optional argument: DejaVu font directory.
"""
from pathlib import Path
import sys
from fontTools import subset

root = Path(__file__).resolve().parents[1]
source = Path(sys.argv[1]) if len(sys.argv)>1 else Path('/usr/share/fonts/truetype/dejavu')
points = list(range(32,127))+list(range(0x410,0x450))+[0x401,0x451,0x2014,0x2013,0x2026,0xab,0xbb]
for name,file in [('body','DejaVuSans.ttf'),('display','DejaVuSans-Bold.ttf'),('mono','DejaVuSansMono.ttf')]:
    options = subset.Options();options.hinting = False
    font = subset.load_font(str(source/file),options)
    builder = subset.Subsetter(options=options);builder.populate(unicodes=points);builder.subset(font)
    subset.save_font(font,str(root/'assets/fonts'/(name+'.ttf')),options)
