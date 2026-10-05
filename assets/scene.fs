#version 330
in vec3 worldPosition;
in vec3 worldNormal;
in vec4 tint;
in vec2 surfaceData;
in vec3 surfacePosition;
in vec3 surfaceNormal;
uniform vec3 eye;
uniform sampler2D grain;
uniform sampler2D shadowMap;
uniform mat4 lightVP;
uniform int bakedScene;
uniform int lightCount;
uniform vec4 lightPosition[12];
uniform vec4 lightColor[12];
out vec4 finalColor;

float shadowVisibility(vec3 position, vec3 normal, vec3 sunDirection) {
    vec4 projected = lightVP * vec4(position + normal * 0.05, 1.0);
    vec3 uvz = projected.xyz / projected.w * 0.5 + 0.5;
    if (any(lessThan(uvz, vec3(0.001))) || any(greaterThan(uvz, vec3(0.999)))) return 1.0;
    float bias = 0.00016 + 0.0004 * (1.0 - max(dot(normal, sunDirection), 0.0));
    float visibility = 0.0;
    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            vec3 packedDepth = texture(shadowMap, uvz.xy + vec2(x, y) / 2048.0).rgb;
            float depth = dot(packedDepth, vec3(1.0, 1.0/255.0, 1.0/65025.0));
            visibility += step(uvz.z - bias, depth);
        }
    }
    return visibility / 9.0;
}

void main() {
    vec3 n = normalize(worldNormal + vec3(0.000001));
    vec3 viewDirection = normalize(eye - worldPosition);
    vec3 weights = pow(abs(normalize(surfaceNormal)), vec3(6.0));
    weights /= max(dot(weights, vec3(1.0)), 0.0001);
    vec3 p = surfacePosition;
    vec4 grainValue = texture(grain, p.zy * 0.22).rgba * weights.x
                    + texture(grain, p.xz * 0.22).rgba * weights.y
                    + texture(grain, p.xy * 0.22).rgba * weights.z;
    vec4 detail = texture(grain, p.zy * 2.4).rgba * weights.x
                + texture(grain, p.xz * 2.4).rgba * weights.y
                + texture(grain, p.xy * 2.4).rgba * weights.z;
    float material = surfaceData.y;
    float ao = bakedScene != 0 ? surfaceData.x : 1.0;
    bool luminous = material > 2.5 && material < 3.5;
    float emission = luminous ? 1.0 : 0.0;
    // Broad stains, fine pits and directional wear come from one small,
    // mipmapped packed texture. No screen-space noise or colour-based glow.
    float stain = smoothstep(0.38, 0.72, grainValue.r);
    float pits = smoothstep(0.60, 0.82, detail.a);
    vec3 albedo = tint.rgb * (0.69 + grainValue.r * 0.50 + detail.g * 0.10);
    float gloss = 0.023;
    float relief = 0.0016;
    if (material < 0.5 || (material > 1.5 && material < 2.5)) {
        float worn = smoothstep(0.52, 0.69, grainValue.a) * smoothstep(0.40, 0.66, detail.r);
        albedo = mix(albedo, vec3(0.19, 0.145, 0.105), worn * 0.20);
        albedo *= 0.84 + 0.22 * detail.b;
        gloss = material > 1.5 ? 0.045 : 0.025;
    } else if (material < 1.5) {
        // Dry ceramic/aggregate, not shiny marble or a square tile grid.
        albedo *= 0.86 + 0.18 * detail.g;
        albedo = mix(albedo, albedo * vec3(0.62, 0.64, 0.60), stain * 0.15 + pits * 0.08);
        gloss = 0.009;
    } else if (material > 4.5 && material < 5.5) {
        albedo = mix(tint.rgb * vec3(0.94, 0.90, 0.90), tint.rgb * 1.025, smoothstep(0.25, 0.70, detail.r));
        albedo *= 0.96 + grainValue.g * 0.075;
        gloss = 0.015;
        relief = 0.0006;
    } else if (material > 5.5 && material < 6.5) {
        albedo *= 0.78 + detail.b * 0.33;
        gloss = 0.003;
        relief = 0.0008;
    } else if (material > 6.5) {
        albedo *= 0.82 + detail.r * 0.25;
        gloss = 0.012;
        relief = 0.0007;
    }
    if (material > 3.5 && material < 4.5) {
        // Copper lanes and small pads under the solder mask. World-space,
        // antialiased with derivatives; no large texture or per-frame generation.
        vec2 p = surfacePosition.xz;
        // Continuous diagonal bends connect the parallel traces across rows.
        float row = p.y * 0.17;
        float bend = (floor(row) + clamp(fract(row)*4.0-1.5, 0.0, 1.0))*0.25;
        float track = abs(fract(p.x * 0.42 + bend) - 0.5);
        float aa = max(fwidth(track), 0.002);
        float lane = 1.0 - smoothstep(0.018, 0.018 + aa, track);
        vec2 cell = fract(vec2(p.x*0.42+bend, p.y*0.34)) - 0.5;
        float pad = 1.0 - smoothstep(0.072, 0.072 + max(fwidth(length(cell)), 0.005), length(cell));
        float copper = max(lane * 0.52, pad) * pow(abs(n.y), 8.0);
        albedo = mix(albedo, vec3(0.55, 0.43, 0.20), copper);
        gloss = 0.025 + copper * 0.035;
    }
    // Surface-gradient bump uses derivatives of the existing samples. The
    // silhouette stays faceted; the small relief breaks uniform flat lighting.
    vec3 dx = dFdx(worldPosition), dy = dFdy(worldPosition);
    vec3 tx = cross(dy, n), ty = cross(n, dx);
    float determinant = dot(dx, tx);
    float height = detail.g * relief;
    vec3 gradient = sign(determinant) * (dFdx(height) * tx + dFdy(height) * ty);
    n = normalize(abs(determinant) * n - gradient + n * 0.0000001);
    vec3 sunDirection = normalize(vec3(-0.45, 0.8, 0.35));
    float sunlight = max(dot(n, sunDirection), 0.0);
    float shadow = shadowVisibility(worldPosition, n, sunDirection);
    vec3 ambient = mix(vec3(0.105, 0.13, 0.18), vec3(0.25, 0.32, 0.39), n.y*0.5+0.5) * ao;
    // Small cool fill keeps moving silhouettes legible in dark service rooms.
    // Geometry still occludes them normally; architecture keeps its baked AO.
    if (bakedScene == 0) {
        float rim = pow(1.0-max(dot(n, viewDirection), 0.0), 2.0);
        ambient += vec3(0.075, 0.10, 0.13)*(0.55+rim);
    }
    vec3 lighting = ambient + vec3(1.48, 1.23, 0.89) * sunlight * shadow;
    float specular = pow(max(dot(n, normalize(sunDirection+viewDirection)), 0.0), 12.0) * gloss * shadow;
    vec3 highlights = vec3(1.0, 0.88, 0.66)*specular;
    for (int i = 0; i < lightCount; ++i) {
        vec3 delta = lightPosition[i].xyz-worldPosition;
        float distanceSquared = dot(delta, delta);
        float radius = lightPosition[i].w;
        if (distanceSquared >= radius*radius) continue;
        float distanceToLight = sqrt(distanceSquared);
        float attenuation = max(0.0, 1.0-distanceToLight/lightPosition[i].w);
        attenuation *= attenuation;
        vec3 direction = delta/max(distanceToLight, 0.001);
        vec3 radiance = lightColor[i].rgb * lightColor[i].a * attenuation;
        lighting += radiance * max(dot(n, direction), 0.0);
        highlights += radiance * pow(max(dot(n, normalize(direction+viewDirection)), 0.0), 12.0)*gloss;
    }
    vec3 color = albedo*lighting + highlights;
    color = mix(color, tint.rgb*2.2, emission);
    color = vec3(1.0)-exp(-color*1.18);
    float distanceFog = 1.0-exp(-length(worldPosition-eye)*0.008);
    float depthFog = (1.0-smoothstep(-42.0, -4.0, worldPosition.y))*0.65;
    color = mix(color, vec3(0.048, 0.085, 0.12), min(0.94, distanceFog+depthFog));
    finalColor = vec4(color, tint.a);
}
