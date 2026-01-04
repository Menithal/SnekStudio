extends Mod_Base
class_name PhysicsRedeemController

@export var bit_redeem = false
@export var throws_per_bit = 1
@export var redeem_name = "Throw something at my face"

@export var count_multiplier = 1
@export var selected_redeemables : Array[String] = []
@export var impact_rotation_return_speed: float = 5.0

@export var target_bone: String = "Head"
# List of every possible throwable object (full path).
var _redeem_controller_list = []

var _redeem_object_queue = []
var _redeem_object_cooldown = 0.0
var _redeem_object_cooldown_max = 0.05

var _head_impact_rotation_offset = Quaternion(0.0, 0.0, 0.0, 1.0)
# Handles Throwable/Droppable SCene Loading 
# Keep this in the same order as ValueTargetBone IDs in PhysicsRedeem Settings
var _target_bones = [
	"Head",
	"Neck",
	"Chest",
	"LeftArm",
	"RightArm"
]


func _ready():
	var local_dir = get_mod_path()
	var local_dir_objects : String = local_dir.path_join("Objects")

	# List of directories to (attempt to) search for throwable objects.
	var folders_with_redeemables = [
		local_dir_objects
	]
	
	# Add a directory with the same path, but relative to the binary. This will
	# let runtime-loaded files override internal files.
	if local_dir_objects.begins_with("res://"):
		folders_with_redeemables.append(
			OS.get_executable_path().get_base_dir().path_join(
				local_dir_objects.substr(len("res://"))))
	
	# Search those directories for any throwable objects, and load them.
	for path_to_list in folders_with_redeemables:
		var filelist = DirAccessWithMods.get_file_list(path_to_list)
		for file_name in filelist:
			# Load scene files directly. 
			if file_name.get_extension() == "tscn" and file_name.contains("ThrownObject_"):
				var local_path = path_to_list.path_join(file_name)
				_redeem_controller_list.append(local_path)
			
	
	print("done Loading Physics Redeem COntroller")
			# TODO: Add GLTF, OBJ, PNG, and VRM support.

func handle_channel_point_redeem(_redeemer_username, _redeemer_display_name, _redeem_title, _user_input):
	if not bit_redeem:
		if _redeem_title != "" and _redeem_title == redeem_name:
			for k in range(count_multiplier):
				throw_random_object()

func handle_channel_chat_message(_cheerer_username, _cheerer_display_name, _message, bits_count):
	if bit_redeem and bits_count > 0:
		var throw_count = (bits_count / throws_per_bit) * count_multiplier
		for k in range(throw_count):
			throw_random_object()

func throw_random_object():
	# If there's nothing to throw, just return.
	if len(selected_redeemables) < 1:
		printerr("Tried to throw/drop an object with nothing in the redeemable object list.")
		return

	# Find something to throw out of the list of stuff to throw and instantiate
	# it.
	var bit_scene_path = selected_redeemables.pick_random()

	var executable_path : String = OS.get_executable_path().get_base_dir()
	if bit_scene_path.begins_with(executable_path):
		bit_scene_path = bit_scene_path.substr(len(executable_path) + 1)

	var bit_scene_packed = load(bit_scene_path)
	if bit_scene_packed:
		var bit_scene = bit_scene_packed.instantiate()

		_redeem_object_queue.append(bit_scene)
		add_autodelete_object(bit_scene)
	else:
		push_error("Failed to load scene for redeemable: ", bit_scene_path)


func add_head_impact_rotation(rot : Quaternion):
	_head_impact_rotation_offset = _head_impact_rotation_offset * rot

func _process(delta):
	
	var skel = get_skeleton()
	
	var head_index = get_skeleton().find_bone("Head")
	var neck_index = get_skeleton().find_bone("Neck")
	var chest_index = get_skeleton().find_bone("Chest")

	var current_rotation
	
	if head_index != -1:
		current_rotation = skel.get_bone_pose_rotation(head_index)
		skel.set_bone_pose_rotation(head_index, _head_impact_rotation_offset * current_rotation)

	if neck_index != -1:
		current_rotation = skel.get_bone_pose_rotation(neck_index)
		skel.set_bone_pose_rotation(neck_index,
			_head_impact_rotation_offset.slerp(Quaternion(0.0, 0.0, 0.0, 1.0), 0.5) * current_rotation)

	if chest_index != -1:
		current_rotation = skel.get_bone_pose_rotation(chest_index)
		skel.set_bone_pose_rotation(chest_index,
			_head_impact_rotation_offset.slerp(Quaternion(0.0, 0.0, 0.0, 1.0), 0.75) * current_rotation)
	
	# SLERP back to rest rotation.
	_head_impact_rotation_offset = \
		_head_impact_rotation_offset.slerp(Quaternion(0.0, 0.0, 0.0, 1.0), delta * impact_rotation_return_speed)

func _physics_process(delta):
	if _redeem_object_queue.size():
		# Reset cooldown.
		_redeem_object_cooldown = _redeem_object_cooldown_max
		
		# Get the next object to throw off the queue.
		var _redeem_scene = _redeem_object_queue[0]
		_redeem_scene.avatar_reference = get_skeleton()
		_redeem_scene.scene_loader_node = self # Add Reference of Redeem Controller 
		_redeem_object_queue.pop_front()
		add_child(_redeem_scene)
	

func save_settings():
	var settings = {}
	settings["bit_redeem"] = bit_redeem
	settings["throws_per_bit"] = throws_per_bit
	settings["redeem_name"] = redeem_name
	settings["count_multiplier"] = count_multiplier
	settings["target_bone"] = target_bone
	settings["selected_redeemables"] = selected_redeemables.duplicate()
	return settings

func load_settings(settings_dict):
	bit_redeem = settings_dict["bit_redeem"]
	throws_per_bit = settings_dict["throws_per_bit"]
	redeem_name = settings_dict["redeem_name"]
	count_multiplier = settings_dict["count_multiplier"]
	target_bone = settings_dict["target_bone"]
	selected_redeemables = []
	for throwable in settings_dict["selected_redeemables"]:
		selected_redeemables.append(throwable)

func _create_settings_window():
	var ui = load(
		get_script().resource_path.get_base_dir() + "/" +
		"UI/PhysicsRedeem_Settings.tscn").instantiate()
	
	var ui_redeem_controller_list : ItemList = ui.get_node("%Value_RedeemableList")
	for redeemable_name in _redeem_controller_list:
		var file_name = redeemable_name.substr(
			redeemable_name.get_base_dir().length())
		if file_name.length() and file_name[0] == "/":
			file_name = file_name.substr(1)
		ui_redeem_controller_list.add_item(file_name)
	
	update_settings_ui(ui)
	ui.settings_modified.connect(update_settings_from_ui)

	return ui
	
func update_settings_ui(ui_window = null):
	
	if not ui_window:
		ui_window = get_settings_window()
	
	ui_window.get_node("%Value_BitOnlyRedeem").button_pressed = bit_redeem
	ui_window.get_node("%Value_ObjectsPerBit").value = throws_per_bit
	ui_window.get_node("%Value_CountMultiplier").value = count_multiplier
	ui_window.get_node("%Value_RedeemName").text = redeem_name
	var _target_bone_select_box: OptionButton= ui_window.get_node("%Value_TargetBone")
	_target_bone_select_box.select( _target_bones.find(target_bone)) 
	var ui__redeem_controller_list : ItemList = ui_window.get_node("%Value_RedeemableList")
	var item_count = ui__redeem_controller_list.item_count
	for k in range(item_count):
		var item_text = _redeem_controller_list[k]
		if item_text in selected_redeemables:
			ui__redeem_controller_list.select(k, false)
		else:
			ui__redeem_controller_list.deselect(k)

func update_settings_from_ui(ui_window = null):

	if not ui_window:
		ui_window = get_settings_window()

	bit_redeem = ui_window.get_node("%Value_BitOnlyRedeem").button_pressed
	throws_per_bit = ui_window.get_node("%Value_ObjectsPerBit").value
	count_multiplier = ui_window.get_node("%Value_CountMultiplier").value
	redeem_name = ui_window.get_node("%Value_RedeemName").text
	
	var _target_bone_select_box: OptionButton= ui_window.get_node("%Value_TargetBone")
	target_bone = _target_bones[_target_bone_select_box.get_selected_id()]
	
	var ui__redeem_controller_list : ItemList = ui_window.get_node("%Value_RedeemableList")
	var item_count = ui__redeem_controller_list.item_count
	selected_redeemables = []
	for k in range(item_count):
		if ui__redeem_controller_list.is_selected(k):
			selected_redeemables.append(_redeem_controller_list[k])
