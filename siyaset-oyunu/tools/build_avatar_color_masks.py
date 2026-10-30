"""Stable face-specific skin/lip and hair-fade masks. Never modifies source artwork.
Run with Python + Pillow. Polygon points were reviewed against each original mouth.
R = skin (faces) or hair; G = lips (faces) or baked skin fade (attachments).
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageChops
import json
ROOT=Path(__file__).resolve().parents[1]/'assets/avatar'
LIPS={
 'face_00':[(490,882),(540,864),(584,847),(603,846),(626,853),(651,849),(665,845),(700,851),(740,869),(765,884),(734,900),(698,917),(650,923),(598,923),(558,916),(520,899)],
 'face_01':[(505,875),(545,862),(584,846),(604,846),(625,852),(648,847),(663,845),(696,852),(730,865),(754,876),(723,896),(688,912),(645,917),(597,916),(558,907),(528,891)],
 'face_10':[(475,869),(518,853),(559,832),(588,827),(611,834),(631,836),(656,830),(682,828),(719,839),(757,857),(780,869),(745,888),(710,905),(665,911),(608,911),(557,907),(517,891)],
 'face_11':[(498,876),(537,860),(577,840),(600,838),(624,844),(650,841),(669,841),(707,854),(746,868),(770,878),(739,896),(698,912),(649,917),(600,916),(558,907),(524,893)],
 'face_36':[(493,871),(536,854),(581,833),(600,832),(627,841),(651,836),(670,835),(711,848),(751,864),(768,874),(730,895),(693,911),(645,917),(596,916),(554,906),(520,888)],
 'face_12':[(509,884),(547,869),(584,851),(604,849),(626,855),(648,851),(665,849),(696,856),(729,874),(749,887),(719,908),(686,925),(648,931),(609,931),(572,925),(539,908)],
 'face_13':[(507,890),(541,873),(578,851),(601,846),(625,851),(647,849),(666,845),(698,852),(735,875),(756,891),(726,913),(690,929),(648,936),(607,935),(570,926),(536,910)],
 'face_37':[(511,878),(546,861),(582,842),(601,840),(624,845),(646,842),(663,839),(697,850),(730,867),(752,880),(723,901),(687,919),(645,925),(607,925),(570,917),(538,902)]}

def smooth_polygon(points):
 result=[]
 for i,p1 in enumerate(points):
  p0=points[(i-1)%len(points)];p2=points[(i+1)%len(points)];p3=points[(i+2)%len(points)]
  for j in range(12):
   t=j/12
   result.append(tuple(.5*((2*p1[k])+(-p0[k]+p2[k])*t+(2*p0[k]-5*p1[k]+4*p2[k]-p3[k])*t*t+(-p0[k]+3*p1[k]-3*p2[k]+p3[k])*t*t*t) for k in [0,1]))
 return result

def ramp(ch,low,span):return ch.point(lambda x:round(max(0,min(1,(x-low)/span))*255))

def build():
 catalog=json.loads((ROOT/'catalog.json').read_text(encoding='utf8'))
 out=ROOT/'color_masks';out.mkdir(exist_ok=True)
 for id,a in catalog['assets'].items():
  im=Image.open(ROOT/a['file']).convert('RGBA');r,g,b,alpha=im.split();zero=Image.new('L',im.size)
  if a['category']=='face':
   lip=Image.new('L',im.size);ImageDraw.Draw(lip).polygon(smooth_polygon(LIPS[id]),fill=255);lip=lip.filter(ImageFilter.GaussianBlur(1.2))
   # Supersample the individually reviewed contours. Texture gradients are not
   # boundaries: using their strongest edge produced notches in shaded lips.
   contour=LIPS[id]
   top_count=10 if id in ['face_00','face_01','face_11','face_36','face_12','face_13','face_37'] else 11
   contour=[(x,y+(2 if i>=top_count else 0)) for i,(x,y) in enumerate(contour)]
   hi=Image.new('L',(im.width*2,im.height*2))
   ImageDraw.Draw(hi).polygon([(x*2,y*2) for x,y in smooth_polygon(contour)],fill=255)
   lip=hi.resize(im.size,Image.Resampling.LANCZOS).filter(ImageFilter.GaussianBlur(.8))
   # White and neutral highlights of the eye are protected, including antialiasing.
   neutral=ImageChops.subtract(ImageChops.lighter(r,ImageChops.lighter(g,b)),ImageChops.darker(r,ImageChops.darker(g,b)))
   white=ImageChops.multiply(ramp(ImageChops.darker(r,ImageChops.darker(g,b)),145,65),ImageChops.invert(ramp(neutral,20,35)))
   skin=ImageChops.multiply(ImageChops.invert(lip),ImageChops.invert(white))
   # Completely transparent pixels never belong to a feature.
   visible=alpha.point(lambda x:255 if x else 0)
   skin=ImageChops.multiply(skin,visible);lip=ImageChops.multiply(lip,visible)
   mask=Image.merge('RGBA',(skin,lip,zero,Image.new('L',im.size,255)))
   assert ImageChops.multiply(skin,white).getextrema()[1]<90
  elif a['category']!='iris':
   warm=ImageChops.multiply(ImageChops.multiply(ramp(r,145,80),ramp(g,85,75)),ramp(b,48,65))
   small=(max(17,im.width//4),max(17,im.height//4))
   interior=alpha.point(lambda x:255 if x>127 else 0).resize(small,Image.Resampling.NEAREST).filter(ImageFilter.MinFilter(17)).resize(im.size,Image.Resampling.BILINEAR)
   fade=ImageChops.multiply(warm,ImageChops.invert(interior))
   mask=Image.merge('RGBA',(ImageChops.invert(fade),fade,zero,Image.new('L',im.size,255)))
  else:continue
  if a['category']!='face':
   mask=mask.resize((max(1,im.width//2),max(1,im.height//2)),Image.Resampling.LANCZOS)
  mask.save(out/(id+'.png'),optimize=True)
 print('39 stable color masks generated; original pixels and transforms unchanged')
if __name__=='__main__':build()
