"""Derive eye-white coverage from original face PNGs; never change the source art."""
from pathlib import Path
from collections import deque
import json, sys
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[1]/'assets'/'avatar'
def build():
 data=json.loads((ROOT/'catalog.json').read_text(encoding='utf8'))
 out=ROOT/'eye_masks';out.mkdir(exist_ok=True)
 sheet=Image.new('RGB',(1200,800),'#e7ddc5'); draw=ImageDraw.Draw(sheet)
 for index,(face,info) in enumerate(data['faces'].items()):
  source=Image.open(ROOT/(face+'.png')).convert('RGBA'); info['eye_masks']=[]
  for eye_index,eye in enumerate(info['eyes']):
   sx,sy=round(eye[0]),round(eye[1]-180)
   roi=(sx-105,sy-65,sx+105,sy+65)
   def eligible(x,y):
    r,g,b,a=source.getpixel((x,y))
    return a>200 and min(r,g,b)>150 and max(r,g,b)-min(r,g,b)<48
   todo=deque([(sx,sy)]);visited=set()
   while todo:
    x,y=todo.popleft()
    if (x,y) in visited or not(roi[0]<=x<roi[2] and roi[1]<=y<roi[3]) or not eligible(x,y):continue
    visited.add((x,y));todo.extend([(x-1,y),(x+1,y),(x,y-1),(x,y+1)])
   assert len(visited)>3000,(face,eye_index,len(visited))
   x0=min(x for x,y in visited)-2;y0=min(y for x,y in visited)-2
   x1=max(x for x,y in visited)+3;y1=max(y for x,y in visited)+3
   mask=Image.new('RGBA',(x1-x0,y1-y0))
   for x,y in visited:
    r,g,b,a=source.getpixel((x,y))
    # Retain the painted dark eyelid edge, with fractional coverage at its boundary.
    coverage=max(0,min(1,(min(r,g,b)-150)/65))
    mask.putpixel((x-x0,y-y0),(255,255,255,round(255*coverage)))
   name=f'{face}_{eye_index}.png';mask.save(out/name)
   # The actual eye-white centroid replaces the earlier approximate face landmarks.
   cx=sum(x for x,y in visited)/len(visited);cy=sum(y for x,y in visited)/len(visited)
   info['eye_masks'].append({'file':'eye_masks/'+name,'rect':[x0,y0+180,x1-x0,y1-y0],'center':[round(cx,2),round(cy+180,2)]})
   thumb=source.crop((sx-110,sy-75,sx+110,sy+75)).resize((220,150))
   sheet.paste(thumb,((index%4)*300,(index//4)*400+eye_index*170+20))
  draw.text(((index%4)*300,(index//4)*400),face,fill='black')
 (ROOT/'catalog.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
 if '--preview' in sys.argv:
  preview=ROOT.parents[2]/'build/avatar-review/eye-source.jpg'
  preview.parent.mkdir(parents=True,exist_ok=True)
  sheet.save(preview)
if __name__=='__main__':build()

