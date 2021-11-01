/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Types and enums that are shared between shaders and the host app code.
*/

#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

enum TextureIndices {
    kTextureY = 0,
    kTextureCbCr = 1,
    kTextureDepth = 2,
    kTextureConfidence = 3,
    kTextureRGB = 3,
};

enum BufferIndices {
    kPointCloudUniforms = 0,
    kParticleUniforms = 1,
    kModelVertices = 1,
    kGridPoints = 2,
    kBoundingBox = 2,
};

struct RGBUniforms {
    matrix_float3x3 viewToCamera;
    float viewRatio;
};

struct Box {
    simd_float3 boxMin;
    simd_float3 boxMax;
};

struct PointCloudUniforms {
    matrix_float4x4 viewMatrix;
    matrix_float4x4 projectionMatrix;
    matrix_float4x4 localToWorld;
    matrix_float3x3 cameraIntrinsicsInversed;
    simd_float2 cameraResolution;
    simd_float4 cameraPosition;
    
    float particleSize;
    int maxPoints;
    int pointCloudCurrentIndex;
    int confidenceThreshold;
};

struct ParticleUniforms {
    simd_float3 position;
    simd_float3 normal;
    simd_float3 color;
    float confidence;
};

#endif /* ShaderTypes_h */
