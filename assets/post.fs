#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
uniform sampler2D texture0;
uniform vec2 resolution;
uniform float damageFlash;
out vec4 finalColor;
void main() {
    vec2 uv = fragTexCoord;
    vec3 color = texture(texture0, uv).rgb;
    // Edge-adaptive antialiasing for the offscreen world; UI is drawn afterwards.
    vec2 texel = 1.0 / resolution;
    vec3 nw = texture(texture0, uv + vec2(-1.0, -1.0) * texel).rgb;
    vec3 ne = texture(texture0, uv + vec2( 1.0, -1.0) * texel).rgb;
    vec3 sw = texture(texture0, uv + vec2(-1.0,  1.0) * texel).rgb;
    vec3 se = texture(texture0, uv + vec2( 1.0,  1.0) * texel).rgb;
    vec3 weights = vec3(0.299, 0.587, 0.114);
    float m = dot(color, weights);
    float a = dot(nw, weights), b = dot(ne, weights);
    float c = dot(sw, weights), d = dot(se, weights);
    float low = min(m, min(min(a, b), min(c, d)));
    float high = max(m, max(max(a, b), max(c, d)));
    if (high - low > max(0.035, high * 0.12)) {
        vec2 direction = vec2(c + d - a - b, a + c - b - d);
        float reduction = max((a + b + c + d) * 0.03125, 0.0078125);
        direction = clamp(direction / (min(abs(direction.x), abs(direction.y)) + reduction), -8.0, 8.0) * texel;
        vec3 narrow = 0.5 * (texture(texture0, uv - direction / 6.0).rgb + texture(texture0, uv + direction / 6.0).rgb);
        vec3 wide = narrow * 0.5 + 0.25 * (texture(texture0, uv - direction * 0.5).rgb + texture(texture0, uv + direction * 0.5).rgb);
        float luma = dot(wide, weights);
        color = (luma < low || luma > high) ? narrow : wide;
    }
    vec2 px = 2.0 / resolution;
    vec3 glow = vec3(0.0);
    glow += max(texture(texture0, uv + vec2(px.x, 0.0)).rgb - 0.68, 0.0);
    glow += max(texture(texture0, uv - vec2(px.x, 0.0)).rgb - 0.68, 0.0);
    glow += max(texture(texture0, uv + vec2(0.0, px.y)).rgb - 0.68, 0.0);
    glow += max(texture(texture0, uv - vec2(0.0, px.y)).rgb - 0.68, 0.0);
    color += glow * 0.15;
    vec2 edge = uv * (1.0 - uv);
    float vignette = clamp(pow(edge.x * edge.y * 16.0, 0.18), 0.0, 1.0);
    color *= mix(0.70, 1.0, vignette);
    color = pow(max(color, 0.0), vec3(0.96));
    // Keep the aiming area clear; a fast red edge hit decays with the real damage event.
    float border = 1.0 - smoothstep(0.0, 0.23, min(min(uv.x, 1.0-uv.x), min(uv.y, 1.0-uv.y)));
    color = mix(color, vec3(0.62, 0.015, 0.025), border * damageFlash * 0.72);
    finalColor = vec4(color, 1.0);
}
