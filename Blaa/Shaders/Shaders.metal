#include <metal_stdlib>
#include <simd/simd.h>
#import "ShaderTypes.h"

using namespace metal;

// Camera's RGB vertex shader outputs
struct RGBVertexOut {
    float4 position [[position]];
    float2 texCoord;
};

struct MeshVertexIn {
    float4 position [[attribute(0)]];
    float4 normal [[attribute(1)]];
    float2 texCoords [[attribute(2)]];
    float4 color [[attribute(3)]];
};

struct MeshVertexOut {
    float4 position [[position]];
    float4 eyeNormal;
    float4 eyePos;
    float4 color;
    float2 texCoord;
};

// Particle vertex shader outputs and fragment shader inputs
struct ParticleVertexOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float4 color;
};

constexpr sampler colorSampler(mip_filter::linear, mag_filter::linear, min_filter::linear);
constant auto yCbCrToRGB = float4x4(float4(+1.0000f, +1.0000f, +1.0000f, +0.0000f),
                                    float4(+0.0000f, -0.3441f, +1.7720f, +0.0000f),
                                    float4(+1.4020f, -0.7141f, +0.0000f, +0.0000f),
                                    float4(-0.7010f, +0.5291f, -0.8860f, +1.0000f));
constant float2 viewVertices[] = { float2(-1, 1), float2(-1, -1), float2(1, 1), float2(1, -1) };
constant float2 viewTexCoords[] = { float2(0, 0), float2(0, 1), float2(1, 0), float2(1, 1) };

/// Retrieves the world position of a specified camera point with depth
static simd_float4 worldPoint(simd_float2 cameraPoint, float depth, matrix_float3x3 cameraIntrinsicsInversed, matrix_float4x4 localToWorld) {
    const auto localPoint = cameraIntrinsicsInversed * simd_float3(cameraPoint, 1) * depth;
    const auto worldPoint = localToWorld * simd_float4(localPoint, 1);
    
    return worldPoint / worldPoint.w;
}

///  Vertex shader that takes in a 2D grid-point and infers its 3D position in world-space, along with RGB and confidence
vertex void unprojectVertex(uint vertexID [[vertex_id]],
                            constant PointCloudUniforms &uniforms [[buffer(kPointCloudUniforms)]],
                            device ParticleUniforms *particleUniforms [[buffer(kParticleUniforms)]],
                            constant float2 *gridPoints [[buffer(kGridPoints)]],
                            texture2d<float, access::sample> capturedImageTextureY [[texture(kTextureY)]],
                            texture2d<float, access::sample> capturedImageTextureCbCr [[texture(kTextureCbCr)]],
                            texture2d<float, access::sample> depthTexture [[texture(kTextureDepth)]],
                            texture2d<unsigned int, access::sample> confidenceTexture [[texture(kTextureConfidence)]]) {
    
    const auto gridPoint = gridPoints[vertexID];
    const auto currentPointIndex = (uniforms.pointCloudCurrentIndex + vertexID) % uniforms.maxPoints;
    const auto texCoord = gridPoint / uniforms.cameraResolution;
    // Sample the depth map to get the depth value
    const auto depth = depthTexture.sample(colorSampler, texCoord).r;
    // With a 2D point plus depth, we can now get its 3D position
    const auto position = worldPoint(gridPoint, depth, uniforms.cameraIntrinsicsInversed, uniforms.localToWorld);
    const auto pointNormal = normalize((position - uniforms.cameraPosition).xyz);
    
    //    // Sample Y and CbCr textures to get the YCbCr color at the given texture coordinate
    const auto ycbcr = float4(capturedImageTextureY.sample(colorSampler, texCoord).r, capturedImageTextureCbCr.sample(colorSampler, texCoord.xy).rg, 1);
    const auto sampledColor = (yCbCrToRGB * ycbcr).rgb;
    // Sample the confidence map to get the confidence value
    const auto confidence = confidenceTexture.sample(colorSampler, texCoord).r;
    
    // Write the data to the buffer
    particleUniforms[currentPointIndex].position = position.xyz;
    particleUniforms[currentPointIndex].normal = pointNormal;
    particleUniforms[currentPointIndex].color = sampledColor;
    particleUniforms[currentPointIndex].confidence = confidence;
}

vertex RGBVertexOut rgbVertex(uint vertexID [[vertex_id]],
                              constant RGBUniforms &uniforms [[buffer(0)]]
                              ) {
    const float3 texCoord = float3(viewTexCoords[vertexID], 1) * uniforms.viewToCamera;
    
    RGBVertexOut out;
    out.position = float4(viewVertices[vertexID], 0, 1);
    out.texCoord = texCoord.xy;
    
    return out;
}

fragment float4 yCbCrtoRGBFragment(RGBVertexOut in [[stage_in]],
                                   constant RGBUniforms &uniforms [[buffer(0)]],
                                   texture2d<float, access::sample> capturedImageTextureY [[texture(kTextureY)]],
                                   texture2d<float, access::sample> capturedImageTextureCbCr [[texture(kTextureCbCr)]]
                                   ) {
    const float4 ycbcr = float4(capturedImageTextureY.sample(colorSampler, in.texCoord.xy).r, capturedImageTextureCbCr.sample(colorSampler, in.texCoord.xy).rg, 1);
    const float3 sampledColor = (yCbCrToRGB * ycbcr).rgb;
    return float4(sampledColor * .5, 1.0);
}

fragment float4 rgbFragmentHalfOpacity(RGBVertexOut in [[stage_in]],
                                       constant RGBUniforms &uniforms [[buffer(0)]],
                                       texture2d<float, access::sample> imageTextureBGRA [[texture(0)]]
                                       ) {
    float3 sampledColor = imageTextureBGRA.sample(colorSampler, in.texCoord.xy).rgb;
    return float4(sampledColor * .5, 1.0);
}

vertex ParticleVertexOut particleVertex(uint vertexID [[vertex_id]],
                                        constant PointCloudUniforms &uniforms [[buffer(kPointCloudUniforms)]],
                                        constant ParticleUniforms *particleUniforms [[buffer(kParticleUniforms)]]) {
    
    // get point data
    const auto particleData = particleUniforms[vertexID];
    const auto position = particleData.position;
    const auto confidence = particleData.confidence;
    const auto sampledColor = particleData.color;
    const auto visibility = confidence >= uniforms.confidenceThreshold;
    
    // animate and project the point
    float4 projectedPosition = uniforms.projectionMatrix * uniforms.viewMatrix * float4(position, 1.0);
    const float pointSize = max(uniforms.particleSize / max(1.0, projectedPosition.z), 2.0);
    projectedPosition /= projectedPosition.w;
    
    // prepare for output
    ParticleVertexOut out;
    out.position = projectedPosition;
    out.pointSize = pointSize;
    out.color = float4(sampledColor, visibility);
    
    return out;
}

bool lessThan(float3 a, float3 b) {
    return a.x < b.x && a.y < b.y && a.z < b.z;
}

vertex ParticleVertexOut particleVertexLimited(uint vertexID [[vertex_id]],
                                               constant PointCloudUniforms &uniforms [[buffer(kPointCloudUniforms)]],
                                               constant ParticleUniforms *particleUniforms [[buffer(kParticleUniforms)]],
                                               constant Box &boundingBox [[buffer(kBoundingBox)]]) {
    
    // get point data
    const auto particleData = particleUniforms[vertexID];
    const auto position = particleData.position;
    const auto confidence = particleData.confidence;
    const auto sampledColor = particleData.color;
    const bool visibility = confidence >= uniforms.confidenceThreshold &&
    lessThan(boundingBox.boxMin, position) && lessThan(position, boundingBox.boxMax);
    
    // animate and project the point
    float4 projectedPosition = uniforms.projectionMatrix * uniforms.viewMatrix * float4(position, 1.0);
    const float pointSize = max(uniforms.particleSize / max(1.0, projectedPosition.z), 2.0);
    projectedPosition /= projectedPosition.w;
    
    // prepare for output
    ParticleVertexOut out;
    out.position = projectedPosition;
    out.pointSize = pointSize;
    out.color = float4(sampledColor, visibility);
    
    return out;
}

fragment float4 particleFragment(ParticleVertexOut in [[stage_in]],
                                 const float2 coords [[point_coord]]) {
    return in.color;
}

vertex MeshVertexOut wireVert(MeshVertexIn in [[stage_in]],
                              constant PointCloudUniforms &uniforms [[buffer(1)]],
                              uint vertexId [[vertex_id]]
                              ) {
    MeshVertexOut out;
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * uniforms.modelMatrix * in.position;
    out.color = float4(1);
    out.eyeNormal = uniforms.viewMatrix * uniforms.modelMatrix * in.normal;
    out.eyePos = uniforms.viewMatrix * uniforms.modelMatrix * in.position;
    out.texCoord = in.texCoords;
    
    return out;
}

fragment float4 wireFrag(MeshVertexOut in [[stage_in]],
                         //                                  texture2d<float, access::sample> imageTextureBGRA [[texture(0)]],
                         const float2 coords [[point_coord]]) {
    return in.color;
}
