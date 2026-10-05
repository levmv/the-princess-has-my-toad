#version 330
out vec4 finalColor;
void main() {
    // A 24-bit packed depth texture works with raylib's ordinary render targets.
    float depth = min(gl_FragCoord.z, 0.9999999);
    vec3 packedDepth = fract(depth * vec3(1.0, 255.0, 65025.0));
    packedDepth -= packedDepth.yzz * vec3(1.0/255.0, 1.0/255.0, 0.0);
    finalColor = vec4(packedDepth, 1.0);
}
