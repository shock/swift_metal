//
//  PixelShaders.metal
//  MetalGemini
//
//  Created by Gemini on 3/27/24.
//

#include <metal_stdlib>
using namespace metal;

//kernel void pixelShader(device float2 *coordinates [[buffer(0)]],
//                        texture2d<float, access::write> outputTexture [[texture(0)]],
//                        uint2 gid [[thread_position_in_grid]]) {
//    // Example: Color based on coordinates
//    float red = coordinates[gid.x].x / outputTexture.get_width();
//    float green = coordinates[gid.y].y / outputTexture.get_height();
//    float blue = 0.5;
//    outputTexture.write(float4(red, green, blue, 1.0), gid);
//}

struct ViewportSize {
    float width;
    float height;
};

struct VertexOut {
    float4 position [[position]];
};

vertex VertexOut vertexShader(uint vertexID [[vertex_id]]) {
    const float2 positions[6] = {
        {-1.0, -1.0},
        { 1.0, -1.0},
        {-1.0,  1.0},
        {-1.0,  1.0},
        { 1.0, -1.0},
        { 1.0,  1.0},
    };
    
    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    return out;
}

#define V2R(p,a) (cos(a)*p+sin(a)*float2(p.y,-p.x))

half4 ripple(float2 pos, float2 size, float time) {
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
    return half4(v, v2, v3, 1.);
}

#define pos vout.position.xy

fragment float4 fragmentShader0(VertexOut vout [[stage_in]],
                               constant float2& u_resolution [[buffer(0)]],
                               constant uint& u_frame [[buffer(1)]],
                               constant float& u_time [[buffer(2)]],
                               constant uint& u_pass [[buffer(3)]],
                               texture2d<float> buffer0 [[texture(0)]],
                               texture2d<float> buffer1 [[texture(1)]],
                               texture2d<float> buffer2 [[texture(2)]],
                               texture2d<float> buffer3 [[texture(3)]]
                               ) {
    
    if( u_pass == 0)
        return float4(ripple(pos, u_resolution, u_time));
    float4 pixelColor = buffer0.sample(sampler(mag_filter::linear, min_filter::linear), pos/u_resolution);
    //    return float4(ripple(pos, u_resolution, u_time));
    return pow(pixelColor,3.);

    // Now you can use 'u_frame' in your shader logic
    // Example usage: Creating a flashing effect based on the frame counter
    float flash = fract(float(u_frame) / 60.);
    if( pos.x < u_resolution.x / 2)
        flash = fract(u_time);
    
    return float4(flash, flash, flash, 1.0);
}

// fragment float4 fragmentShader(VertexOut vout [[stage_in]],
//                                constant ViewportSize& u_resolution [[buffer(0)]]) {
//     // You can now use u_resolution.width and u_resolution.height in your shader
//     // Example: computing a normalized position
//     float2 normalizedCoordinates = float2(vout.position.x / u_resolution.width, vout.position.y / u_resolution.height);
    
//     return float4(normalizedCoordinates, 1.0, 1.0); // Example usage
// }


fragment float4 pixelShader() {
    return float4(1, 1, 0, 1); // Draw every pixel red.
}

fragment float4 contrastFilter(VertexOut vout [[stage_in]],
                               constant float2& u_resolution [[buffer(0)]],
                               constant uint& u_frame [[buffer(1)]],
                               constant float& u_time [[buffer(2)]],
                               constant uint& u_pass [[buffer(3)]],
                               texture2d<float> buffer0 [[texture(0)]],
                               texture2d<float> buffer1 [[texture(1)]],
                               texture2d<float> buffer2 [[texture(2)]],
                               texture2d<float> buffer3 [[texture(3)]]
                               ) {
    float angle = u_time;
    float2 rpos = pos - u_resolution/2;
    rpos = V2R(rpos, angle);
    rpos += u_resolution/2;
    float4 pixelColor = buffer0.sample(sampler(mag_filter::linear, min_filter::linear), rpos/u_resolution);
    //    return float4(ripple(pos, u_resolution, u_time));
    return pow(pixelColor,1.8);
}
