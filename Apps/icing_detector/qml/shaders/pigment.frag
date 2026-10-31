#version 440
// Native Qt port of liquid-pigment-ice.html: autonomous pigment field.
// Retained water field is supplied by studio/ambient.py; no UI events are consumed.
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform buf {
 mat4 qt_Matrix;
 float qt_Opacity;
 vec2 resolution;
 float phase;
 float rotationPhase;
 float circulation;
 float motion;
 float blend;
 float detail;
 float relief;
 float saturation;
 float darkMode;
 vec2 fieldTexel;
 vec4 fieldMapping;
 float stir;
 float radius;
 float activity;
 float envelope;
 float gentle;
};
layout(binding=1) uniform sampler2D waterField;
const float TAU=6.283185307179586;
float hash(vec2 p){p=fract(p*vec2(123.34,345.45));p+=dot(p,p+34.345);return fract(p.x*p.y);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+1.),f.x),f.y);}
float fbm(vec2 p){float f=0.,a=.5;mat2 m=mat2(.8,.6,-.6,.8);for(int i=0;i<4;i++){f+=a*noise(p);p=m*p*2.03+vec2(3.7,9.2);a*=.5;}return f;}
vec2 warp(vec2 p,float t){
 vec2 orbit=motion*.23*vec2(cos(t),sin(t));
 vec2 a=vec2(fbm(p*3.3+orbit+vec2(1.8,7.1)),fbm(p*3.3-orbit+vec2(8.3,2.8)))-.46;
 vec2 b=vec2(fbm(p*7.4+a*2.+orbit*.6),fbm(p*7.4-a*2.-orbit*.6+6.4))-.46;
 return p+a*.20+b*(.025+detail*.035);
}
float ellipse(vec2 p,vec2 c,vec2 r,float angle){vec2 q=p-c;float a=cos(angle),b=sin(angle);q=mat2(a,-b,b,a)*q;return (length(q/r)-1.)*min(r.x,r.y);}
vec2 eddy(vec2 p,vec2 center,float radius,float strength){vec2 v=p-center;float angle=strength*exp(-dot(v,v)/(radius*radius));float c=cos(angle),s=sin(angle);return center+mat2(c,-s,s,c)*v;}
vec2 fluidCirculation(vec2 p,float cycle,float softness){
 // Radial twist, reciprocal stretch and alternating shears each preserve area.
 // Their bounded, periodic composition stretches pigment instead of rotating a plate.
 vec2 center=softness*vec2(.052*(cos(cycle)-1.),.040*sin(cycle));
 vec2 z=p-center;
 float radial=exp(-dot(z,z)*1.8)-.55;
 float angle=cycle+softness*(1.65*radial*sin(cycle)+.12*radial*sin(2.*cycle));
 float c=cos(angle),s=sin(angle);z=mat2(c,-s,s,c)*z;
 float breath=softness*.13*sin(2.*cycle+.35*sin(cycle));
 z*=vec2(exp(breath),exp(-breath));
 z.x+=softness*.13*sin(3.1*z.y+cycle+.35*sin(2.*cycle));
 z.y+=softness*.10*sin(3.7*z.x-cycle+.3*sin(cycle));
 return z+center;
}
vec3 pigmentMix(vec3 a,vec3 b,float weight,float edge){
 vec3 optical=sqrt(max(vec3(0.),mix(a*a,b*b,weight)));
 // Logarithmic pigment blending is continuous, including complementary hues.
 vec3 pigment=exp(mix(log(max(a,vec3(.018))),log(max(b,vec3(.018))),weight));
 float value=mix(max(a.r,max(a.g,a.b)),max(b.r,max(b.g,b.b)),weight);
 pigment*=value/max(.018,max(pigment.r,max(pigment.g,pigment.b)));
 return mix(optical,pigment,edge*(.44+.22*blend));
}
vec2 fieldAt(vec2 uv){
 vec4 p=texture(waterField,clamp(uv*fieldMapping.zw+fieldMapping.xy,vec2(0.),vec2(1.)));
 return vec2(p.r,dot(p.gb,vec2(65280.,255.))/65535.*2.-1.);
}
vec3 interact(vec2 uv){
 if(activity<.5||stir<=0.)return vec3(0.);
 float aspect=resolution.x/resolution.y;
 vec2 e=fieldTexel*2.,center=fieldAt(uv);
 vec2 gx=(fieldAt(uv+vec2(e.x,0.))-fieldAt(uv-vec2(e.x,0.)))/(2.*e.x*aspect);
 vec2 gy=(fieldAt(uv+vec2(0.,e.y))-fieldAt(uv-vec2(0.,e.y)))/(2.*e.y);
 vec2 gradV=vec2(gx.x,gy.x),gradH=vec2(gx.y,gy.y);
 float sigma=.055+radius*.16;
 // Recover local circulation from the retained field, never from cursor position.
 vec2 d=-gradV*sigma*sigma/(2.*max(center.x,.025));
 float angle=center.x*stir*envelope*gentle*3.1,c=cos(angle),s=sin(angle);
 vec2 offset=mat2(c,-s,s,c)*d-d;
 offset+=gradH*stir*envelope*gentle*.008;
 offset=clamp(offset,vec2(-.12),vec2(.12));
 float sheen=dot(gradH,vec2(-.5,.8))*stir*envelope*gentle*.010;
 return vec3(offset/vec2(aspect,1.),clamp(sheen,-.025,.025));
}
vec3 sheet(vec3 under,vec3 ink,float d,vec2 p,float id,float t){
 float softness=.015+blend*.095;
 float breathing=(motion*.013+circulation*.015)*sin(t+id+p.x*5.+p.y*3.);
 d+=breathing;
 float cover=1.-smoothstep(-softness,softness,d);
 float inner=1.-smoothstep(-.12,-.005,d);
 float boundary=exp(-abs(d)/(softness*1.5));
 vec2 orbit=motion*.13*vec2(cos(t+id),sin(t+id));
 float cloud=fbm(p*11.+vec2(id*7.3,2.9)+orbit);
 vec2 silk=vec2(p.x*7.+p.y*2.5,p.y*34.-p.x*3.5);
 float fine=fbm(silk+cloud*1.6+orbit);
 float folds=sin(d*(125.+detail*110.)+(cloud-.5)*6.+fine*2.);
 float veins=pow(.5+.5*folds,8.)*boundary;
 float opacity=mix(.64,.97,inner);
 vec3 body=ink*(.90+cloud*.19)+(fine-.5)*detail*.055;
 body+=vec3(.07,.08,.095)*relief*veins;
 vec3 col=pigmentMix(under,body,cover*opacity,boundary*circulation);
 // A translucent rolled shoulder, then a narrow lit lip: folded pigment film.
 float shoulder=exp(-pow((d+.037+(cloud-.5)*.025)/.025,2.));
 col=mix(col,sqrt(under*under*.40+ink*ink*.60),shoulder*cover*relief*.14);
 float crease=exp(-abs(d+.069+(cloud-.5)*.022)*260.);
 col*=1.-crease*relief*.035*cover;
 float gleam=exp(-abs(d+.056+(cloud-.5)*.022)*500.);
 col+=vec3(.06,.07,.08)*gleam*relief*cover;
 float lip=exp(-abs(d+.002)*660.);
 col=mix(col,ink*.67+vec3(.33),lip*relief*.045);
 float outer=exp(-abs(d-.012)*230.)*(1.-cover);
 col=mix(col,ink,outer*relief*.025);
 return col;
}
void main(){
 vec2 uv=qt_TexCoord0;
 // A periodic, area-preserving circulation gives different parts different speeds.
 float t=phase*TAU;
 vec3 waterMotion=interact(uv);
 vec2 centered=(uv+waterMotion.xy-.5)*vec2(resolution.x/resolution.y,1.);
 float spin=rotationPhase*TAU;
 centered=fluidCirculation(centered,spin,circulation);
 // The analytic pigment field extends outside the frame at every rotation angle.
 vec2 p=centered/vec2(1.82,1.)+.5;
 vec2 q=warp(p,t);
 q=eddy(q,vec2(.43,.64),.21,1.25+motion*.24*sin(t));
 q=eddy(q,vec2(.73,.81),.18,-.95+motion*.20*cos(t));
 q+=motion*.032*vec2(sin(t+q.y*4.),cos(t+q.x*4.));
 float clouds=fbm(q*7.+vec2(.018*cos(t),.018*sin(t))*motion);
 vec3 col=mix(vec3(.94,.98,1.),vec3(1.,1.,1.),smoothstep(.2,.9,clouds));
 float yellow=(.665+.065*sin(q.y*5.8+1.)-q.x)*1.25;
 yellow+=(fbm(q*8.1+4.5)-.48)*.055;
 vec3 amber=mix(vec3(.72,.89,.99),vec3(.91,.97,1.),smoothstep(-.1,.58,q.y));
 col=sheet(col,amber,yellow,q,1.,t);
 float gold=1.-smoothstep(.0,.22,-yellow);
 col+=vec3(.025,.04,.055)*(1.-gold)*.6;
 float purple=ellipse(q,vec2(-.025,.34),vec2(.40,.72),-.17);
 purple+=(fbm(q*10.+2.)-.5)*.044;
 vec3 violet=mix(vec3(.48,.74,.94),vec3(.62,.85,.99),smoothstep(.02,.68,q.y));
 col=sheet(col,violet,purple,q,2.,t);
 float blue=ellipse(q,vec2(.065,.94),vec2(.45,.55),-.40);
 blue+=(fbm(q*9.3+7.)-.5)*.055;
 col=sheet(col,vec3(.67,.85,.98),blue,q,3.,t);
 float cyan=ellipse(q,vec2(.39,1.13),vec2(.32,.56),.50);
 cyan+=(fbm(q*10.5+14.)-.5)*.045;
 col=sheet(col,vec3(.94,.985,1.),cyan,q,4.,t);
 float green=ellipse(q,vec2(.81,1.10),vec2(.40,.39),-.25);
 green+=(fbm(q*8.6+22.)-.5)*.045;
 col=sheet(col,vec3(.75,.91,1.),green,q,5.,t);
 float pink=ellipse(q,vec2(1.04,1.15),vec2(.25,.26),.3);
 col=sheet(col,vec3(.98,.99,1.),pink,q,6.,t);
 float luma=dot(col,vec3(.2126,.7152,.0722));
 col=mix(vec3(luma),col,saturation);
 col+=vec3(.80,.90,1.)*waterMotion.z;
 col+=(hash(uv*resolution)-.5)*.003;
 col=clamp(col,0.,1.);
 // Near-white ice blue in the light theme; retain the existing dark palette.
 col=mix(vec3(1.),col,mix(.25,1.,darkMode));
 col=mix(col,col*.18+vec3(.025,.040,.065),darkMode);
 fragColor=vec4(col,1.)*qt_Opacity;
}
