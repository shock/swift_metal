//
//  PixelShaders.metal
//  MetalGemini
//
//  Created by Gemini on 3/27/24.
//

#include <metal_stdlib>
using namespace metal;

// this must be defined in every shader
struct SysUniforms { // DO NOT CHANGE
    float2 resolution;
    uint frame;
    float time;
    uint pass;
};

vertex float4 vertexShader(uint vertexID [[vertex_id]]) {
    const float2 positions[3] = {
        {-1.0, -1.0},
        { 3.0, -1.0},
        {-1.0,  3.0},
    };
    return float4(positions[vertexID], 0.0, 1.0);
}

// needed to convert from .rgba16Unorm to .bgra8Unorm
fragment float4 fragFinalPass(float4 frag_coord [[position]],
                                constant SysUniforms& sys_u [[buffer(0)]],
                                texture2d<float> buffer [[texture(0)]]
                               )
{
    float4 pixelColor = buffer.sample(sampler(mag_filter::linear, min_filter::linear), frag_coord.xy/sys_u.resolution);
    return pixelColor;
}

#define V2R(p,a) (cos(a)*p+sin(a)*float2(p.y,-p.x))

float4 ripple(float2 pos, float2 size, float time) {
    float angle = time;
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
    return float4(v, v2, v3, 1.);
}

fragment float4 fragmentShader0(float4 frag_coord [[position]],
                                constant SysUniforms& sys_u [[buffer(0)]],
                                texture2d<float> buffer0 [[texture(0)]],
                                texture2d<float> buffer1 [[texture(1)]],
                                texture2d<float> buffer2 [[texture(2)]],
                                texture2d<float> buffer3 [[texture(3)]]
                               )
{
    return float4(ripple(frag_coord.xy, sys_u.resolution, sys_u.time));
}

fragment float4 fragmentShader1(float4 frag_coord [[position]],
                                constant SysUniforms& sys_u [[buffer(0)]],
                               texture2d<float> buffer0 [[texture(0)]],
                               texture2d<float> buffer1 [[texture(1)]],
                               texture2d<float> buffer2 [[texture(2)]],
                               texture2d<float> buffer3 [[texture(3)]]
                               ) 
{
    float4 pixelColor = buffer0.sample(sampler(mag_filter::linear, min_filter::linear), frag_coord.xy/sys_u.resolution);
    return pow(pixelColor,3.);
}

fragment float4 fragmentShader2(float4 frag_coord [[position]],
                                constant SysUniforms& sys_u [[buffer(0)]],
                               texture2d<float> buffer0 [[texture(0)]],
                               texture2d<float> buffer1 [[texture(1)]],
                               texture2d<float> buffer2 [[texture(2)]],
                               texture2d<float> buffer3 [[texture(3)]]
                               ) 
{
    float4 pixelColor = buffer1.sample(sampler(mag_filter::linear, min_filter::linear), frag_coord.xy/sys_u.resolution);
    // vignetting
    float2 q = frag_coord.xy/sys_u.resolution.xy;
    pixelColor *= 0.1 + 0.9*pow(16.0*q.x*q.y*(1.0-q.x)*(1.0-q.y),0.15);

    return pow(pixelColor,3.);
}
