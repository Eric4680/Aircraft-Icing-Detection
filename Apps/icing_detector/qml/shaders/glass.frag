#version 440
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 sampleRect;
    vec2 paneSize;
    vec2 backdropSize;
    vec4 glassTint;
    float weight;
    float cornerRadius;
};
layout(binding=1) uniform sampler2D backdrop;
void main() {
    vec2 uv=sampleRect.xy+qt_TexCoord0*sampleRect.zw;
    vec2 d=vec2(18.)/max(backdropSize,vec2(1.));
    vec3 col=texture(backdrop,uv).rgb*.25;
    col+=(texture(backdrop,uv+vec2(d.x,0.)).rgb+texture(backdrop,uv-vec2(d.x,0.)).rgb
         +texture(backdrop,uv+vec2(0.,d.y)).rgb+texture(backdrop,uv-vec2(0.,d.y)).rgb)*.125;
    col+=(texture(backdrop,uv+d).rgb+texture(backdrop,uv-d).rgb
         +texture(backdrop,uv+vec2(d.x,-d.y)).rgb+texture(backdrop,uv+vec2(-d.x,d.y)).rgb)*.0625;
    col=mix(col,glassTint.rgb,weight);
    vec2 q=abs((qt_TexCoord0-.5)*paneSize)-paneSize*.5+cornerRadius;
    float distance=length(max(q,vec2(0.)))+min(max(q.x,q.y),0.)-cornerRadius;
    float alpha=1.-smoothstep(-.6,.6,distance);
    fragColor=vec4(col*alpha,alpha)*qt_Opacity;
}
