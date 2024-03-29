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
constant float3 lumCoeff = float3(0.2126, 0.7152, 0.0722);

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
                            texture2d<unsigned int, access::sample> confidenceTexture [[texture(kTextureConfidence)]]
                            ) {
    
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

fragment float4 rgbFragmentFullOpacity(RGBVertexOut in [[stage_in]],
                                       constant RGBUniforms &uniforms [[buffer(0)]],
                                       texture2d<float, access::sample> imageTextureBGRA [[texture(0)]]
                                       ) {
    float3 sampledColor = imageTextureBGRA.sample(colorSampler, in.texCoord.xy).rgb;
    return float4(sampledColor, 1.0);
}

// MARK: - Particles

#define PointSize 8

vertex ParticleVertexOut particleVertex(uint vertexID [[vertex_id]],
                                        constant PointCloudUniforms &uniforms [[buffer(kPointCloudUniforms)]],
                                        constant ParticleUniforms *particleUniforms [[buffer(kParticleUniforms)]]) {
    
    // get point data
    const auto particleData = particleUniforms[vertexID];
    const auto position = particleData.position;
    const auto confidence = particleData.confidence;
    const float3 sampledColor = particleData.color;
    const auto visibility = confidence >= uniforms.confidenceThreshold;
    
    // animate and project the point
    float4 projectedPosition = uniforms.viewProjectionMatrix * float4(position, 1.0);
    const float pointSize = max(PointSize / max(1.0, projectedPosition.z), 2.0);
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
    const float3 color = particleData.color;
    const bool visibility = confidence >= uniforms.confidenceThreshold && lessThan(boundingBox.boxMin, position) && lessThan(position, boundingBox.boxMax);
    
    // animate and project the point
    float4 projectedPosition = uniforms.viewProjectionMatrix * float4(position, 1.0);
    projectedPosition /= projectedPosition.w;
    
    // prepare for output
    ParticleVertexOut out;
    out.position = projectedPosition;
    out.pointSize = PointSize;
    out.color = float4(color, visibility);
    
    return out;
}

fragment float4 particleFragment(ParticleVertexOut in [[stage_in]],
                                 const float2 coords [[point_coord]]) {
    return in.color;
}

// MARK: - 3d Model Wireframe

vertex MeshVertexOut modelVert(MeshVertexIn in [[stage_in]],
                               constant PointCloudUniforms &uniforms [[buffer(1)]]) {
    MeshVertexOut out;
    out.position = uniforms.viewProjectionMatrix * in.position;
    out.texCoord = in.texCoords;
    
    return out;
}

fragment float4 wireFrag(MeshVertexOut in [[stage_in]],
                         const float2 coords [[point_coord]]) {
    return float4(1);
}

// MARK: - UV Export

vertex MeshVertexOut UVMapVert(MeshVertexIn in [[stage_in]]) {
    MeshVertexOut out;
    out.position = float4(in.texCoords * 2 - 1.0, 0, 1);
    out.color = in.color;
    out.texCoord = in.texCoords;
    return out;
}

fragment float4 UVMapFrag(MeshVertexOut in [[stage_in]],
                          const float2 coords [[point_coord]]) {
    return float4(in.color.rgb * 0.5, 1);
}


// MARK: - Tattoo Sim

#define Vibrance -.1

float3 multiply(float3 a, float3 b) {
    return a*b;
}

float3 screen(float3 a, float3 b) {
    return 1 - (1 - a) * (1 - b);
}

float4 toneDown(float4 sketch) {
    float4 color = sketch;
    float luma = dot(lumCoeff, color.rgb);
    
    float maxColor = max(max(color.r,color.g),color.b);
    float minColor = min(min(color.r,color.g),color.b);
    
    float colorSaturation = maxColor - minColor;
    
    color = mix(luma, color, (1.0 + (Vibrance * (1.0 - (sign(Vibrance) * colorSaturation)))));
    color.a = pow(color.a, 1-colorSaturation);
    return color;
}

float3 deSat(float3 in, float blend) {
    float luma = dot(lumCoeff, in);
    return mix(luma, in, blend);
}

fragment float4 sketchFrag(MeshVertexOut in [[stage_in]],
                           texture2d<float, access::sample> cameraImage [[texture(0)]],
                           texture2d<float, access::sample> sketch [[texture(2)]],
                           texture2d<float, access::sample> depthTex [[texture(1)]],
                           constant PointCloudUniforms &uniforms [[buffer(1)]]
                           ) {
    float2 sampleSpot = float2(
                               in.position.y / uniforms.cameraResolution.y,
                               1 - in.position.x / uniforms.cameraResolution.x
                               );
    float4 sketchColor = sketch.sample(colorSampler, in.texCoord);
    if (sketchColor.a > 0) {
        float depth = depthTex.sample(colorSampler, sampleSpot).r;
        if (depth < in.position.z) {
            return float4(0);
        }
        float4 cameraColor = cameraImage.sample(colorSampler, sampleSpot);
        float4 mixed = toneDown(sketchColor);
        float3 mixRGB = multiply(mixed.rgb, float3(cameraColor.r));
        mixRGB = screen(mixRGB, float3(pow(cameraColor.b, 2.2)));
        return float4(mixRGB, mixed.a);
    } else {
        return float4(0);
    }
}

// MARK: - Depth Video

#define depth_limit 5.0

fragment float4 encodeDepth(RGBVertexOut in [[stage_in]],
                            texture2d<float, access::sample> depthIn [[texture(0)]]) {
    float depth = depthIn.sample(colorSampler, in.texCoord.yx).r / depth_limit;
    depth = round(depth * 1529.0);
    int dnorm = int(depth);
    float3 col = float3(0);
    if(dnorm <= 255) {
        col.b = 255;
        col.g = dnorm;
        col.r = 0;
    } else if (255 < dnorm && dnorm <= 510) {
        col.b = 255 - dnorm;
        col.g = 255;
        col.r = 0;
    } else if (510 < dnorm && dnorm <= 765) {
        col.b = 0;
        col.g = 765 - dnorm;
        col.r = 0;
    } else if (765 < dnorm && dnorm <= 1020) {
        col.b = 0;
        col.g = 0;
        col.r = dnorm - 765;
    } else if (1020 < dnorm && dnorm <= 1275) {
        col.b = dnorm - 1020;
        col.g = 0;
        col.r = 255;
    } else if (1275 < dnorm) {
        col.b = 255;
        col.g = 0;
        col.r = 1529 - dnorm;
    } else if (1529 < dnorm) {
        col.b = 255;
        col.g = 0;
        col.r = 0;
    }
    col /= 256.0;
    return float4(col, 1);
}

kernel void decodeDepth(texture2d<float, access::sample> rgbIn [[texture(0)]],
                        texture2d<float, access::write> depthOut [[texture(1)]],
                        uint2 pos [[ thread_position_in_grid ]]
                        ) {
    float3 c = rgbIn.read(pos).rgb * 256.0;
    float dnorm = 0.;
    if (c.b >= c.g && c.b >= c.r && c.g >= c.r) {
        dnorm = c.g - c.r;
    } else if (c.b >= c.g && c.b >= c.r && c.g < c.r) {
        dnorm = c.g - c.r + 1529;
    } else if (c.g >= c.b && c.g >= c.r) {
        dnorm = c.r - c.b + 510;
    } else if (c.r >= c.g && c.r >= c.b) {
        dnorm = c.b - c.g + 1020;
    }
    float d = depth_limit * dnorm / 1529.0;
    depthOut.write(d, pos);
    //    return out;
}
