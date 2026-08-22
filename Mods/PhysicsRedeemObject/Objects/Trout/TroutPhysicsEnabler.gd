extends PhysicalBoneSimulator3D


@export var root:Node3D = null
func _ready():
	if root != null:
		self.position = root.position
		self.rotation = root.rotation
	physical_bones_start_simulation()
	print("Start Sim")
