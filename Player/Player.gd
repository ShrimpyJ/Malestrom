extends KinematicBody

###################-VARIABLES-####################

# Camera
export(float) var mouse_sensitivity = 18.0
export(NodePath) var head_path = "Head"
export(NodePath) var cam_path = "Head/Camera"
export(float) var FOV = 90.0
var mouse_axis := Vector2()
onready var head: Spatial = get_node(head_path)
onready var cam: Camera = get_node(cam_path)
# Move
var velocity := Vector3()
var direction := Vector3()
var move_axis := Vector2()
var snap := Vector3()
var sprint_enabled := true
var sprinting := false
# Walk
const FLOOR_MAX_ANGLE: float = deg2rad(46.0)
export(float) var gravity = 33.0
export(int) var walk_speed = 22
export(int) var sprint_speed = 55
export(int) var crouch_speed = 11
export(int) var slide_speed = 35
export(float) var crouch_mul = 0.5
export(int) var acceleration = 9
export(int) var deacceleration = 8

export(float, 0.0, 1.0, 0.05) var air_control = 0.5
export(int) var jump_height = 12
export(float) var sprint_cooldown = 2
export(float) var sprint_duration = 0.8
export(float, 0.0, 1.0, 0.05) var sprint_air_control = 0.5
export(float) var double_jump_mul = 1.1

var _speed: int
var _is_sprinting_input := false
var _is_jumping_input := false
var _is_double_input := false
var _is_crouch_input := false
var sprint_timer : float
var can_double_jump : bool
var jump_x_dir : float

##################################################

# Called when the node enters the scene tree
func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	cam.fov = FOV

# Called every frame. 'delta' is the elapsed time since the previous frame
func _process(_delta: float) -> void:
	if _is_crouch_input:
		cam.v_offset = -0.5
	else:
		cam.v_offset = 0
	sprint_timer += _delta
	
	move_axis.x = Input.get_action_strength("move_forward") - Input.get_action_strength("move_backward")
	move_axis.y = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")

	# Double Jump
	if not is_on_floor() and can_double_jump and Input.is_action_just_pressed("move_jump"):
		_is_double_input = true
		can_double_jump = false
	
	if is_on_floor():
		can_double_jump = true
		
	# Jump
	if Input.is_action_just_pressed("move_jump"):
		_is_jumping_input = true
	
	# Sprint/dash
	if Input.is_action_just_pressed("move_sprint") and sprint_timer > sprint_cooldown:
		$dash.play()
		_is_sprinting_input = true
		sprint_timer = 0
	
	# Crouch/slide
	if Input.is_action_pressed("move_crouch"):
		_is_crouch_input = true
	if Input.is_action_just_released("move_crouch"):
		_is_crouch_input = false
	
	# Weapons
	if Input.is_action_just_pressed("shoot_primary"):
		$pistol.play()


# Called every physics tick. 'delta' is constant
func _physics_process(delta: float) -> void:
	walk(delta)


# Called when there is an input event
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_axis = event.relative
		camera_rotation()


func walk(delta: float) -> void:
	direction_input()
	
	if is_on_floor() or _is_double_input:
		snap = -get_floor_normal() - get_floor_velocity() * delta
		
		# Workaround for sliding down after jump on slope
		if velocity.y < 0:
			velocity.y = 0
		
		jump()
	else:
		# Workaround for 'vertical bump' when going off platform
		if snap != Vector3.ZERO && velocity.y != 0:
			velocity.y = 0
		
		snap = Vector3.ZERO
		
		velocity.y -= gravity * delta
	
	sprint(delta)
	
	accelerate(delta)
	
	velocity = move_and_slide_with_snap(velocity, snap, Vector3.UP, true, 4, FLOOR_MAX_ANGLE)
	_is_jumping_input = false
	_is_double_input = false
	#_is_crouch_input = false
	sprint_timer += delta
	if sprint_timer > sprint_duration:
		_is_sprinting_input = false


func camera_rotation() -> void:
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return
	if mouse_axis.length() > 0:
		var horizontal: float = -mouse_axis.x * (mouse_sensitivity / 100)
		var vertical: float = -mouse_axis.y * (mouse_sensitivity / 100)
		
		mouse_axis = Vector2()
		
		rotate_y(deg2rad(horizontal))
		head.rotate_x(deg2rad(vertical))
		
		# Clamp mouse rotation
		var temp_rot: Vector3 = head.rotation_degrees
		temp_rot.x = clamp(temp_rot.x, -90, 90)
		head.rotation_degrees = temp_rot


func direction_input() -> void:
	direction = Vector3()
	var aim: Basis = get_global_transform().basis
	if move_axis.x >= 0.5:
		direction -= aim.z
	if move_axis.x <= -0.5:
		direction += aim.z
	if move_axis.y <= -0.5:
		direction -= aim.x
	if move_axis.y >= 0.5:
		direction += aim.x
	direction.y = 0
	direction = direction.normalized()


func accelerate(delta: float) -> void:
	# Where would the player go
	var _temp_vel: Vector3 = velocity
	var _temp_accel: float
	#var _target: Vector3 = direction * _speed
	var _target: Vector3
	if  _is_crouch_input:
		if _is_sprinting_input:
			_target = direction * slide_speed
		else:
			_target = direction * crouch_speed
	else:
		_target = direction * _speed
	
	_temp_vel.y = 0
	if direction.dot(_temp_vel) > 0:
		_temp_accel = acceleration
		
	else:
		_temp_accel = deacceleration
		
	
	if not is_on_floor():
		if sprinting:
			_temp_accel *= sprint_air_control
		else:
			_temp_accel *= air_control

	# Interpolation
	_temp_vel = _temp_vel.linear_interpolate(_target, _temp_accel * delta)
	
	if sprinting and sprint_timer > 0.2:
		velocity.x = velocity.x
		velocity.z = velocity.z
		if not is_on_floor():
			velocity.y = 0
	else:
		velocity.x = _temp_vel.x
		velocity.z = _temp_vel.z
	
	# Make too low values zero
	if direction.dot(velocity) == 0:
		var _vel_clamp := 0.01
		if abs(velocity.x) < _vel_clamp:
			velocity.x = 0
		if abs(velocity.z) < _vel_clamp:
			velocity.z = 0


func jump() -> void:
	if _is_jumping_input:
		velocity.y = jump_height
		snap = Vector3.ZERO
		if not _is_double_input:
			jump_x_dir = move_axis.y

	if _is_double_input:
		velocity.y = jump_height * double_jump_mul
		if jump_x_dir == 1 and move_axis.y == -1 or jump_x_dir == -1 and move_axis.y == 1:
			velocity.x *= -1
		snap = Vector3.ZERO

func sprint(delta: float) -> void:
	if can_sprint():
		_speed = sprint_speed
		if not is_on_floor():
			_speed *= 1
		cam.set_fov(lerp(cam.fov, FOV * 1.05, delta * 8))
		sprinting = true
		
	else:
		_speed = walk_speed
		cam.set_fov(lerp(cam.fov, FOV, delta * 8))
		sprinting = false


func can_sprint() -> bool:
	return _is_sprinting_input
	#return (sprint_enabled and is_on_floor() and _is_sprinting_input and move_axis.x >= 0.5)
