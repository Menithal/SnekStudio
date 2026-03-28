extends RigidBody3D
class_name RedeemRigidBody

## Base Redeem RigidBody is an extension of a RigidBody that manages effects after events.
## Should be used in place of Rigid Body in a Redeem object scene

## It manages its own lifetime, and events that occur when it collides with an object, 
## including stickyness, and cleanup behavior past the collision

## Can object stick on collision?
@export var sticky : bool = true
## Does the object have a chance of "sticking" on avatar collision
@export var stickiness_chance : float = 0.5
## How long should the object stick to avatar
@export var stickiness_time : float = 5.0
## Lifetime of the object in total in scene
@export var remaining_lifetime : float = 10.0
## Max amount of random spin on spawn
@export var random_spin_amount: float = 1
## Amount of damping on the spin over time.
@export var spin_damping: float = 2.0
## Add this scene on collision
@export var collide_scene: PackedScene = null
## Force we want to add to the avatar head on collision
@export var collision_force : float = 1.0
## Should we clear the RedeemObject scene collision?
@export var clear_on_collision : bool = false
## Should the object be thrown AT the avatar. Else dropped
@export var aim_at_avatar: bool = false
## Should the object look at towards the avatar? If yes, do not apply any spin,
@export var look_at_avatar: bool = false
@export var randomized_pitch: float = 0.2

@export var collision_sound : AudioStream = null

@export var physical_bone_sim: PhysicalBoneSimulator3D = null
@export var reparent_node: Node3D = null

var attached_to_body = false
var collision_shape: CollisionShape3D = null
var redeem_controller: RedeemNode = null

var _orig_parent = null
var _impacted = false
var _audio_stream_player: AudioStreamPlayer3D = null

func _set_physics_active(active : bool):
	if not active:
		linear_velocity = Vector3(0.0, 0.0, 0.0)
		angular_velocity = Vector3(0.0, 0.0, 0.0)
		collision_mask = 0
		collision_layer = 0
		set_gravity_scale(0.0)
	else:
		collision_mask = 1
		set_gravity_scale(1.0)

func _reattach_to_body(body):
	if attached_to_body:
		return
	
	if not (body is CharacterBody3D):
		return
	
	if get_node_or_null("..") is CharacterBody3D:
		return
	
	linear_velocity = Vector3(0.0, 0.0, 0.0)
	angular_velocity = Vector3(0.0, 0.0, 0.0)
	collision_mask = 0
	collision_layer = 0
	
	assert(not _orig_parent)
	_orig_parent = get_node("..")
	var old_global_transform = get_global_transform()
	_orig_parent.call_deferred("remove_child", self)
	body.call_deferred("add_child", self)
	call_deferred("set_global_transform", old_global_transform)
	attached_to_body = true
	

func create_collision_scene():
	collide_scene.can_instantiate()
	
	var collide_object = collide_scene.instantiate()
	
	get_parent().add_child(collide_object) 
	collide_object.position = self.position
	collide_object.rotation = self.rotation

func _on_RigidBody_body_entered(body):
	if body is not CharacterBody3D:
		return
	if attached_to_body:
		return
	
	var collision_point = global_transform.origin
	var collision_point_extended = global_transform.origin + linear_velocity
	var body_part_pos = body.global_transform.origin - Vector3(0.0, 0.25, 0.0)
	
	var dir1 = (collision_point - body_part_pos).normalized()
	var dir2 = (collision_point_extended - body_part_pos).normalized()
	
	var rotation_axis = dir1.normalized().cross(dir2.normalized())
	var rotation_angle = acos(dir1.dot(dir2)) * 2
	if rotation_angle > 0.5:
		rotation_angle = 0.5
	if rotation_angle < -0.5:
		rotation_angle = -0.5
	
	rotation_angle *= -collision_force
	
	var q = Quaternion(
		rotation_axis.normalized(), rotation_angle)
	if sticky and randf() < stickiness_chance:
		_reattach_to_body(body)
		set_gravity_scale(0.0)
	else:
		# We no longer have to move in a straight line. Enable gravity and just
		# let the projectile fall down.
		set_gravity_scale(1.0)
	
	if redeem_controller:
		print("Rigid Body !", body.name )
		redeem_controller.scene_loader_node.add_head_impact_rotation(
			(body.global_transform.inverse() * Transform3D(q)).basis.get_rotation_quaternion() )

	if not _impacted:
		if physical_bone_sim != null and reparent_node != null:
			# TODO: Solve stickyness issue Currently if sticky, it will not "stick" anymore
			var angular = angular_velocity
			var linear_impulse = linear_velocity /  physical_bone_sim.get_children().size()
			collision_shape.set_deferred("disabled", true)
			freeze = true
			var main_transform = reparent_node.get_global_transform_interpolated()
			
			remove_child(reparent_node)
			get_parent().add_child(reparent_node)
			reparent_node.transform = main_transform
			
			collision_shape.set_deferred("disabled", false)
			freeze = false
			physical_bone_sim.active = true
			physical_bone_sim.physical_bones_start_simulation()
			
		elif clear_on_collision:
			freeze = true
			visible = false
			queue_free()
			
		if _audio_stream_player != null:
			get_parent().add_child(_audio_stream_player)
		
		if collide_scene != null:
			create_collision_scene()
			
		_impacted = true

## Rigid Body will only handle its stickyness. The Redeem Node will handle cleanup
## This will keep consistancy.
func _physics_process(delta):
	stickiness_time -= delta
	remaining_lifetime -= delta
	
	# Handle stickiness wearing off.
	if stickiness_time < 0 and _orig_parent:
		stickiness_time = 999.0
		_set_physics_active(true)
		sleeping = false
		
		# Remove us from the character and re-attach us to the original parent.
		var current_global_transform = get_global_transform()
		
		## FIXME: Instead of doing parent_instance manipulation ,what about using constraints instead?
		if is_instance_valid(_orig_parent):
			_orig_parent.add_child(self)
			global_transform = current_global_transform
			_orig_parent = null
		else:
			queue_free()


func _ready() -> void:
	
	for child in get_children():
		if child is CollisionShape3D:
			collision_shape = child as CollisionShape3D
		
	spin_damping = angular_damp
	# Make sure these are enabled and scripts are connected
	contact_monitor = true
	max_contacts_reported = 1
	if physical_bone_sim != null:
		physical_bone_sim.active = false
		
	if collision_sound != null:
		_audio_stream_player = AudioStreamPlayer3D.new()
		_audio_stream_player.name = "CollisionSoundNode"
		_audio_stream_player.stream = collision_sound
		_audio_stream_player.autoplay = true
		_audio_stream_player.pitch_scale = 1.0 + (randf() * 2.0 - 1.0) * 0.2
		
		
		#if head is not null:
		#	look_at((head as Node3D))
	# if the redeem in question doesnt have everything bound yet if
	# someone new forgot to bind the connection
	if not is_connected("body_entered", _on_RigidBody_body_entered):
		connect("body_entered", _on_RigidBody_body_entered)

	
