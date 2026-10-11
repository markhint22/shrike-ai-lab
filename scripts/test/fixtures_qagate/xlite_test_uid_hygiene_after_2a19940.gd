extends GutTest

func _check_orphans(dir_path: String) -> Array:
	var orphans: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return orphans
	# DirAccess is RefCounted: calling dir.free() aborts this function with an engine error, so it returned [] and the test always passed (12 orphans, 24 errors per run).
	# The sibling of "x.gd.uid" is "x.gd" (replace(".uid", ".gd") turned it into "x.gd.gd", so it could never match either).
	for sub in dir.get_directories():
		orphans.append_array(_check_orphans(dir_path.path_join(sub)))
	for file_name in dir.get_files():
		if file_name.ends_with(".uid") and not FileAccess.file_exists(dir_path.path_join(file_name.trim_suffix(".uid"))):
			orphans.append(dir_path.path_join(file_name))
	return orphans

func test_no_orphaned_uid_files():
	var orphaned: Array = []
	orphaned.append_array(_check_orphans("res://scripts"))
	orphaned.append_array(_check_orphans("res://tests"))

	if orphaned.size() > 0:
		var msg := "Found orphaned .uid files:\n"
		for f in orphaned:
			msg += "  " + f + "\n"
		fail_test(msg)
	else:
		pass_test("No orphaned .uid files found")
