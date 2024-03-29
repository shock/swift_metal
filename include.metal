//
// File: include.metal
//

float4 SS( float4 in ) {
  return smoothstep(0.,1.,in);
}