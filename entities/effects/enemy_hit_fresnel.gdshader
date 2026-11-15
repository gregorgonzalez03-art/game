shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// Color base y propiedades de superficie
uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform float roughness : hint_range(0.0, 1.0) = 0.3;
uniform float metallic : hint_range(0.0, 1.0) = 0.1;

// Emisión base
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy : hint_range(0.0, 16.0) = 1.0;

// Efecto de Impacto Cinético (Fresnel + Flash blanco puro)
uniform float hit_flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 hit_flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float fresnel_power : hint_range(0.5, 8.0) = 2.5;

// Efecto de Disolución Procedural (Noise + Borde de energía neón)
uniform float dissolve_amount : hint_range(0.0, 1.0) = 0.0;
uniform float dissolve_edge_width : hint_range(0.005, 0.25) = 0.06;
uniform vec4 dissolve_edge_color : source_color = vec4(0.0, 0.95, 1.0, 1.0);
uniform float noise_scale : hint_range(1.0, 30.0) = 10.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Ruido procedural pseudo-3D ultra rápido y sin texturas externas
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float noise2D(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float val = 0.0;
	float amp = 0.55;
	for (int i = 0; i < 3; i++) {
		val += amp * noise2D(p);
		p *= 2.1;
		amp *= 0.45;
	}
	return val;
}

void fragment() {
	// 1. Disolución con ruido procedural
	if (dissolve_amount > 0.0) {
		vec2 noise_coords = UV * noise_scale + vec2(world_pos.x * 0.35, world_pos.z * 0.35);
		float n = fbm(noise_coords);

		if (n < dissolve_amount) {
			discard;
		}

		float edge = smoothstep(dissolve_amount, dissolve_amount + dissolve_edge_width, n);
		if (edge < 1.0) {
			float burn = (1.0 - edge) * 5.0;
			EMISSION += dissolve_edge_color.rgb * burn;
		}
	}

	// 2. Albedo base y textura opcional
	vec4 base_color = albedo_color * texture(albedo_texture, UV);

	// 3. Fresnel (ángulo de incidencia hacia la cámara)
	float n_dot_v = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fresnel = pow(1.0 - n_dot_v, fresnel_power);

	// 4. Efecto de Impacto Cinético (Hit Flash)
	vec3 flash_rgb = hit_flash_color.rgb;
	ALBEDO = mix(base_color.rgb, flash_rgb, hit_flash * 0.85);
	ROUGHNESS = roughness;
	METALLIC = metallic;

	// Emisión combinada: emisión base + Fresnel de impacto superbrillante
	vec3 base_emission = emission_color.rgb * emission_energy;
	vec3 impact_emission = flash_rgb * ((fresnel * 4.0) + 1.5) * hit_flash;

	EMISSION += base_emission + impact_emission;
}
