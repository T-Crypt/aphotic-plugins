// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors
//
// Retints a pet's accent regions onto the live palette, so a pet wears
// the theme instead of sitting on the desktop as a foreign sprite. Every
// pet comes through here; one that declares no accent window passes
// through at strength zero.
//
// The accent is selected by hue, not by a mask, because the pet
// generators produce one flat image and nothing else. A pet declares the
// hue window its recolourable regions live in and the saturation floor
// that separates them from its neutrals; everything outside that window
// -- skin, hair, dark cloth, the whole unsaturated base -- passes through
// untouched. Cipher's accents sit between 205 and 285 degrees and his
// skin below 50, which is the gap this relies on.
//
// Value is never touched. Cel shading lives entirely in the value
// channel, so replacing hue and scaling saturation moves the colour and
// leaves every shading band where the artist put it. Driving value from
// the palette instead flattens the sprite into a silhouette, which is the
// outcome this is written to avoid.
//
// `strength` at 0 is an exact passthrough, which is what a pet with no
// declared accent and a pet whose retint the user turned off both draw.
// One code path, rather than a second one that has to stay in step.

#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    // Degrees. The window wraps, so 340 -> 20 is a legal red band.
    float hueFrom;
    float hueTo;
    // Degrees of soft edge at each end, so a gradient crossing the
    // boundary fades instead of stepping.
    float hueFeather;
    // Below this saturation a pixel is neutral and is left alone.
    float minSat;
    // The saturation the pet's accents were drawn at. Saturation is
    // scaled by accent/reference rather than replaced, so a muted theme
    // mutes the pet in proportion instead of flattening it.
    float refSat;
    float strength;
    vec4 accent;
};

layout(binding = 1) uniform sampler2D source;

vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void main() {
    vec4 tex = texture(source, qt_TexCoord0);
    if (tex.a <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }

    // Qt hands over premultiplied alpha and expects it back. The hue
    // maths in between only means anything on straight colour.
    vec3 rgb = tex.rgb / tex.a;

    if (strength > 0.0) {
        vec3 hsv = rgb2hsv(rgb);
        float span = mod(hueTo - hueFrom + 360.0, 360.0);
        float rel = mod(hsv.x * 360.0 - hueFrom + 360.0, 360.0);
        // A feather wider than half the window would leave no fully
        // selected middle, so it gives way to the window rather than the
        // other way round.
        float feather = max(min(hueFeather, span * 0.5), 0.001);
        float band = smoothstep(0.0, feather, rel) * (1.0 - smoothstep(span - feather, span, rel));
        float mask = band * smoothstep(minSat, minSat + 0.10, hsv.y) * strength;

        vec3 target = rgb2hsv(accent.rgb);
        float sat = clamp(hsv.y * (target.y / max(refSat, 0.05)), 0.0, 1.0);
        rgb = mix(rgb, hsv2rgb(vec3(target.x, sat, hsv.z)), mask);
    }

    fragColor = vec4(rgb * tex.a, tex.a) * qt_Opacity;
}
