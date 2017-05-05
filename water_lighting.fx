#if OPENGL
#define SV_POSITION POSITION
#define VS_SHADERMODEL vs_3_0
#define PS_SHADERMODEL ps_3_0
#else
#define VS_SHADERMODEL vs_4_0_level_9_1
#define PS_SHADERMODEL ps_4_0_level_9_1
#endif

//camera
matrix xView;
matrix xProjection;
matrix xWorld;
matrix xReflectionView;
float3 xCameraPosition;


//water
Texture2D xWaterBumpMap;
Texture2D xReflectionMap;
Texture2D xRefractionMap;
float xWaveLength;
float xWaveHeight;

//wind
float xTime;
float3 xWindDirection;
float xWindPower;

//lighting
float3 xLightDirection;
float xAmbientLight;
bool xEnableLighting;

//for multitexturing
Texture2D<float4> xTexture0;
Texture2D<float4> xTexture1;
Texture2D<float4> xTexture2;
Texture2D<float4> xTexture3;

//for texture depth
float xTexPrecision;
//for clipping
float3 xClipPlane;
int xClipping;
//0 -> no clipping
//1 -> refraction clipping
//2 -> reflection clipping

SamplerState texSampler
{
	magfilter = LINEAR;
	minfilter = LINEAR;
	mipfilter = LINEAR;
//wraps the texture around 3d model, use for any 3d
	AddressU = wrap;
	AddressV = wrap;
};

SamplerState waterSampler
{
	magfilter = LINEAR;
	minfilter = LINEAR;
	mipfilter = LINEAR;
//mirrors texture |_ -> _| use for water reflections
	AddressU = mirror;
	AddressV = mirror;
};

matrix GetWorldViewProjection(matrix world, matrix view, matrix projection)
{
	matrix viewProjection = mul(view, projection);

	return mul(world, viewProjection);
}

struct PSOutput
{
	float4 Color : COLOR0;
};

//Water

struct WaterVSInput
{
	float4 Position : SV_POSITION0;
	float2 TexCoords : TEXCOORD0;
};

struct WaterVSOutput
{
	float4 Position : SV_POSITION0;
	float4 ReflectionMapPosition : TEXCOORD1;
	float2 BumpMapPosition : TEXCOORD2;
	float4 RefractionMapPosition : TEXCOORD3;
	float4 Position3D : TEXCOORD4;
};

float2 GetWindVector(float2 texCoords : TEXCOORD0)
{
	float3 windDirection = normalize(xWindDirection);
	float3 perpendicularDirection = cross(xWindDirection, float3(0, 1, 0));
	float windY = dot(texCoords, xWindDirection.xz);
	float windX = dot(texCoords, perpendicularDirection.xz);
	float2 windVector = float2(windX, windY);
	windVector.y += xTime * xWindPower;

	return windVector;
}

WaterVSOutput WaterVS(WaterVSInput input)
{
	WaterVSOutput output = (WaterVSOutput)0;

	matrix worldViewProjection = GetWorldViewProjection(xWorld, xView, xProjection);
	//matrix from the point of view of camera under water
	//angle of originalCamera <-> water = angle of underWaterCamera and water
	matrix worldReflectionViewProjection = GetWorldViewProjection(xWorld,
		xReflectionView, xProjection);
	//transforms position to position on real world and on reflection map
	output.Position = mul(input.Position, worldViewProjection);
	output.ReflectionMapPosition = mul(input.Position, worldReflectionViewProjection);
	//the larger wave length, the bigger area of bumpmap
	output.RefractionMapPosition = mul(input.Position, worldViewProjection);
	output.Position3D = mul(input.Position, xWorld);

	//float2 windVector = GetWindVector(input.TexCoords);
	output.BumpMapPosition = input.TexCoords / xWaveLength;

	return output;
}

PSOutput WaterPS(WaterVSOutput input)
{
	PSOutput output = (PSOutput)0;
	//finds position on reflection map
	float2 reflectionTexCoords;
	reflectionTexCoords.x = input.ReflectionMapPosition.x / 
		input.ReflectionMapPosition.w / 2.0f + 0.5f;
	reflectionTexCoords.y = -input.ReflectionMapPosition.y /
		input.ReflectionMapPosition.w / 2.0f + 0.5f;

	float2 refractionTexCoords;
	refractionTexCoords.x = input.RefractionMapPosition.x /
		input.RefractionMapPosition.w / 2.0f + 0.5f;
	refractionTexCoords.y = input.RefractionMapPosition.y /
		input.RefractionMapPosition.w / 2.0f + 0.5f;

	float4 bumpColor = xWaterBumpMap.Sample(waterSampler, input.BumpMapPosition);
	////remap from [0,1] to [-1,1], make waves
	float2 perturbation = xWaveHeight * (bumpColor.rg - 0.5f) * 2.0f;
	reflectionTexCoords = reflectionTexCoords + perturbation;
	refractionTexCoords = refractionTexCoords + perturbation;
	//find reflected light color
	float4 reflectionColor = xReflectionMap.Sample(waterSampler, reflectionTexCoords);
	//find color under the water
	float4 refractionColor = xRefractionMap.Sample(waterSampler, refractionTexCoords);

	float3 eyeVector = normalize(xCameraPosition - input.Position3D);
	float3 normalVector = float3(0, 1, 0);
	//find interpolation constant
	float fresnelTerm = dot(eyeVector, normalVector);
	//interpolate the color
	output.Color = lerp(reflectionColor, refractionColor, fresnelTerm);
	
	//float4 waterColor = float4(0.3f, 0.3f, 0.5f, 1.0f);

	//output.Color = lerp(output.Color, waterColor, 0.2f);
	return output;
}

technique Water
{
	pass Pass0
	{
		VertexShader = compile VS_SHADERMODEL WaterVS();
		PixelShader = compile PS_SHADERMODEL WaterPS();
	}
};

// MultiTextured
struct MultiTexturedVSInput
{
	float4 Position : SV_POSITION0;
	float3 Normal : NORMAL0;
	float2 TexCoords : TEXCOORD0;
	float4 TexWeights : TEXCOORD1;
};

struct MultiTexturedVSOutput
{
	float4 Position : SV_POSITION0;
	float4 Color : COLOR0;
	float3 Normal : TEXCOORD0;
	float2 TexCoords : TEXCOORD1;
	float4 LightDirection : TEXCOORD2;
	float4 TexWeights : TEXCOORD3;
	float Depth : TEXCOORD4;
	float ClipDistance : TEXCOORD5;
};


float4 GetClipDistance(float4 position : SV_POSITION0)
{
	float3 positionFromPlane;
	if (xClipping == 1) //if refraction, then clips vertices below the plane
	{
		positionFromPlane = xClipPlane - position;
	}
	else if (xClipping == 2)//if reflection, then clips vertices above the plane
	{
		positionFromPlane = position - xClipPlane;
	}
	//finds cosine -> if bigger than zero then it is above the plane
	//fix bug where some vertices are defined at height of clip plane -> they change color to black
	float clipDistance = dot(positionFromPlane, xClipPlane);
	
	return clipDistance;
}

MultiTexturedVSOutput MultiTexturedVS(MultiTexturedVSInput input)
{
	MultiTexturedVSOutput output = (MultiTexturedVSOutput)0;

	matrix worldViewProjection = GetWorldViewProjection(xWorld, xView, xProjection);
	//clipping non needed vertices for refraction/reflection
	if (xClipping != 0)
	{
		float clipDist = GetClipDistance(mul(input.Position, xWorld));
		output.ClipDistance = clipDist;
	}

	output.Position = mul(input.Position, worldViewProjection);
	output.Normal = mul(normalize(input.Normal), xWorld);
	output.TexCoords = input.TexCoords;
	output.LightDirection.xyz = -xLightDirection;
	output.LightDirection.w = 1;
	output.TexWeights = input.TexWeights;
	output.Depth = output.Position.z / output.Position.w;
	return output;
}

struct DepthColorValues
{
	float4 FarColor;
	float4 NearColor;
};

//get color of smaller and larger part of texture for blending depth
DepthColorValues GetDepthColorValues(MultiTexturedVSOutput input)
{
	DepthColorValues depthValues = (DepthColorValues)0;
	
	depthValues.FarColor = xTexture0.Sample(texSampler, input.TexCoords) * input.TexWeights.x;
	depthValues.FarColor += xTexture1.Sample(texSampler, input.TexCoords) * input.TexWeights.y;
	depthValues.FarColor += xTexture2.Sample(texSampler, input.TexCoords) * input.TexWeights.z;
	depthValues.FarColor += xTexture3.Sample(texSampler, input.TexCoords) * input.TexWeights.w;

	float2 preciseTexCoords = input.TexCoords * xTexPrecision;
	depthValues.NearColor = xTexture0.Sample(texSampler, preciseTexCoords) * input.TexWeights.x;
	depthValues.NearColor += xTexture1.Sample(texSampler, preciseTexCoords) * input.TexWeights.y;
	depthValues.NearColor += xTexture2.Sample(texSampler, preciseTexCoords) * input.TexWeights.z;
	depthValues.NearColor += xTexture3.Sample(texSampler, preciseTexCoords) * input.TexWeights.w;
	
	return depthValues;
}

PSOutput MultiTexturedPS(MultiTexturedVSOutput input)
{
	PSOutput output = (PSOutput)0;

	if (xClipping != 0)
	{
		if (input.ClipDistance <= 0)
		{
			clip(-1);
		}
	}

	float lightingFactor = 1;

	//simple lighting
	if (xEnableLighting)
	{
		float diffuseLightPower = saturate(dot((float3)input.Normal, input.LightDirection));
		lightingFactor = saturate(diffuseLightPower + xAmbientLight);
	}
	//multitexturing
	output.Color = xTexture0.Sample(texSampler, input.TexCoords) * input.TexWeights.x;
	output.Color += xTexture1.Sample(texSampler, input.TexCoords) * input.TexWeights.y;
	output.Color += xTexture2.Sample(texSampler, input.TexCoords) * input.TexWeights.z;
	output.Color += xTexture3.Sample(texSampler, input.TexCoords) * input.TexWeights.w;
	
	//depth blending -> the closer to vertex the smaller part of texture is used
	//distance at which blending starts
	float blendDistance = 0.99f;
	float blendBorderWidth = 0.005f;
	//limits factor to [0,1]
	float blendFactor = clamp((input.Depth - blendDistance) / blendBorderWidth, 0, 1);
	DepthColorValues depthValues = GetDepthColorValues(input);
	//linear interpolation between colors of textures
	output.Color = lerp(depthValues.NearColor, depthValues.FarColor, blendFactor);

	output.Color *= lightingFactor;

	return output;
}

technique MultiTextured
{
	pass Pass0
	{
		VertexShader = compile vs_5_0 MultiTexturedVS();
		PixelShader = compile ps_5_0 MultiTexturedPS();
	}
};

// NotShaded
struct NotShadedVSInput
{
	float4 Position : SV_POSITION0;
	float3 Normal : NORMAL0;
	float2 TexCoords : TEXCOORD0;
};

struct NotShadedVSOutput
{
	float4 Position : SV_POSITION0;
	float2 TexCoords : TEXCOORD0;
};

NotShadedVSOutput NotShadedVS(NotShadedVSInput input)
{
	NotShadedVSOutput output = (NotShadedVSOutput)0;

	matrix worldViewProjection = GetWorldViewProjection(xWorld, xView, xProjection);

	output.Position = mul(input.Position, worldViewProjection);
	output.TexCoords = input.TexCoords;

	return output;
}

PSOutput NotShadedPS(NotShadedVSOutput input)
{
	PSOutput output = (PSOutput)0;

	output.Color = xTexture0.Sample(texSampler, input.TexCoords);

	return output;
}

technique NotShaded
{
	pass Pass0
	{
		VertexShader = compile VS_SHADERMODEL NotShadedVS();
		PixelShader = compile PS_SHADERMODEL NotShadedPS();
	}
};