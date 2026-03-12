## autoloads/NeonEnvironment.gd  (stub — efekty wizualne są teraz bezpośrednio w Main.tscn)
## WorldEnvironment, CanvasModulate, PointLight2D i WaterRect są statycznymi węzłami w scenie.
extends Node

func setup(_world_node: Node2D) -> void:
	pass  # Efekty zarządzane przez World.gd bezpośrednio

func update_for_daytime(_is_night: bool) -> void:
	pass  # Zarządzane przez World._update_canvas_modulate()
