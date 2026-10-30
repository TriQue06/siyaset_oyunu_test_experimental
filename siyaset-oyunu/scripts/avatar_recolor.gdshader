shader_type canvas_item;
render_mode unshaded;
uniform sampler2D regions : filter_linear, repeat_disable;
uniform int mode = 0;
uniform bool keep_main = true;
uniform bool keep_skin = true;
uniform bool keep_lips = true;
uniform vec4 main_shadow : source_color;
uniform vec4 main_base : source_color;
uniform vec4 main_light : source_color;
uniform vec4 skin_shadow : source_color;
uniform vec4 skin_base : source_color;
uniform vec4 skin_light : source_color;
uniform vec4 lip_shadow : source_color;
uniform vec4 lip_base : source_color;
uniform vec4 lip_light : source_color;
float luma(vec3 rgb) {return dot(rgb, vec3(0.299, 0.587, 0.114));}
vec3 ramp(float t, float midpoint, vec3 dark, vec3 base, vec3 light) {
 return t < midpoint ? mix(dark, base, clamp(t / midpoint, 0.0, 1.0)) : mix(base, light, clamp((t - midpoint) / (1.0 - midpoint), 0.0, 1.0));
}
vec3 skin_map(vec3 rgb) {
 if (keep_skin) return rgb;
 float t = clamp((luma(rgb) - 0.12) / 0.80, 0.0, 1.0);
 vec3 mapped = ramp(t, 0.65, skin_shadow.rgb, skin_base.rgb, skin_light.rgb);
 // Retain ink lines while shifting the full illustrated skin/shadow range.
 return mix(rgb, mapped, smoothstep(0.07, 0.19, luma(rgb)));
}
varying vec4 tint;
void vertex() { tint = COLOR; }
void fragment() {
 vec4 original = texture(TEXTURE, UV);
 vec3 rgb = original.rgb;
 float lum = luma(rgb);
 vec2 mask = texture(regions, UV).rg;
 if (mode == 0) {
  vec3 lip_rgb = rgb;
  if (!keep_lips) lip_rgb = mix(rgb, ramp(clamp((lum - 0.10) / 0.68, 0.0, 1.0), 0.58, lip_shadow.rgb, lip_base.rgb, lip_light.rgb), smoothstep(0.10, 0.25, lum));
  rgb = mix(rgb, skin_map(rgb), mask.r);
  rgb = mix(rgb, lip_rgb, mask.g);
 } else if (mode == 1) {
  vec3 hair_rgb = rgb;
  if (!keep_main) hair_rgb = ramp(clamp((lum - 0.035) / 0.70, 0.0, 1.0), 0.39, main_shadow.rgb, main_base.rgb, main_light.rgb);
  rgb = mix(hair_rgb, skin_map(original.rgb), mask.g);
 } else if (!keep_main) {
  vec3 iris_rgb = ramp(clamp((lum - 0.04) / 0.74, 0.0, 1.0), 0.48, main_shadow.rgb, main_base.rgb, main_light.rgb);
  // Preserve neutral reflections and the dark pupil backing of the masked patch.
  float chroma = max(rgb.r, max(rgb.g, rgb.b)) - min(rgb.r, min(rgb.g, rgb.b));
  float reflection = smoothstep(0.65, 0.90, min(rgb.r, min(rgb.g, rgb.b))) * (1.0 - smoothstep(0.08, 0.22, chroma));
  rgb = mix(rgb, iris_rgb, (1.0 - reflection) * smoothstep(0.06, 0.16, lum));
 }
 COLOR = vec4(rgb, original.a) * tint;
}
