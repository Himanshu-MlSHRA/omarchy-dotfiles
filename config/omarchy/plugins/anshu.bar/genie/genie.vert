#version 440
// macOS-Dock "genie", ported from ~/Work/Portfolio/src/features/resume/Resume.tsx.
// t: 0 = inside the mouth (the island), 1 = lying open. The edge nearest the
// mouth is pinched to the mouth's width, then the sheet is drawn through the
// funnel, gathering speed. Lengths are in the item's own pixels; the mouth
// (tx, ty, tw) is usually above the item (ty < 0) and sits *inside* the
// island, so the neck disappears under it (see the cut-out in genie.frag).
layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 coord;
layout(location = 1) out vec2 pos;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float t;
    float tx;
    float tw;
    float ty;
    float w;
    float h;
    float ix;
    float iw;
    float ih;
    float ir;
    float bs;
    float rr;
    vec4 borderColor;
};
out gl_PerVertex { vec4 gl_Position; };

const float PI = 3.14159265;

void main() {
    coord = qt_MultiTexCoord0;
    float away = 1.0 - t;
    // first the near edge is pinched in to the mouth...
    float pinch = (1.0 - cos(PI * clamp(away / 0.45, 0.0, 1.0))) * 0.5;
    // ...then the sheet is drawn up through the funnel that leaves
    float span = h - ty;
    float a = clamp((away - 0.12) / 0.88, 0.0, 1.0);
    float slide = a * a * span;
    // rows that have gone past the mouth collapse onto it
    float y = max(coord.y * h - slide, ty);
    // squeezed all the way at the mouth, not at all at the far edge, S-curve between
    float e = pinch * (1.0 + cos(PI * clamp((y - ty) / span, 0.0, 1.0))) * 0.5;
    float left = tx * e;
    float width = w + (tw - w) * e;
    pos = vec2(left + coord.x * width, y);
    gl_Position = qt_Matrix * vec4(pos, 0.0, 1.0);
}
