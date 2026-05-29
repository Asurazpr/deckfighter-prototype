class_name KaiAnimationManifest
extends RefCounted

const CHARACTER := "kai"
const FPS := 30
const RENDERS_ROOT := "res://assets/characters/kai/renders/png_sequences"
const ANIMATIONS := {
	"idle": "kai_idle",
	"walking": "kai_walking",
	"block": "kai_block",
	"light_hitstun": "kai_light_hitstun",
	"heavy_hitstun": "kai_heavy_hitstun",
	"light_punch": "kai_light_punch",
	"light_kick": "kai_light_kick",
	"heavy_punch": "kai_heavy_punch",
	"heavy_kick": "kai_heavy_kick"
}
const FPS_OVERRIDES := {}
const LOOP_OVERRIDES := {
	"idle": true,
	"walking": true,
	"block": false,
	"light_hitstun": false,
	"heavy_hitstun": false,
	"light_punch": false,
	"light_kick": false,
	"heavy_punch": false,
	"heavy_kick": false
}
