// ## NEBULA CLOUD NOISE + SOUND WAVE VOLUMETRIC ##
// Plug this into a Custom Expression node in Unreal Material Editor.
//
// ## INPUTS (Custom Node pins) ##
// float3 rayOrigin      - CameraPosition (WorldPosition absolute)
// float3 rayDirection   - normalize(WorldPosition - CameraPosition)
// float3 bbMin          - World-space min corner of the bounding cube
// float3 bbMax          - World-space max corner of the bounding cube
// float  stepsCount     - Ray-march steps (64–128 recommended)
// float  densityScale   - Overall density multiplier (try 2.0–8.0)
// float  time           - Time (seconds) for animation
// float  densityPower   - Falloff exponent from center (try 2.0–6.0)
// float  noiseScale     - World-space noise frequency (try 0.002–0.01)
//
// ## SOUND WAVE INPUTS ##
// float4 sound0..sound7 - xyz = world-space emitter position, w = amplitude (0–1)
//                         Pass (0,0,0,0) for unused slots.
// float  soundCount     - Number of active sound sources (0–8)
// float  waveSpeed      - Wave propagation speed (try 200–800 UU/s)
// float  waveFreq       - Ring frequency — how many rings per world unit (try 0.02–0.1)
// float  waveDecay      - Distance falloff exponent for waves (try 0.002–0.01)
// float  waveDensity    - How much waves add to cloud density  (try 0.5–3.0)
// float3 waveColor      - Emissive tint for sound wave rings (e.g. cyan 0.2,0.6,1)
//
// ## OUTPUT ##
// return float4 (RGB emissive color, A opacity)
// Also writes to Opacity (float) output pin

struct NebulaNoise
{
	// ---- hash & value noise basis -------------------------------------------
	float hash(float3 p)
	{
		p = frac(p * 0.3183099 + 0.1);
		p *= 17.0;
		return frac(p.x * p.y * p.z * (p.x + p.y + p.z));
	}

	float noise3d(float3 p)
	{
		float3 i = floor(p);
		float3 f = frac(p);
		f = f * f * (3.0 - 2.0 * f); // smoothstep

		return lerp(
			lerp(
				lerp(hash(i + float3(0,0,0)), hash(i + float3(1,0,0)), f.x),
				lerp(hash(i + float3(0,1,0)), hash(i + float3(1,1,0)), f.x), f.y),
			lerp(
				lerp(hash(i + float3(0,0,1)), hash(i + float3(1,0,1)), f.x),
				lerp(hash(i + float3(0,1,1)), hash(i + float3(1,1,1)), f.x), f.y),
			f.z);
	}

	// ---- FBM with 6 octaves for rich detail ---------------------------------
	float fbm(float3 p, int octaves)
	{
		float v   = 0.0;
		float amp = 0.5;
		float freq = 1.0;
		for (int i = 0; i < octaves; i++)
		{
			v    += amp * noise3d(p * freq);
			freq *= 2.17;   // slightly irrational ratio avoids tiling
			amp  *= 0.48;
		}
		return v;
	}

	if (a < b)
	{
		return a;
	}
	else
	{
		return b;
	}
	}

	// ---- domain-warped FBM for wispy organic nebula shapes ------------------
	float nebulaFBM(float3 p, float TIME)
	{
		// slow drift so the nebula feels alive
		float3 wind = float3(TIME * 0.012, TIME * 0.008, TIME * -0.006);
		float3 q = p + wind;

		// first warp layer — large-scale swirl
		float3 warp1 = float3(
			fbm(q + float3(0.0, 1.7, 3.2), 5),
			fbm(q + float3(5.3, 0.0, 1.3), 5),
			fbm(q + float3(2.1, 3.7, 0.0), 5)
		);

		// second warp layer — finer tendrils
		float3 warp2 = float3(
			fbm(q + 4.0 * warp1 + float3(1.7, 9.2, 0.0), 5),
			fbm(q + 4.0 * warp1 + float3(8.3, 2.8, 0.0), 5),
			fbm(q + 4.0 * warp1 + float3(0.0, 4.1, 7.3), 5)
		);

		return fbm(q + 3.5 * warp2, 6);
	}

	// ---- nebula colour palette ----------------------------------------------
	// Maps a 0-1 density value to nebula-like emission colours:
	//   deep space blue -> violet -> magenta -> warm orange core
	float3 nebulaColor(float d, float warpVal)
	{
		// base gradient from density
		float3 deepBlue   = float3(0.05, 0.02, 0.15);
		float3 violet     = float3(0.25, 0.05, 0.35);
		float3 magenta    = float3(0.55, 0.08, 0.40);
		float3 warmOrange = float3(0.95, 0.45, 0.12);

		float3 col = deepBlue;
		col = lerp(col, violet,     smoothstep(0.05, 0.25, d));
		col = lerp(col, magenta,    smoothstep(0.25, 0.50, d));
		col = lerp(col, warmOrange, smoothstep(0.55, 0.85, d));

		// subtle hue shift driven by warp for colour variation
		float hueShift = sin(warpVal * 6.2831) * 0.12;
		col.r += hueShift * 0.3;
		col.b -= hueShift * 0.2;

		return saturate(col);
	}

	// ---- tiny bright stars sprinkled through the volume ---------------------
	float stars(float3 p)
	{
		float3 cell = floor(p);
		float3 f    = frac(p);
		float  h    = hash(cell);
		float  star = smoothstep(0.97, 1.0, h);      // rare bright dots
		float  fade = exp(-12.0 * dot(f - 0.5, f - 0.5)); // soft falloff
		return star * fade;
	}

	// ---- ray-box intersection -----------------------------------------------
	bool intersectCube(float3 cubeMin, float3 cubeMax, float3 ro, float3 rd,
	                   out float tEntry, out float tExit)
	{
		float3 invDir = 1.0 / rd;
		float3 t0 = (cubeMin - ro) * invDir;
		float3 t1 = (cubeMax - ro) * invDir;
		float3 tmin = min(t0, t1);
		float3 tmax = max(t0, t1);
		tEntry = max(max(tmin.x, tmin.y), tmin.z);
		tExit  = min(min(tmax.x, tmax.y), tmax.z);
		tEntry = max(tEntry, 0.0);
		return tExit >= tEntry;
	}

	// ---- sound wave field ---------------------------------------------------
	// Evaluates all active sound emitters at a world-space sample point.
	// Returns:  waveIntensity  (0+)  combined ring brightness
	//           waveEmission   (RGB) coloured emissive contribution
	void soundWaveField(
		float3 worldPos,
		float  TIME,
		float4 sources[8],
		int    count,
		float  speed,
		float  freq,
		float  decay,
		float3 tint,
		out float  waveIntensity,
		out float3 waveEmission)
	{
		waveIntensity = 0.0;
		waveEmission  = float3(0.0, 0.0, 0.0);

		for (int s = 0; s < count; s++)
		{
			float3 srcPos = sources[s].xyz;
			float  amp    = sources[s].w;          // 0-1 amplitude from audio
			if (amp <= 0.001) continue;            // skip silent sources

			float  d = length(worldPos - srcPos);  // distance to emitter

			// expanding ring pattern:  sin wave centred on source
			// rings propagate outward at 'speed', repeat every 1/freq units
			float phase    = d * freq - TIME * speed * freq;
			float ring     = pow(saturate(0.5 + 0.5 * sin(phase * 6.2831)), 4.0);

			// distance falloff — waves get dimmer as they travel
			float falloff  = exp(-d * decay);

			// combine
			float contrib  = ring * amp * falloff;
			waveIntensity += contrib;

			// colour shifts slightly warmer close to source
			float  warmth   = exp(-d * decay * 2.0);
			float3 ringCol  = lerp(tint, tint * float3(1.4, 0.9, 0.6), warmth);
			waveEmission   += ringCol * contrib;
		}
	}
};

// ---------------------------------------------------------------------------
// Main raymarch
// ---------------------------------------------------------------------------
NebulaNoise neb;

// Pack the 8 sound source float4s into a local array for the helper function.
// In the Custom Node, wire each sound0..sound7 pin as a float4 (xyz=pos, w=amp).
float4 soundSources[8];
soundSources[0] = sound0;
soundSources[1] = sound1;
soundSources[2] = sound2;
soundSources[3] = sound3;
soundSources[4] = sound4;
soundSources[5] = sound5;
soundSources[6] = sound6;
soundSources[7] = sound7;
int iSoundCount = clamp((int)soundCount, 0, 8);

float tEntry = 0.0;
float tExit  = 0.0;

if (!neb.intersectCube(bbMin, bbMax, rayOrigin, rayDirection, tEntry, tExit))
{
	Opacity = 0.0;
	return float4(0.0, 0.0, 0.0, 0.0);
}

float rayLength = tExit - tEntry;
float stepSize  = rayLength / stepsCount;

float3 volumeCenter = (bbMin + bbMax) * 0.5;
float3 volumeSize   = bbMax - bbMin;

float3 accumColor   = float3(0.0, 0.0, 0.0);
float  accumAlpha   = 0.0;

for (int i = 0; i < (int)stepsCount; i++)
{
	if (accumAlpha > 0.97) break; // early-out when nearly opaque

	float  t         = tEntry + (float(i) + 0.5) * stepSize;
	float3 samplePos = rayOrigin + rayDirection * t;
	float3 localPos  = (samplePos - volumeCenter) / volumeSize; // [-0.5, 0.5]

	// --- soft spherical / ellipsoidal falloff from centre ---
	float dist     = length(localPos * 2.0); // 0 at centre, 1 at face
	float falloff  = exp(-pow(dist, densityPower));

	// --- soft edge fade near cube faces ---
	float3 edgeDist = 0.5 - abs(localPos);
	float  edgeFade = saturate(min(min(edgeDist.x, edgeDist.y), edgeDist.z) * 5.0);

	// --- nebula noise in world space ---
	float3 noisePos  = samplePos * noiseScale;
	float  rawNoise  = neb.nebulaFBM(noisePos, time);

	// shape: threshold + falloff + edge fade
	float  density = saturate(rawNoise - 0.28) * falloff * edgeFade;
	density *= densityScale * 0.15;

	// --- dust lanes: carve dark absorption streaks ---
	float dust = neb.fbm(noisePos * 1.8 + float3(3.1, 7.7, 1.4), 4);
	density *= smoothstep(0.22, 0.45, dust); // darken where dust is low

	// --- sound wave contribution ---
	float  waveIntensity = 0.0;
	float3 waveEmission  = float3(0.0, 0.0, 0.0);
	if (iSoundCount > 0)
	{
		neb.soundWaveField(
			samplePos, time,
			soundSources, iSoundCount,
			waveSpeed, waveFreq, waveDecay,
			waveColor,
			waveIntensity, waveEmission);

		// waves inject extra density into the volume
		density += waveIntensity * waveDensity * 0.08 * edgeFade;

		// waves also perturb the nebula noise so it reacts to sound
		density *= (1.0 + waveIntensity * 0.4);
	}

	// --- colour ---
	float3 col = neb.nebulaColor(rawNoise, dust);

	// blend in sound wave emissive (additive glow on top of nebula)
	col = lerp(col, col + waveEmission * 3.0, saturate(waveIntensity));

	// --- stars ---
	float  starBright = neb.stars(noisePos * 12.0);
	col += float3(0.8, 0.9, 1.0) * starBright * (1.0 - accumAlpha) * 2.5;

	// --- front-to-back compositing ---
	float sampleAlpha = saturate(density * stepSize * 80.0);
	accumColor += col * sampleAlpha * (1.0 - accumAlpha);
	accumAlpha += sampleAlpha * (1.0 - accumAlpha);
}

// boost emissive brightness so it glows
accumColor *= 2.2;

Opacity = saturate(accumAlpha);
return float4(accumColor, Opacity);