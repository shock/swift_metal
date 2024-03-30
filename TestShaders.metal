//
//  TestShaders.metal
//  MetalGemini
//
//  Created by Bill Doughty on 3/28/24.
//

#include <metal_stdlib>
using namespace metal;

#define SS(in) smoothstep(0.,1.,in)
#define SS4(in) SS(SS(SS(SS(in))))


#define V2R(p,a) (cos(a)*p+sin(a)*float2(p.y,-p.x))

float4 circles(float2 pos, float2 size, float time) {
    float angle = -time*2;
    float2 rpos1 = pos - size/2;
    rpos1 = V2R(rpos1, -angle);
    rpos1 += size/2;
    float2 rpos2 = pos - size/2;
    rpos2 = V2R(rpos2, angle);
    rpos2 += size/2;
    float2 c = size/2;
    float r_size = 2;
    float rate = 0.1;
    float2 c2 = c + 50;
    float2 c3 = c + float2(-70,10);
    float d = length(pos-c)/(10*r_size);
    float v = smoothstep(0.,1.,cos(d-time*rate*4.));
    v = v / 2 + 0.5;
    float d2 = length(rpos1-c2)/(20*r_size);
    float v2 = smoothstep(0.,1.,   cos(d2-time*rate*5.));
    v2 = v2 / 2 + 0.5;
    float d3 = length(rpos2-c3)/(30*r_size);
    float v3 = smoothstep(0.,1.,   cos(d3-time*rate*6.));
    v3 = v3 / 2 + 0.5;
    float4 color = float4(v, v2, v3, 1.);
    return color;
}

#define pos frag_coord.xy

fragment float4 fragmentShader0(float4 frag_coord [[position]],
                               constant float2& u_resolution [[buffer(0)]],
                               constant uint& u_frame [[buffer(1)]],
                               constant float& u_time [[buffer(2)]],
                               constant uint& u_pass [[buffer(3)]],
                               texture2d<float> buffer0 [[texture(0)]],
                               texture2d<float> buffer1 [[texture(1)]],
                               texture2d<float> buffer2 [[texture(2)]],
                               texture2d<float> buffer3 [[texture(3)]]
) {

    return float4(circles(pos, u_resolution, u_time*0.5));
}

fragment float4 fragmentShader1(float4 frag_coord [[position]],
                               constant float2& u_resolution [[buffer(0)]],
                               constant uint& u_frame [[buffer(1)]],
                               constant float& u_time [[buffer(2)]],
                               constant uint& u_pass [[buffer(3)]],
                               texture2d<float> buffer0 [[texture(0)]],
                               texture2d<float> buffer1 [[texture(1)]],
                               texture2d<float> buffer2 [[texture(2)]],
                               texture2d<float> buffer3 [[texture(3)]]
) {

    float4 pixelColor = buffer0.sample(sampler(mag_filter::linear, min_filter::linear), pos/u_resolution);
    return pow(pixelColor,10.);
}

fragment float4 fragmentShader2(float4 frag_coord [[position]],
                               constant float2& u_resolution [[buffer(0)]],
                               constant uint& u_frame [[buffer(1)]],
                               constant float& u_time [[buffer(2)]],
                               constant uint& u_pass [[buffer(3)]],
                               texture2d<float> buffer0 [[texture(0)]],
                               texture2d<float> buffer1 [[texture(1)]],
                               texture2d<float> buffer2 [[texture(2)]],
                               texture2d<float> buffer3 [[texture(3)]]
) {

    float4 pixelColor = buffer1.sample(sampler(mag_filter::linear, min_filter::linear), pos/u_resolution);
    return SS(pixelColor);
}

fragment float4 fragmentShader3(float4 frag_coord [[position]],
                               constant float2& u_resolution [[buffer(0)]],
                               constant uint& u_frame [[buffer(1)]],
                               constant float& u_time [[buffer(2)]],
                               constant uint& u_pass [[buffer(3)]],
                               texture2d<float> buffer0 [[texture(0)]],
                               texture2d<float> buffer1 [[texture(1)]],
                               texture2d<float> buffer2 [[texture(2)]],
                               texture2d<float> buffer3 [[texture(3)]]
) {

    // add ripples
    float speed = 0.1;
    float strength = 10;
    float frequency = 20;
    float2 normalizedPosition = pos / u_resolution;
    float moveAmount = u_time * speed;

    float2 ppos = pos.xy;
    ppos.x += sin((normalizedPosition.x + moveAmount) * frequency) * strength;
    ppos.y += cos((normalizedPosition.y + moveAmount) * frequency) * strength;

    float4 pixelColor = buffer2.sample(sampler(mag_filter::linear, min_filter::linear), ppos/u_resolution);

    // vignetting
    float2 q = frag_coord.xy/u_resolution.xy;
    pixelColor *= 0.05 + 0.95*pow(16.0*q.x*q.y*(1.0-q.x)*(1.0-q.y),0.15);

    return pixelColor;
}
