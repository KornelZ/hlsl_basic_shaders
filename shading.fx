#if OPENGL
#define SV_POSITION POSITION
#define VS_SHADERMODEL vs_3_0
#define PS_SHADERMODEL ps_3_0
#else
#define VS_SHADERMODEL vs_4_0_level_9_1
#define PS_SHADERMODEL ps_4_0_level_9_1
#endif

//matrix xCameraWorldViewProjection;
matrix xWorld;
//worldviewprojection from light source point of view
//matrix xLightWorldViewProjection;

matrix xCameraProjection;
matrix xCameraView;
matrix xLightProjection;
matrix xLightView;

float3 xLightPosition;
float xLightPower;
float xAmbientLight;
Texture xTex;
Texture xShadowMap;
Texture xCarLightTex;

sampler TextureSampler = sampler_state
{
	texture = <xTex>;
	magfilter = LINEAR;
	minfilter = LINEAR;
	mipfilter = LINEAR;
	AddressU = mirror;
	AddressV = mirror;
};

sampler ShadowMapSampler = sampler_state
{
	texture = <xShadowMap>;
	magfilter = LINEAR;
	minfilter = LINEAR;
	mipfilter = LINEAR;
	AddressU = clamp;
	AddressV = clamp;
};

sampler CarLightSampler = sampler_state
{
	texture = <xCarLightTex>;
	magfilter = LINEAR;
	minfilter = LINEAR;
	mipfilter = LINEAR;
	AddressU = clamp;
	AddressV = clamp;
};

float DotProduct(float3 lightPosition, float3 position3D, float3 normal)
{
	float3 lightDirection = normalize(position3D - lightPosition);
	return dot(-lightDirection, normal);
}

//ShadowedScene
struct ShadowedSceneVSInput
{
	float4 Position : SV_POSITION0;
	float3 Normal : NORMAL0;
	float2 TexCoords : TEXCOORD0;
};
struct ShadowedSceneVSOutput
{
	float4 Position : SV_POSITION0;
	float4 PositionAsSeenByLight : TEXCOORD0;
	float2 TexCoords : TEXCOORD1;
	float3 Normal : TEXCOORD2;
	float4 Position3D : TEXCOORD3;
};
struct ShadowedScenePSOutput
{
	float4 Color : COLOR0;
};

//preshader matrix multiplication done only once by cpu
//compiler finds calculations that are the same for every vertex in input
//and sends them to cpu
matrix GetWorldViewProjection(matrix view, matrix projection)
{
	matrix preViewProjection = mul(view, projection);
	matrix preWorldViewProjection = mul(xWorld, preViewProjection);
	return preWorldViewProjection;
}


ShadowedSceneVSOutput ShadowedSceneVertexShader(ShadowedSceneVSInput input)
{
	ShadowedSceneVSOutput output = (ShadowedSceneVSOutput)0;

	//get input v position as seen by the camera
	output.Position = mul(input.Position, GetWorldViewProjection(xCameraView, xCameraProjection));
	//get input v position as seen by the light source
	output.PositionAsSeenByLight = mul(input.Position, GetWorldViewProjection(xLightView, xLightProjection));
	/*output.Position = mul(input.Position, xCameraWorldViewProjection);*/
	/*output.PositionAsSeenByLight = mul(input.Position, xLightWorldViewProjection);*/
	//rotate Normal according to position in World
	output.Normal = normalize(mul(input.Normal, (float3x3) xWorld));
	output.TexCoords = input.TexCoords;
	//transform position of vertex to real position
	output.Position3D = mul(input.Position, xWorld);
	return output;
}

ShadowedScenePSOutput ShadowedScenePixelShader(ShadowedSceneVSOutput input)
{
	ShadowedScenePSOutput output = (ShadowedScenePSOutput)0;

	//remap texCoords from [-1,1] to [0,1]
	//if the value of texCoords was in [0,1] range before then it is in view of our light source
	float2 projectedTexCoords;
	projectedTexCoords[0] = input.PositionAsSeenByLight.x / input.PositionAsSeenByLight.w / 2.0f + 0.5f;
	projectedTexCoords[1] = -input.PositionAsSeenByLight.y / input.PositionAsSeenByLight.w / 2.0f + 0.5f;

	float diffuseLightFactor = 0;
	//check if the value of texCoords was the same before clipping to [0,1] if yes then it is lighted
	if ((saturate(projectedTexCoords).x == projectedTexCoords.x) && (saturate(projectedTexCoords).y == projectedTexCoords.y))
	{
		//get depth stored in shadow map i.e distance between pixel and light calculated before
		float depthStoredInShadowMap = tex2D(ShadowMapSampler, projectedTexCoords).r;
		//get distance calculated now
		float realDistance = input.PositionAsSeenByLight.z / input.PositionAsSeenByLight.w;
		//compare them, if realdistance - bias is smaller then it is not obscured by another object
		//the smaller the bias the greater is the shadow and it is closer to lighted object
		if ((realDistance - 0.003f) <= depthStoredInShadowMap)
		{
			//find direction of light(lightPos - position of pixel) and dotprod with normal
			diffuseLightFactor = DotProduct(xLightPosition, input.Position3D, input.Normal);
			diffuseLightFactor = saturate(diffuseLightFactor);
			diffuseLightFactor *= xLightPower;
		}
	}
	//sample the shape of light (0,1)
	float lightTextureFactor = tex2D(CarLightSampler, projectedTexCoords).r;
	diffuseLightFactor *= lightTextureFactor;
	//light the base color
	float4 baseColor = tex2D(TextureSampler, input.TexCoords);
	output.Color = baseColor * (diffuseLightFactor + xAmbientLight);

	return output;
}

technique ShadowedScene
{
	pass Pass0
	{
		VertexShader = compile VS_SHADERMODEL ShadowedSceneVertexShader();
		PixelShader = compile PS_SHADERMODEL ShadowedScenePixelShader();
	}
};

//ShadowMap creates a depth map (the darker pixel is the closer to light source
struct ShadowMapVSInput
{
	float4 Position : SV_POSITION0;
};
struct ShadowMapVSOutput
{
	float4 Position : SV_POSITION0;
	float4 Position2D : TEXCOORD0;
};
struct ShadowMapPSOutput
{
	float4 Color : COLOR0;
};


ShadowMapVSOutput ShadowMapVertexShader(ShadowMapVSInput input)
{
	ShadowMapVSOutput output = (ShadowMapVSOutput)0;
	//get projection of input position as seen from the light source view
	output.Position = mul(input.Position, GetWorldViewProjection(xLightView, xLightProjection));
	/*output.Position = mul(input.Position, xLightWorldViewProjection);*/
	output.Position2D = output.Position;

	return output;
}

ShadowMapPSOutput ShadowMapPixelShader(ShadowMapVSOutput input)
{
	ShadowMapPSOutput output = (ShadowMapPSOutput)0;

	//z is distance between light source and pixel, w is normalizer
	output.Color = input.Position2D.z / input.Position2D.w;

	return output;
}

technique ShadowMap
{
	pass Pass0
	{
		VertexShader = compile VS_SHADERMODEL ShadowMapVertexShader();
		PixelShader = compile PS_SHADERMODEL ShadowMapPixelShader();
	}
};

//TexturedShaded
struct TexturedShadedVSInput
{
	float4 Position : SV_POSITION0;
	float3 Normal : NORMAL;
	float2 TexCoords : TEXCOORD0;
};

struct TexturedShadedVSOutput
{
	float4 Position : SV_POSITION;
	float3 Normal : TEXCOORD0;
	float2 TexCoords : TEXCOORD1;
	float3 Position3D : TEXCOORD2;
};


struct TexturedShadedPSOutput
{
	float4 Color : COLOR0;
};


TexturedShadedVSOutput TexturedShadedVertexShader(TexturedShadedVSInput input)
{
	TexturedShadedVSOutput output = (TexturedShadedVSOutput)0;
	//transform vertices according to camera
	output.Position = mul(input.Position, GetWorldViewProjection(xCameraView, xCameraProjection));
	/*output.Position = mul(input.Position, xCameraWorldViewProjection);*/
	output.TexCoords = input.TexCoords;
	//we need to rotate the normals using World matrix
	output.Normal = normalize(mul(input.Normal, (float3x3) xWorld));
	//transform vertices according to their real position
	output.Position3D = mul((float3)input.Position, (float3x3) xWorld);

	return output;
}

TexturedShadedPSOutput TexturedShadedPixelShader(TexturedShadedVSOutput input)
{
	TexturedShadedPSOutput output = (TexturedShadedPSOutput)0;
	//compute direction of light(from lightPosition to input position in 3D, then dotProduct with normal
	float diffuseLightFactor = DotProduct(xLightPosition, input.Position3D, input.Normal);
	//set factor to [0,1] interval;
	diffuseLightFactor = saturate(diffuseLightFactor);
	diffuseLightFactor *= xLightPower;

	float4 baseColor = tex2D(TextureSampler, input.TexCoords);
	output.Color = baseColor * (diffuseLightFactor + xAmbientLight);
	//output.Color = diffuseLightFactor;
	return output;
}

technique TexturedShaded
{
	pass Pass0
	{
		VertexShader = compile VS_SHADERMODEL TexturedShadedVertexShader();
		PixelShader = compile PS_SHADERMODEL TexturedShadedPixelShader();
	}
}

// Textured

struct TexturedVSInput
{
	float4 Position : SV_POSITION0;
	float3 Normal : NORMAL;
	float2 TexCoords : TEXCOORD0;
};

struct TexturedVSOutput
{
	float4 Position : SV_POSITION;
	float3 Normal : NORMAL;
	float2 TexCoords : TEXCOORD0;
};


struct TexturedPSOutput
{
	float4 Color : COLOR0;
};


TexturedVSOutput TexturedVertexShader(TexturedVSInput input)
{
	TexturedVSOutput output = (TexturedVSOutput)0;

	output.Position = mul(input.Position, GetWorldViewProjection(xCameraView, xCameraProjection));
	/*output.Position = mul(input.Position, xCameraWorldViewProjection);*/
	output.TexCoords = input.TexCoords;

	return output;
}

TexturedPSOutput TexturedPixelShader(TexturedVSOutput input)
{
	TexturedPSOutput output = (TexturedPSOutput)0;

	output.Color = tex2D(TextureSampler, input.TexCoords);

	return output;
}

technique Textured
{
	pass Pass0
	{
		VertexShader = compile VS_SHADERMODEL TexturedVertexShader();
		PixelShader = compile PS_SHADERMODEL TexturedPixelShader();
	}
}
// Simple //

struct SimpleVSInput
{
	float4 Position : SV_POSITION;
	float4 Color : COLOR0;
};

struct SimpleVSOutput
{
	float4 Position : SV_POSITION;
	float4 Color : COLOR0;
	float3 Position3D : TEXCOORD0;
};


struct SimplePSOutput
{
	float4 Color : COLOR0;
};


SimpleVSOutput SimpleVertexShader(SimpleVSInput input)
{
	SimpleVSOutput output = (SimpleVSOutput)0;

	output.Position = mul(input.Position, GetWorldViewProjection(xCameraView, xCameraProjection));
	/*output.Position = mul(input.Position, xCameraWorldViewProjection);*/
	output.Color = input.Color;
	output.Position3D = (float3)input.Position;

	return output;
}

SimplePSOutput SimplePixelShader(SimpleVSOutput input)
{
	SimplePSOutput output = (SimplePSOutput)0;

	output.Color = input.Color;
	output.Color.rgb = input.Position3D.xyz;
	return output;
}

technique Simple
{
	pass Pass0
	{
		VertexShader = compile VS_SHADERMODEL SimpleVertexShader();
		PixelShader = compile PS_SHADERMODEL SimplePixelShader();
	}
}