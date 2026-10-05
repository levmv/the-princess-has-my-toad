#version 330
in vec2 fragTexCoord;
uniform sampler2D texture0;
uniform vec3 skyForward;
uniform vec3 skyRight;
uniform vec3 skyUp;
uniform vec2 skyScale;
uniform vec4 skyRefresh;
out vec4 finalColor;
void main() {
    vec2 p = (fragTexCoord * 2.0 - 1.0) * skyScale;
    vec3 direction = normalize(skyForward + skyRight * p.x - skyUp * p.y);
    vec2 uv = vec2(atan(direction.z, direction.x) / 6.2831853 + 0.5,
                   asin(clamp(direction.y, -1.0, 1.0)) / 3.14159265 + 0.5);
    vec3 color = texture(texture0, uv).rgb;
    if (skyRefresh.x > 0.001) {
        float u = fract(uv.x + skyRefresh.z);
        float travel = exp(-pow((u - skyRefresh.y) * 4.0, 2.0));
        float zigzag = abs(fract(u * 37.0) - 0.5) * 0.016;
        float path = 0.59 + sin(u * 19.0) * 0.038 + zigzag;
        float d = abs(uv.y - path);
        float fork = abs(uv.y - path - (u - 0.45) * 0.20);
        float branch = exp(-fork * 550.0) * smoothstep(0.45, 0.49, u) * (1.0 - smoothstep(0.66, 0.70, u));
        float arc = exp(-d * 900.0) + exp(-d * 95.0) * 0.18 + branch * 0.55;
        color += vec3(0.25, 0.66, 1.0) * arc * travel * skyRefresh.x;
    }
    finalColor = vec4(color, 1.0);
}
