extends Node
## Force-reloads every project script so Godot re-analyses all of them.
##
## Godot prints GDScript warnings only while a debugger is attached. A headless
## run — `make test`, CI — therefore never shows them, so they pile up until
## someone opens the project in the editor's debugger. `check-warnings.sh`
## registers this node as an autoload for a single run and starts the game with
## `-d`, which makes Godot print every warning it can see; the shell script
## fails the run if anything came out of `GDScript::reload`.
##
## Nothing happens unless `--warning-sweep` is passed as a user argument, so a
## stray registration in project.godot is harmless:
##
##     godot --headless -d --path . -- --warning-sweep

const SWEEP_ROOTS: Array[String] = ["res://scripts", "res://tests"]


func _ready() -> void:
	if not "--warning-sweep" in OS.get_cmdline_user_args():
		return
	var scripts := _scripts_under(SWEEP_ROOTS)
	for path in scripts:
		var script := ResourceLoader.load(path)
		if script is GDScript:
			script.reload(true)
	print("WARNING_SWEEP_DONE scripts=%d" % scripts.size())
	get_tree().quit()


## Every .gd file under `roots`, sorted so a sweep reads the same every run.
func _scripts_under(roots: Array[String]) -> Array[String]:
	var paths: Array[String] = []
	for root in roots:
		_collect(root, paths)
	paths.sort()
	return paths


func _collect(path: String, paths: Array[String]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with(".") and entry != "addons":
				_collect(full, paths)
		elif entry.ends_with(".gd"):
			paths.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
