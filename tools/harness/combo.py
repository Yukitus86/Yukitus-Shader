import sys
from PIL import Image
files=sys.argv[2:]; out=sys.argv[1]
ims=[Image.open(f) for f in files]
w,h=ims[0].size
cols=2 if len(ims)>2 else 1
rows=(len(ims)+cols-1)//cols
o=Image.new('RGB',(w*cols,h*rows))
for i,im in enumerate(ims): o.paste(im,((i%cols)*w,(i//cols)*h))
scale=min(1.0, 1400/(w*cols))
o.resize((int(w*cols*scale),int(h*rows*scale))).save(out)
