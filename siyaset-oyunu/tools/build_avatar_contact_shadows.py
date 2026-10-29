"""Bake soft, face-clipped contact/cast shadows from untouched avatar alpha layers."""
from pathlib import Path
from PIL import Image, ImageChops, ImageFilter
import json
ROOT=Path(__file__).resolve().parents[1]/'assets'/'avatar'
SCALE=.5
SIZE=(627,775)
def shifted(image, dx, dy):
 out=Image.new('L',SIZE);out.paste(image,(dx,dy));return out
def build():
 catalog=json.loads((ROOT/'catalog.json').read_text(encoding='utf8'))
 out=ROOT/'contact_shadows';out.mkdir(exist_ok=True)
 count=0
 for face_id,face in catalog['faces'].items():
  base=Image.open(ROOT/(face_id+'.png')).convert('RGBA')
  mask=Image.new('L',SIZE)
  mask.paste(base.getchannel('A').resize((627,627),Image.Resampling.LANCZOS),(0,90))
  gender=catalog['assets'][face_id]['gender']
  for id,asset in catalog['assets'].items():
   category=asset['category']
   if category not in ['hair','beard','moustache'] or asset['gender']!=gender:continue
   correction=face['corrections'].get(category,[0,0,1,1])
   sx,sy=asset['scale'];ox,oy=asset['offset'];cx,cy,wx,hy=correction
   ox=627+(ox-627)*wx+cx;oy=180+(oy-180)*hy+cy
   source=Image.open(ROOT/asset['file']).convert('RGBA')
   alpha=source.getchannel('A').resize((round(source.width*sx*wx*SCALE),round(source.height*sy*hy*SCALE)),Image.Resampling.LANCZOS)
   silhouette=Image.new('L',SIZE);silhouette.paste(alpha,(round(ox*SCALE),round(oy*SCALE)))
   # Project in face coordinates; combine a broad cast shadow and a tighter contact edge.
   dx,dy,blur=(5,13,5) if category=='hair' else (2,8,3)
   cast=shifted(silhouette,dx,dy).filter(ImageFilter.GaussianBlur(blur)).point(lambda a:round(a*.34))
   contact=shifted(silhouette,0,4).filter(ImageFilter.GaussianBlur(2)).point(lambda a:round(a*.18))
   opacity=ImageChops.multiply(ImageChops.add(cast,contact),mask)
   visible=ImageChops.multiply(opacity,ImageChops.invert(silhouette))
   assert visible.getextrema()[1]>=30,(face_id,id,'shadow hidden by layer')
   assert ImageChops.multiply(opacity,mask.point(lambda a:255 if a==0 else 0)).getextrema()[1]==0,(face_id,id,'shadow outside face')
   shadow=Image.new('RGBA',SIZE,(38,25,19,0));shadow.putalpha(opacity)
   shadow.save(out/(face_id+'__'+id+'.png'),optimize=True);count+=1
 print(f'{count} face-clipped shadow layers generated')
if __name__=='__main__':build()
