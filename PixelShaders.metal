//
//  PixelShaders.metal
//  MetalGemini
//
//  Created by Gemini on 3/27/24.
//

#include <metal_stdlib>
using namespace metal;

kernel void pixelShader(device float2 *coordinates [[buffer(0)]],
                        texture2d<float, access::write> outputTexture [[texture(0)]],
                        uint2 gid [[thread_position_in_grid]]) {
    // Example: Color based on coordinates
    float red = coordinates[gid.x].x / outputTexture.get_width();
    float green = coordinates[gid.y].y / outputTexture.get_height();
    float blue = 0.5;
    outputTexture.write(float4(red, green, blue, 1.0), gid);
}
