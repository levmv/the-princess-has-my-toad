#version 330
layout(location=0) in vec3 vertexPosition;
layout(location=1) in vec2 vertexTexCoord;
layout(location=2) in vec3 vertexNormal;
layout(location=3) in vec4 vertexColor;
layout(location=4) in mat4 instanceTransform;
layout(location=8) in vec4 instanceNormalX;
layout(location=9) in vec4 instanceNormalY;
layout(location=10) in vec4 instanceNormalZ;
layout(location=11) in vec4 instanceTint;
layout(location=12) in vec4 skinWeights;
uniform mat4 mvp;
uniform int instanced;
uniform int skinned;
uniform mat4 bones[17];
uniform float skinFlash;
out vec3 worldPosition;
out vec3 worldNormal;
out vec4 tint;
out vec2 surfaceData;
out vec3 surfacePosition;
out vec3 surfaceNormal;
void main() {
    surfaceData = vertexTexCoord;
    surfacePosition = vertexPosition;
    surfaceNormal = vertexNormal;
    if (skinned != 0) {
        mat4 skin = bones[int(skinWeights.x)] * skinWeights.z
                  + bones[int(skinWeights.y)] * skinWeights.w;
        worldPosition = (skin * vec4(vertexPosition, 1.0)).xyz;
        worldNormal = mat3(skin) * vertexNormal;
        tint = vec4(mix(vertexColor.rgb, vec3(0.70, 0.86, 0.85), skinFlash), vertexColor.a);
    } else if (instanced != 0) {
        worldPosition = (instanceTransform * vec4(vertexPosition, 1.0)).xyz;
        worldNormal = mat3(instanceNormalX.xyz, instanceNormalY.xyz, instanceNormalZ.xyz) * vertexNormal;
        tint = instanceTint * vertexColor;
        // Object-space grain moves with the object. Scale keeps small props
        // and stretched beams at a comparable physical texel density.
        vec3 scale = vec3(length(instanceTransform[0].xyz),
                          length(instanceTransform[1].xyz),
                          length(instanceTransform[2].xyz));
        surfacePosition *= scale;
        surfaceNormal /= max(scale, vec3(0.00001));
        if (instanceNormalX.w >= 0.0) surfaceData.y = instanceNormalX.w;
    } else {
        worldPosition = vertexPosition;
        worldNormal = vertexNormal;
        tint = vertexColor;
    }
    gl_Position = mvp * vec4(worldPosition, 1.0);
}
