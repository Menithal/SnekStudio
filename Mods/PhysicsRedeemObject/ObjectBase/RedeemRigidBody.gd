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

var attached_to_body = false
var redeem_controller: RedeemNode = null;

var _orig_parent = null
var _impacted = false

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
	print("Create Collision Scene")
	collide_scene.can_instantiate()
	
	var collide_object = collide_scene.instantiate()
	
	collide_scene.position = self.position
	collide_scene.rotation = self.rotation
	get_parent().append(collide_object) 
	#get_parent().add_child(collide_scene)
	#collide_scene.position = position
	#collide_scene.rotation = rotation

func _on_RigidBody_body_entered(body):
	print("Some Collission spotted?")
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
	
	# FIXME: Don't hardcode head rotation. Make it select the right bone!
	if redeem_controller:
		redeem_controller.add_head_impact_rotation(
			(body.global_transform.inverse() * Transform3D(q)).basis.get_rotation_quaternion())
			
	# If we have a post-impact animation defined, then reset the animation time
	# to the beginning.
	# FIXME: Move sprite frames management to its own node.
	#if len(sprite_frames_after_impact):
	#	_animation_time = 0.0
	
	if _impacted:
		if collide_scene != null:
			create_collision_scene()
			
		if clear_on_collision == null:
			self.queue_free()
		
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

# Attempt to determine total visible AABB for collision approximations.
func _find_total_aabb(node, indent=""):
	if not (node is Node3D):
		return AABB()
		
	var node_transform : Transform3D = node.transform
	
	var aabb : AABB = AABB()
	
	if node is VisualInstance3D and node.visible:
		aabb = node_transform * node.get_aabb()
		
	for child in node.get_children():
		var child_aabb = _find_total_aabb(child, indent + "  ")
		if aabb.size == Vector3(0.0, 0.0, 0.0):
			aabb = child_aabb
		else:
			aabb = aabb.merge(child_aabb)
	return aabb

func _ready() -> void:
	spin_damping = angular_damp
	# Transferred these over from ThrownObject
	#if redeem_controller:
	#	redeem_controller.
	# Attempt to determine the max AABB of our visual models and use it as a
	# guess for a radius for the sphere collider.
	# 
	# FIXME: If we have an AABB maybe we should just do a box collider.
	# FIXME: Work for sprites, too.
	var max_aabb : AABB = _find_total_aabb(self)
	if max_aabb != AABB():
		if $CollisionShape.shape is SphereShape3D:
			var collision_sphere = $CollisionShape.shape.duplicate()
			$CollisionShape.shape = collision_sphere
			var max_dim = max(
				abs(max_aabb.position.x),
				abs(max_aabb.position.y),
				abs(max_aabb.position.x + max_aabb.size.x),
				abs(max_aabb.position.y + max_aabb.size.y))
			collision_sphere.set_radius(max_dim)
