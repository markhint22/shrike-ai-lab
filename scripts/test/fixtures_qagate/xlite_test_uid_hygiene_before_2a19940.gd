extends GutTest

func _check_orphans(dir_path: String) -> Array:
	var orphans: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return orphans
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if dir.current_is_dir():
			if file_name != "." and file_name != "..":
				orphans.append_array(_check_orphans(dir_path.path_join(file_name)))
		else:
			if file_name.ends_with(".uid"):
				var gd_path := dir_path.path_join(file_name.replace(".uid", ".gd"))
				if not FileAccess.file_exists(gd_path):
					orphans.append(dir_path.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()
	dir.free()
	return orphans

func test_no_orphaned_uid_files():
	var orphaned: Array = []
	orphaned.append_array(_check_orphans("res://scripts"))
	orphaned.append_array(_check_orphans("res://tests"))

	if orphaned.size() > 0:
		var msg := "Found orphaned .uid files:\n"
		for f in orphaned:
			msg += "  " + f + "\n"
		assert_false(true, msg)
	else:
		assert_true(true, "No orphaned .uid files found")
