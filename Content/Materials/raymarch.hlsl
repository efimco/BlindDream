// ## INPUTS (Custom Node in Unreal) ##
// float3 rayOrigin     - CameraPosition
// float3 rayDirection  - normalize(WorldPosition - CameraPosition)
// float3 bbMin         - World-space min corner of the cube
// float3 bbMax         - World-space max corner of the cube
// float stepsCount     - Number of steps (64-128)
// float densityScale   - How thick the cloud is (try 1.0-5.0)
// float time            - Time for animation (can be used in noise)
// float3 cloudColor 	- Base color of the cloud (e.g., light gray or white)
// float densityPower
// float noiseScale

struct HelperFunctions
{
	bool intersectCube(float3 cubeMin, float3 cubeMax, float3 ro, float3 rd, out float tEntry, out float tExit)
	{
		float3 invDir = 1.0 / rd;
		float3 t0 = (cubeMin - ro) * invDir;
		float3 t1 = (cubeMax - ro) * invDir;

		float3 tmin = min(t0, t1); // entry points for each axis
		float3 tmax = max(t0, t1); // exit points for each axis

		tEntry = max(max(tmin.x, tmin.y), tmin.z);
		tExit = min(min(tmax.x, tmax.y), tmax.z);

		tEntry = max(tEntry, 0.0); // handle camera inside the cube

		return tExit >= tEntry; // valid intersection if exit is after entry
	}

	float hash(float3 p)
	{
		p = frac(p * 0.3183099 + 0.1);
		p *= 17.0;
		return frac(p.x * p.y * p.z * (p.x + p.y + p.z));
	}

	float noise3d(float3 p) // Simple Perlin-like noise for cloud texture
	{
		float3 i = floor(p); // integer lattice point
		float3 f = frac(p); // fractional part for interpolation
		f = f * f * (3.0 - 2.0 * f); // smoothstep for smoother transitions

		return lerp(

			lerp(
				lerp(hash(i + float3(0, 0, 0)), hash(i + float3(1, 0, 0)), f.x),
				lerp(hash(i + float3(0, 1, 0)), hash(i + float3(1, 1, 0)), f.x),
				f.y),

			lerp(
				lerp(hash(i + float3(0, 0, 1)), hash(i + float3(1, 0, 1)), f.x),
				lerp(hash(i + float3(0, 1, 1)), hash(i + float3(1, 1, 1)), f.x),
				f.y),
			f.z);
	}

	float fbm(float3 p) // Fractal Brownian Motion for more complex noise
	{
		float v = 0.0;
		float amp = 0.5;
		float freq = 1.0;
		for (int i = 0; i < 5; i++)
		{
			v += amp * noise3d(p * freq);
			freq *= 2.0;
			amp *= 0.5;
		}
		return v;
	}

	float sampleDensity(float3 localPos, float TIME) // localPos is in range [-0.5, 0.5] within the cube
	{
		// Soft edges: fade near cube boundaries
		float3 edgeDist = 0.5 - abs(localPos);
		float edgeFade = saturate(min(min(edgeDist.x, edgeDist.y), edgeDist.z) * 4.0);

		// Cloud shape from noise
		// float3 wind = float3(TIME + 0.05, TIME * 0.02, TIME * 0.03); // animate noise with time
		float n = fbm(localPos); // scale noise for larger features
		return saturate(n - 0.35) * edgeFade; // threshold to create more defined cloud shapes, multiplied by edge fade
	}
};

HelperFunctions helper;

// Step 1: Find where the ray enters and exits the cube
float tEntry = 0.0;
float tExit = 0.0;

if (!helper.intersectCube(bbMin, bbMax, rayOrigin, rayDirection, tEntry, tExit))
{
	return float4(0.0, 0.0, 0.0, 0.0); // ray misses cube entirely
}

float3 posEntry = rayOrigin + rayDirection * tEntry;
float3 posExit = rayOrigin + rayDirection * tExit;

// Step 2: March from entry to exit, accumulating density
float rayLength = tExit - tEntry;
float stepSize = rayLength / stepsCount; // uniform step size for simplicity

float3 volumeCenter = (bbMin + bbMax) * 0.5; // center of the cube for local coordinate conversion
float3 volumeSize = bbMax - bbMin; // for converting world to local coords

float totalDensity = 0.0;
for (int i = 0; i < (int)stepsCount; i++)
{
	float t = tEntry + (float(i) + 0.5) * stepSize;
	float3 samplePos = rayOrigin + rayDirection * t;
	float3 localPos = (samplePos - volumeCenter) / volumeSize; // convert to local [-0.5, 0.5]
	float noiseSample = helper.noise3d((float3(samplePos.x + time / noiseScale, samplePos.y, samplePos.z)) * noiseScale); // animate noise with time

	float3 absLocalPos = abs(localPos) * 2.0; // scale to [0, 1] for distance calculation
	float dist = max(max(absLocalPos.x, absLocalPos.y), absLocalPos.z); // distance from center in local space 0 at center, 1 at face
	float density = exp(-pow(dist, densityPower) * densityScale) * noiseSample; // apply density falloff and noise-based density
	totalDensity += density * stepSize; // accumulate density along the ray, scaled by step size for proper integration

}

float alpha = saturate(totalDensity); // simple exponential falloff for opacity, can be adjusted for different looks
float3 ambient = cloudColor * alpha; // modulate cloud color by density

Opacity = alpha;
return ambient;