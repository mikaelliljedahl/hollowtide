class_name PlayerConfig extends RefCounted

# Fasta fysikuppdateringar per sekund.
const PHYSICS_TICKS_PER_SECOND: int = 60
# Storlek på en tile i pixlar.
const TILE_SIZE: int = 64
# Spelets viewport-bredd i pixlar.
const VIEWPORT_WIDTH: int = 1920
# Spelets viewport-hojd i pixlar.
const VIEWPORT_HEIGHT: int = 1080
# Fonstrets skalade bredd i pixlar.
const WINDOW_WIDTH: int = 1920
# Fonstrets skalade hojd i pixlar.
const WINDOW_HEIGHT: int = 1080
# Staende kollisionsformens bredd i pixlar.
const STANDING_WIDTH: float = 56.0
# Staende kollisionsformens hojd i pixlar.
const STANDING_HEIGHT: float = 176.0
# Hukformens bredd matchar spelarens andra former.
const CROUCH_WIDTH: float = 56.0
# 104 px ger tydlig markering och 72 px extra takmarginal utan att bli en bollpose.
const CROUCH_HEIGHT: float = 104.0
# Hukformens mittpunkt fran fotorigo.
const CROUCH_CENTER_Y: float = -52.0
# Bollens kollisionsforms bredd i pixlar.
const BALL_WIDTH: float = 56.0
# Bollens kollisionsforms hojd i pixlar.
const BALL_HEIGHT: float = 56.0

# Hogsta ganghastighet i pixlar per sekund.
const WALK_MAX: float = 480.0
# Initialt lopforslag: 1.5x ganghastighet. Endast horisontellt toppfartstak.
const RUN_MAX: float = 720.0
# Acceleration pa marken i pixlar per sekund-kvadrat.
const GROUND_ACCEL: float = 4000.0
# Friktion utan input pa marken i pixlar per sekund-kvadrat.
const GROUND_FRICTION: float = 6000.0
# Acceleration i luften i pixlar per sekund-kvadrat.
const AIR_ACCEL: float = 3040.0
# Friktion utan input i luften i pixlar per sekund-kvadrat.
const AIR_FRICTION: float = 1760.0
# Multiplikator for acceleration vid riktningsbyte.
const TURN_BOOST: float = 1.8

# Begynnelsehastighet uppat, med negativ y-riktning i Godot.
const JUMP_VELOCITY: float = 1280.0
# Gravitation under hoppets stigning i pixlar per sekund-kvadrat.
const GRAVITY_RISING: float = 3200.0
# Gravitation under hoppets fall i pixlar per sekund-kvadrat.
const GRAVITY_FALLING: float = 4640.0
# Hogsta fallhastighet nedat i pixlar per sekund.
const TERMINAL_VELOCITY: float = 1760.0
# Kvarvarande uppatgaende hastighet nar hoppknappen slapps.
const JUMP_CUTOFF: float = 0.40
# Tid efter markkontakt da hopp fortfarande far losas.
const COYOTE_TIME: float = 0.10
# Tid fore landning da ett hopptryck buffras.
const JUMP_BUFFER: float = 0.12
# Hastighetsintervall runt apex dar apex-hang aktiveras.
const APEX_THRESHOLD: float = 160.0
# Gravitationens multiplikator under apex-hang.
const APEX_GRAVITY_MUL: float = 0.75
# Accelerationens multiplikator under apex-hang.
const APEX_ACCEL_MUL: float = 1.15

# Hogsta fallhastighet vid vaggglidning nedat.
const WALL_SLIDE_SPEED: float = 680.0
# Uppatgaende hastighet vid vagghopp; identisk med vanligt hopp.
const WALL_JUMP_VELOCITY: float = 1280.0
# Utatgaende hastighet fran vaggen vid vagghopp.
const WALL_PUSH_VELOCITY: float = 620.0
# Tid da vagrat input ignoreras efter vagghopp.
const WALL_INPUT_LOCK: float = 0.14
# Tid da vagghopp tillats efter att vaggkontakt slappt.
const WALL_COYOTE: float = 0.10
# Hojd over fotterna for vaggraycastarnas ursprung.
const WALL_CHECK_OFFSET: float = 88.0

# Hogsta rullhastighet i pixlar per sekund.
const ROLL_MAX: float = 580.0
# Bollens acceleration i pixlar per sekund-kvadrat.
const ROLL_ACCEL: float = 2600.0
# Bollens friktion utan input i pixlar per sekund-kvadrat.
const ROLL_FRICTION: float = 2160.0
# Langd pa staende-till-boll-overgangen i sekunder.
const SLIP_DURATION: float = 0.12

# Siktets axel- och mynningsoffset, relativt spelarens fotorigo.
const AIM_SHOULDER_OFFSET: Vector2 = Vector2(0.0, -120.0)
const AIM_MUZZLE_DISTANCE: float = 52.0
# Mätt pa dedicated standing firing pose, whose feet align to row 240.
const STANDING_HORIZONTAL_MUZZLE_OFFSET: Vector2 = Vector2(71.0, -161.0)
# Measured from player_shoot_horizontal_air.png muzzle tip, feet aligned to row 240.
const AIR_HORIZONTAL_MUZZLE_OFFSET: Vector2 = Vector2(81.0, -140.0)
# Measured from player_crouch_shoot_horizontal.png muzzle tip, feet aligned to row 240.
const CROUCH_HORIZONTAL_MUZZLE_OFFSET: Vector2 = Vector2(70.0, -72.0)
# Animation cadence only; physics constants remain unchanged.
const RUN_ANIMATION_SPEED_SCALE: float = 1.15

# Halsokonstanter enligt game-feel.md.
const MAX_HEALTH: int = 100
const INVULN_TIME: float = 1.00
const HURT_KNOCKBACK_X: float = 520.0
const HURT_KNOCKBACK_Y: float = -480.0
const HURT_INPUT_LOCK: float = 0.18
const INVULN_FLASH_HZ: float = 15.0

# Kamera-forflyttning framfor spelaren i pixlar.
const CAMERA_LOOK_AHEAD: float = 128.0
# Tid for kamera-forflyttning till ny blickriktning i sekunder.
const CAMERA_LOOK_AHEAD_DURATION: float = 0.40
# Kamera-positionens smoothing-hastighet.
const CAMERA_SMOOTHING_SPEED: float = 8.0
