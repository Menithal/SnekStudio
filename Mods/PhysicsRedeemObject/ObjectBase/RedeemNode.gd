extends Node3D
class_name RedeemNode
## RedeemNode is *a scene* that has RedeemRigidBodies inside "RedeemObjects" 
## Its task is to Wrap the velocities for the Physical Redeem, such as a throwable or droppable, 
## Allow also each specific Redeem to consist of multiple components, instead of just a single one multiplied.
##
## Based on Old ThrownObject.gd by Kiri.

## Lifetime for the entire bundle
@export var remaining_lifetime : float = 5
## Offset or Radius from where the objects are dropped or thrown from..
@export var spawn_randomized_offset: float = 0.1;
# Target Bone for redeemable.
var target_bone: String = "Head"
## Randomize thrown velocity
@export var velocity_randomness: float = 0.2
var avatar_reference: Skeleton3D = null

var dropped_spawn_offset: Vector3 = Vector3(0.,4.,0.)
# Redeem scene loader that defines the entire Throwable/Droppable Mod.
var scene_loader_node: Node3D = null;
# Rigid bodies managed by this node.
var tracked_rigid_bodies : Array = []

# Collision tracking should be handled by each individual RigidBody
func rand_vec3():
	return Vector3((randf() - 0.5) * 2,
				(randf() - 0.5) * 2,
				(randf() - 0.5) * 2).normalized()

func set_redeem_rigid_body(redeem_rigid_body: RedeemRigidBody):
	redeem_rigid_body.visible = false
	# Add refernece to self
	redeem_rigid_body.redeem_controller = self
	# Track Rigid bodies added into the scene.
	tracked_rigid_bodies.append(redeem_rigid_body)
	
	if !redeem_rigid_body.look_at_avatar:
		var random_rotation_axis = rand_vec3()
		var random_rotation_velocity = randf() * PI * 2.0 * redeem_rigid_body.random_spin_amount
		redeem_rigid_body.angular_velocity = random_rotation_axis * random_rotation_velocity
	
	var target_position = Vector3(0.0, 1.8, 0.0)
	
	var bone_idx = avatar_reference.find_bone(target_bone)
	
	if bone_idx != -1:
		var bone_transform = avatar_reference.global_transform * avatar_reference.get_bone_global_pose(bone_idx)
		if bone_transform:
			target_position = bone_transform.origin
			
	if !redeem_rigid_body.aim_at_avatar:
		# Pick a random position, as an offset from the targeted bone, in front of
		# the character.
		var random_start_position = Vector3((randf() - 0.5) * 2,
				(randf() - 0.5) * 0.5,
				(randf() - 0.5)).normalized()
				
		var random_velocity = rand_vec3() * randf() * velocity_randomness
		 
		redeem_rigid_body.global_transform.origin = target_position + random_start_position
		
		## FIXME: instead use spawn location to start_position and use cone.
		
		redeem_rigid_body.linear_velocity = -random_start_position * 3.5 + random_velocity
		
		# Now let's do the math to give the projectile an arc. We're trying to find
		# time t, which is when the object would collide with the target, given the
		# velocity it has right now, if it were to go in a straight line.
		#
		#   random_start_position + bit_scene.linear_velocity * t = head_position
		#   (random_start_position - head_position) + bit_scene.linear_velocity * t = 0
		#   (random_start_position.length() - head_position.length()) + bit_scene.linear_velocity.length() * t = 0
		#   (random_start_position.length() - head_position.length()) = -bit_scene.linear_velocity.length() * t
		#   ((random_start_position.length() - head_position.length())) / -bit_scene.linear_velocity.length() = t
		var t = (random_start_position - target_position).length() / redeem_rigid_body.linear_velocity.length()
		# Determine a vertical velocity offset such that gravity would perfectly
		# negate it by the time we reach time t.
		## FIXME: Somethings off with this math
		var vertical_velocity_offset = 9.8 * t / 3.0
		redeem_rigid_body.linear_velocity[1] += vertical_velocity_offset
		redeem_rigid_body.set_gravity_scale(1.0)
		 
	else:
		var random_position_vector = rand_vec3()  
		redeem_rigid_body.position = target_position + dropped_spawn_offset + random_position_vector * spawn_randomized_offset
		# Gravity does the rest :) 
	redeem_rigid_body.visible = true


func _ready():
	if get_child_count() == 0:
		printerr("RedeemNode: does not contain children")
		queue_free()
		return
	if avatar_reference == null:
		printerr("RedeemNode: Avatar reference not found")
		queue_free()
		return
	
	if scene_loader_node == null:
		print("Scene Loader node doesnt exist. Assuming in Editor.")
		return
		
	## Cycle through all children (including newly cloned ones!)
	for child in get_children():
		if child is not RedeemRigidBody:
			printerr ("RedeemNode: RedeemObjects does not contain expected RedeemRigidBody! Destroying {}.", child.name)
			child.queue_free()
			continue
		
		set_redeem_rigid_body(child as RedeemRigidBody)

func _physics_process(delta):
	remaining_lifetime -= delta
	if remaining_lifetime < 0.0:
		# Destroy ALL Tracked rigid bodies
		for tracked_rigid_body: Node in tracked_rigid_bodies:
			# This makes sure that If rigid body that is no longer child of this controller scene (such as those attached to something)
			# that it is still cleaned up
			if tracked_rigid_body != null and tracked_rigid_body.is_queued_for_deletion() != false:
				tracked_rigid_body.queue_free()
			
		# Clean up the controller
		queue_free()
		return
