#version 460 core
#include <flutter/runtime_effect.glsl>

// One pass of a *variable* Gaussian blur: the radius is a function of how far
// down the bar the fragment sits, peaking at the top and reaching zero — with a
// zero slope — at the bottom edge.
//
// This is the whole reason the shader exists. The banded version it replaced
// stacked five clipped `BackdropFilter`s, and each clip was a hard cut: blur
// stepped at every boundary (a visible horizontal line), each band's kernel was
// wider than its own clip so it edge-clamped and smeared rows instead of
// blurring them, and because every band filtered the one below it the sigmas
// compounded to ~16 at the top where 11 was intended. A continuous ramp has no
// boundary to show, nothing to clamp against, and the sigma it is handed is the
// sigma it applies.
//
// Separable, so it is run twice — vertically, then horizontally over that
// result. Two 17-tap passes instead of one 289-tap kernel.
//
// `highp` is not optional: `uv` is a fraction of a texture that is over a
// thousand pixels wide, and mediump's ~10-bit mantissa cannot address a single
// pixel in it.
precision highp float;

// Set by the engine to the size of the filter's input texture.
uniform vec2 uTextureSize;

// x: the bar's own height in device pixels — the distance the ramp is measured
//    over, which is *not* the texture's height (the backdrop the engine hands
//    us may be larger than the box we are drawn into).
// y: peak sigma, device pixels, at the very top of the bar.
uniform vec2 uBar;

// (0,1) for the vertical pass, (1,0) for the horizontal one.
uniform vec2 uDirection;

// Peak saturation multiplier, ramped down with the blur. Apple's own materials
// boost saturation so a coloured chip or a source dot passing under the bar
// keeps its colour instead of washing out to the same grey as everything else.
// It has to fade on the *same* curve as the blur: a flat boost puts a colour
// step exactly at the bar's bottom edge, which is another line to see. Set to
// 1.0 on the vertical pass so the pair applies it once.
uniform float uSaturation;

uniform sampler2D uTexture;

out vec4 fragColor;

// Each side of centre. With a stride of 0.5 sigma this covers ±4 sigma, past
// which the Gaussian's weight is under 0.0003.
const int kTaps = 8;

void main() {
  vec2 pos = FlutterFragCoord().xy;
  // Impeller's GLES backend hands us a flipped y. Flipping the position rather
  // than the sampling coordinate keeps the ramp the right way up too.
#ifdef IMPELLER_TARGET_OPENGLES
  pos.y = uTextureSize.y - pos.y;
#endif
  vec2 uv = pos / uTextureSize;

  // 1 at the top of the bar, 0 at the bottom. `smoothstep` rather than a linear
  // fade because its slope is zero at *both* ends: the blur holds near its peak
  // under the title, then dies into the content with no discontinuity in the
  // rate of change either — a linear ramp ends in a corner the eye still reads
  // as a faint edge.
  float t = clamp(pos.y / max(uBar.x, 1.0), 0.0, 1.0);
  float ramp = smoothstep(0.0, 0.62, 1.0 - t);
  float sigma = uBar.y * ramp;

  // Clamped by hand, half a texel in. The input sampler's tiling is the
  // engine's business and a decal mode would fade the top of the bar toward
  // transparent black — an artifact worse than the banding this replaces.
  vec2 lo = vec2(0.5) / uTextureSize;
  vec2 hi = vec2(1.0) - lo;

  vec4 color;
  if (sigma < 0.35) {
    // Below a third of a pixel there is nothing left to average: the taps would
    // all land on the same texel.
    color = texture(uTexture, clamp(uv, lo, hi));
  } else {
    float stride = sigma * 0.5;
    vec2 tapStep = uDirection * stride / uTextureSize;
    vec4 sum = texture(uTexture, clamp(uv, lo, hi));
    float weight = 1.0;
    for (int i = 1; i <= kTaps; i++) {
      float d = float(i) * stride;
      float w = exp(-0.5 * d * d / (sigma * sigma));
      vec2 offset = tapStep * float(i);
      sum += w * (texture(uTexture, clamp(uv + offset, lo, hi)) +
                  texture(uTexture, clamp(uv - offset, lo, hi)));
      weight += 2.0 * w;
    }
    color = sum / weight;
  }

  float saturation = mix(1.0, uSaturation, ramp);
  if (saturation != 1.0 && color.a > 0.0) {
    // The engine's colours are premultiplied; saturating the premultiplied
    // triple would drag the result toward black wherever alpha is under one.
    vec3 straight = color.rgb / color.a;
    float luma = dot(straight, vec3(0.2126, 0.7152, 0.0722));
    color = vec4(mix(vec3(luma), straight, saturation) * color.a, color.a);
  }

  fragColor = color;
}
