#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float4 p0;          // time, bass, mid, treble
    float4 p1;          // rms, peak, onset, silent
    float4 p2;          // gain, bandCount, width, height
    float4 chroma[3];
    float4 bands[16];
    float4 wave[32];
};

struct VertOut {
    float4 position [[position]];
    float2 uv;
};

static float bandAt(constant Uniforms &u, int i) {
    i = clamp(i, 0, 63);
    return u.bands[i / 4][i % 4];
}

static float waveAt(constant Uniforms &u, int i) {
    i = clamp(i, 0, 127);
    return u.wave[i / 4][i % 4];
}

static float chromaAt(constant Uniforms &u, int i) {
    i = clamp(i, 0, 11);
    return u.chroma[i / 4][i % 4];
}

static float hash21(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static float brick(float2 uv) {
    float2 scaled = uv * float2(10.0, 16.0);
    float row = floor(scaled.y);
    if (fmod(row, 2.0) > 0.5) {
        scaled.x += 0.5;
    }
    float2 f = fract(scaled);
    float mortar = step(0.08, f.x) * step(0.12, f.y);
    return mortar;
}

static float flame(float2 p, float energy, float time) {
    p.y += 0.02;
    float y = clamp(p.y, 0.0, 1.0);
    float flicker = 0.6 + 0.4 * sin(time * 11.0 + p.x * 40.0);
    float width = (0.18 + 0.35 * energy) * (1.0 - y) * flicker;
    float d = abs(p.x) - width;
    float body = 1.0 - smoothstep(0.0, 0.05, d);
    body *= smoothstep(0.0, 0.08, y) * (1.0 - smoothstep(0.55 + 0.4 * energy, 1.0, y));
    return pow(body, 1.2);
}

vertex VertOut hall_vertex(uint vid [[vertex_id]]) {
    float2 positions[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    VertOut out;
    out.position = float4(positions[vid], 0.0, 1.0);
    out.uv = float2(positions[vid].x * 0.5 + 0.5, 0.5 - positions[vid].y * 0.5);
    return out;
}

fragment float4 hall_fragment(VertOut in [[stage_in]],
                              constant Uniforms &u [[buffer(0)]]) {
    float time = u.p0.x;
    float bass = u.p0.y;
    float mid = u.p0.z;
    float treble = u.p0.w;
    float rms = u.p1.x;
    float onset = u.p1.z;
    float silent = u.p1.w;
    float2 uv = in.uv;

    float3 orange = float3(1.0, 0.38, 0.12);
    float3 ember = float3(1.0, 0.62, 0.22);
    float3 bg = float3(0.03, 0.012, 0.01);
    float3 col = bg;

    // Starfield
    float stars = step(0.996, hash21(floor(uv * float2(180.0, 90.0) + treble * 4.0)));
    col += orange * stars * (0.25 + 0.75 * treble);

    // Brick hall
    float hallTop = 0.18;
    float hallBot = 0.62;
    if (uv.y > hallTop && uv.y < hallBot) {
        float2 buv = float2(uv.x, (uv.y - hallTop) / (hallBot - hallTop));
        float b = brick(buv);
        float3 brickCol = mix(float3(0.08, 0.03, 0.02), float3(0.22, 0.07, 0.03), b);
        brickCol += orange * bass * 0.18;
        col = mix(col, brickCol, 0.92);

        // Window candles on the masonry
        float2 cell = floor(buv * float2(10.0, 4.0));
        float2 local = fract(buv * float2(10.0, 4.0)) - 0.5;
        float candleOn = step(0.15, hash21(cell + 2.7));
        float2 flameUV = float2(local.x * 4.0, 0.35 - local.y);
        float cf = flame(flameUV, 0.45 + bass * 0.5, time + cell.x);
        col += orange * cf * candleOn * (0.35 + onset * 0.4);
    }

    // Arcade arches + torches (12, chroma-driven)
    const int N = 12;
    for (int i = 0; i < N; i++) {
        float gx = (float(i) + 0.5) / float(N);
        float energy = max(chromaAt(u, i), bandAt(u, i * 5));
        energy = max(energy, onset * 0.4);
        float2 local = float2((uv.x - gx) * float(N) * 0.55, (uv.y - 0.34) * 2.4);

        float arch = smoothstep(0.62, 0.55, length(float2(local.x, min(local.y, 0.0))));
        arch *= smoothstep(0.55, 0.2, uv.y) * smoothstep(0.18, 0.28, uv.y);
        col = mix(col, orange * 0.15, arch * 0.35);

        float2 flameUV = float2(uv.x - gx, (hallTop + 0.02) - uv.y);
        flameUV.x *= 18.0;
        flameUV.y *= 7.0;
        float f = flame(flameUV, energy, time + float(i));
        float3 flameCol = mix(orange, ember, clamp(flameUV.y * 1.4, 0.0, 1.0));
        col += flameCol * f * (0.55 + energy);
    }

    // Spectrum curve
    float specY = 0.78;
    int idx = int(clamp(uv.x, 0.0, 0.999) * 63.0);
    float b = bandAt(u, idx);
    float y = specY - b * 0.16;
    float line = 1.0 - smoothstep(0.002, 0.01, abs(uv.y - y));
    col += orange * line * (0.4 + b);

    // Waveform ribbon
    int wi = int(clamp(uv.x, 0.0, 0.999) * 127.0);
    float w = waveAt(u, wi);
    float waveY = 0.88 + w * 0.06;
    float waveLine = 1.0 - smoothstep(0.0015, 0.008, abs(uv.y - waveY));
    col += orange * waveLine * 0.7;

    // Side meters
    if (uv.x < 0.03) {
        float fill = step(1.0 - uv.y, rms);
        col = mix(col, orange, fill * 0.8);
    }
    if (uv.x > 0.97) {
        float fill = step(1.0 - uv.y, mid);
        col = mix(col, ember, fill * 0.8);
    }

    // Piano keys
    if (uv.y > 0.93) {
        int key = int(uv.x * 12.0);
        float on = chromaAt(u, key);
        float3 keyCol = mix(float3(0.08, 0.04, 0.03), orange, on);
        col = mix(col, keyCol, 0.9);
        float sep = smoothstep(0.004, 0.0, abs(fract(uv.x * 12.0) - 0.02));
        col *= 1.0 - sep * 0.4;
    }

    // Title band
    if (uv.y < 0.06) {
        col = mix(col, orange * 0.2, 0.65);
    }

    // CRT scan + vignette
    float scan = 0.92 + 0.08 * sin(uv.y * u.p2.w * 3.14159 * 1.15 + time * 2.0);
    col *= scan;
    float vig = smoothstep(1.2, 0.35, length((uv - 0.5) * 1.4));
    col *= vig;
    col += orange * onset * 0.08;
    if (silent > 0.5) {
        col *= 0.55;
    }

    return float4(clamp(col, 0.0, 1.0), 1.0);
}
