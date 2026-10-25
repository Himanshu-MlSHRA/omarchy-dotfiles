#version 440
// Samples the sheet, optionally rounds it into a window (rr corner radius,
// bs-px border), and cuts away every pixel that lies inside the island, so
// the sheet reads as pouring out from *under* the notch rather than being
// drawn across it.
layout(location = 0) in vec2 coord;
layout(location = 1) in vec2 pos;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float t;
    float tx;
    float tw;
    float ty;
    float w;
    float h;
    float ix;     // island body, in this item's coordinates (iw <= 0: no cut-out)
    float iw;
    float ih;     // island bottom edge y
    float ir;     // island bottom corner radius
    float bs;     // window border width (0: plain sheet)
    float rr;     // window corner radius (0: plain sheet)
    vec4 borderColor;
};
layout(binding = 1) uniform sampler2D source;

float roundBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

void main() {
    vec4 c;
    if (rr > 0.0 || bs > 0.0) {
        vec2 size = vec2(w, h);
        vec2 p = coord * size;
        vec2 hs = size * 0.5;
        float dOut = roundBox(p - hs, hs, rr + bs);
        float dIn = roundBox(p - hs, hs - bs, rr);
        // antialias in screen pixels, however hard the funnel squeezes
        float aaOut = max(fwidth(dOut), 0.0001);
        float aaIn = max(fwidth(dIn), 0.0001);
        vec4 tex = texture(source, (p - bs) / (size - 2.0 * bs));
        float inCov = clamp(0.5 - dIn / aaIn, 0.0, 1.0);
        float outCov = clamp(0.5 - dOut / aaOut, 0.0, 1.0);
        c = mix(borderColor, tex, inCov) * outCov;
    } else {
        c = texture(source, coord);
    }
    if (iw > 0.0) {
        // the island: flat top far above the screen, rounded bottom at y = ih
        float d = roundBox(pos - vec2(ix + iw * 0.5, ih - 4096.0), vec2(iw * 0.5, 4096.0), ir);
        c *= clamp(0.5 + d / max(fwidth(d), 0.0001), 0.0, 1.0);
    }
    fragColor = c * qt_Opacity;
}
