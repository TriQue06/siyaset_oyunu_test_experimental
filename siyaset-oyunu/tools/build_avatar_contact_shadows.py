"""Bake soft, face-clipped contact/cast shadows from fade-aware avatar coverage; original PNGs are never modified."""
from pathlib import Path
from PIL import Image, ImageChops, ImageFilter
import json
ROOT=Path(__file__).resolve().parents[1]/'assets'/'avatar'
SCALE=.5
SIZE=(627,775)
def shifted(image, dx, dy):
 out=Image.new('L',SIZE);out.paste(image,(dx,dy));return out
def hair_coverage(source):
 # A face-colored fade is a compositing transition, not solid hair casting a shadow.
 # RGB is never edited: this separate coverage is used ONLY to bake shadows.
 r,g,b,alpha=source.split()
 def ramp(channel,low,span):
  return channel.point(lambda value:round(max(0,min(1,(value-low)/span))*255))
 warm=ImageChops.multiply(ImageChops.multiply(ramp(r,145,80),ramp(g,85,75)),ramp(b,48,65))
 small=(max(17,source.width//4),max(17,source.height//4))
 solid=alpha.point(lambda a:255 if a>127 else 0).resize(small,Image.Resampling.NEAREST)
 interior=solid.filter(ImageFilter.MinFilter(17)).resize(source.size,Image.Resampling.BILINEAR)
 # Restrict filtering to the silhouette edge; inner golden highlights retain coverage.
 fade=ImageChops.multiply(warm,ImageChops.invert(interior))
 retain=ImageChops.invert(fade.point(lambda a:round(a*.95)))
 return ImageChops.multiply(alpha,retain)

def verify_coverage():
 source=Image.new('RGBA',(256,256),(75,45,28,0))
 source.paste((75,45,28,255),(24,24,232,232))
 source.putpixel((25,100),(235,180,142,255))
 source.putpixel((128,128),(235,180,142,255))
 before=source.tobytes();coverage=hair_coverage(source)
 assert coverage.getpixel((25,100))<64,'skin-colored edge must not cast an opaque shadow'
 assert coverage.getpixel((25,128))==255,'dark edge strands must retain shadow coverage'
 assert coverage.getpixel((128,128))==255,'interior highlights must not be filtered'
 assert source.tobytes()==before,'source color/alpha must remain untouched'

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
   fx,fy,fw,fh=face.get('asset_corrections',{}).get(id,[0,0,1,1])
   ox=627+(ox-627)*fw+fx;oy=180+(oy-180)*fh+fy
   wx*=fw;hy*=fh
   source=Image.open(ROOT/asset['file']).convert('RGBA')
   alpha=hair_coverage(source).resize((round(source.width*sx*wx*SCALE),round(source.height*sy*hy*SCALE)),Image.Resampling.LANCZOS)
   silhouette=Image.new('L',SIZE);silhouette.paste(alpha,(round(ox*SCALE),round(oy*SCALE)))
   # Project in face coordinates; combine a broad cast shadow and a tighter contact edge.
   dx,dy,blur=(2,5,3) if category=='hair' else ((1,3,2) if category=='beard' else (1,2,1.5))
   cast=shifted(silhouette,dx,dy).filter(ImageFilter.GaussianBlur(blur)).point(lambda a:round(a*(.28 if category=='hair' else .22)))
   contact=shifted(silhouette,0,2).filter(ImageFilter.GaussianBlur(1.25)).point(lambda a:round(a*.10))
   opacity=ImageChops.multiply(ImageChops.add(cast,contact),mask)
   visible=ImageChops.multiply(opacity,ImageChops.invert(silhouette))
   assert visible.getextrema()[1]>=18,(face_id,id,'shadow hidden by layer')
   assert ImageChops.multiply(opacity,mask.point(lambda a:255 if a==0 else 0)).getextrema()[1]==0,(face_id,id,'shadow outside face')
   shadow=Image.new('RGBA',SIZE,(38,25,19,0));shadow.putalpha(opacity)
   destination=out/(face_id+'__'+id+'.png')
   temporary=destination.with_suffix('.tmp.png')
   shadow.save(temporary,optimize=True)
   temporary.replace(destination);count+=1
 print(f'{count} face-clipped shadow layers generated')
if __name__=='__main__':
 verify_coverage()
 build()
