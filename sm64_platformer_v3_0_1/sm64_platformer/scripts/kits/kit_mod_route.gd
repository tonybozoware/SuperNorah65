class_name KitModRoute
extends Resource
## A live link from something the player is doing to a Instruments setting, updated every
## frame while the kit is active. The source gives 0..1, shaped by `power`, then
## mapped onto out_min..out_max (straight, or exponential for frequencies).

enum Source {
	RUN,          ## the run meter: fills while you keep up speed, empties when you stop
	SPEED,        ## forward speed, 0 = still, 1 = top running speed
	FACING_NORTH, ## 1 facing north (-Z), 0.5 facing east or west, 0 facing south
	FACING_EAST,  ## 1 facing east (+X), 0.5 facing north or south, 0 facing west
	AIRTIME,      ## 0 on the ground, rising to 1 after airtime_full seconds in the air
	HEIGHT_SPEED, ## vertical speed: 0 = falling fast, 0.5 = still, 1 = rising fast
}

@export var source := Source.RUN
## A Instruments setting name as it appears in the Inspector, e.g. "cutoff", "drive",
## "pulse_width", "resonance", "dexed_volume".
@export var target := "cutoff"
@export var out_min := 0.0
@export var out_max := 1.0
## Exponential suits frequencies (cutoff); straight suits levels and amounts.
@export var exponential := false
## Shapes the source before mapping: 1 = straight, >1 = slow start, <1 = fast start.
@export var power := 1.0
@export var airtime_full := 1.5


func map(x: float) -> float:
	x = pow(clampf(x, 0.0, 1.0), power)
	if exponential and out_min > 0.0 and out_max > 0.0:
		return out_min * pow(out_max / out_min, x)
	return lerpf(out_min, out_max, x)
