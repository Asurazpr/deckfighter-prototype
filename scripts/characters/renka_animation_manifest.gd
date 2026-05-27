class_name RenkaAnimationManifest
extends RefCounted

const CHARACTER := "renka"
const FPS := 30
const RENDERS_ROOT := "res://assets/characters/renka/renders"
const SPRITESHEET_ROOT := "res://assets/characters/renka/renders/spritesheets"
const USE_SPRITESHEETS := true
const ANIMATIONS := {
	"idle": "renka_idle",
	"run_forward": "renka_forward_running",
	"run_backward": "renka_backward_running",
	"block": "renka_block",
	"light_punch": "renka_light_punch",
	"light_kick": "renka_light_kick",
	"heavy_punch": "renka_heavy_punch",
	"heavy_kick": "renka_heavy_kick",
	"light_hitstun": "renka_light_hitstun",
	"heavy_hitstun": "renka_heavy_hitstun",
	"uppercut": "renka_uppercut"
}
const FPS_OVERRIDES := {}
const LOOP_OVERRIDES := {
	"idle": true,
	"run_forward": true,
	"run_backward": true,
	"block": false,
	"light_punch": false,
	"light_kick": false,
	"heavy_punch": false,
	"heavy_kick": false,
	"light_hitstun": false,
	"heavy_hitstun": false,
	"uppercut": false
}
const SPRITESHEET_VISUAL_SCALES := {
	"idle": 2.0,
	"run_forward": 2.0,
	"run_backward": 2.0,
	"block": 2.0,
	"light_punch": 1.0,
	"light_kick": 2.0,
	"heavy_punch": 2.0,
	"heavy_kick": 2.0,
	"light_hitstun": 2.0,
	"heavy_hitstun": 2.0,
	"uppercut": 2.0
}
