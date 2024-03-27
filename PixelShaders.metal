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

fragment float4 fragmentShader(VertexOut vout [[stage_in]],
                               constant ViewportSize& u_resolution [[buffer(0)]],
                               constant uint& u_frame [[buffer(1)]],
                               constant float& u_time [[buffer(2)]]) {
    // Now you can use 'u_frame' in your shader logic
    // Example usage: Creating a flashing effect based on the frame counter
    float flash = fract(float(u_frame) / 60.);
    float4 pos = vout.position;
    if( pos.x < u_resolution.width / 2)
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

