# SceneLoader

`SceneLoader` es un Autoload persistente. El juego inicia en `bootstrap.tscn` y
el valor `INITIAL_SCENE_ID` decide qué interfaz se abre primero.

## Registrar escenas

Las escenas habituales pueden añadirse a `INITIAL_SCENES` en
`Scripts/SceneLoader/scene_loader.gd`:

```gdscript
&"main_menu": {
	"path": "res://Scenes/UI/main_menu.tscn",
	"category": SceneCategory.INTERFACE,
	"transition": &"fade",
},
&"route_01": {
	"path": "res://Scenes/Maps/route_01.tscn",
	"category": SceneCategory.MAP,
	"transition": &"fade",
},
&"pause_menu": {
	"path": "res://Scenes/UI/pause_menu.tscn",
	"category": SceneCategory.OVERLAY,
	"transition": &"fade",
},
```

También es posible registrarlas dinámicamente:

```gdscript
SceneLoader.register_scene(
	&"laboratory",
	"res://Scenes/Maps/laboratory.tscn",
	SceneLoader.SceneCategory.MAP
)
```

## Usos comunes

Desde un botón:

```gdscript
func _on_start_pressed() -> void:
	await SceneLoader.open_interface(&"main_menu")
```

Cambiar de mapa y enviar el punto de aparición:

```gdscript
await SceneLoader.load_map(
	&"route_01",
	&"north_gate",
	{"party": current_party}
)
```

En `_ready()` del mapa, los datos están disponibles antes de que el nodo entre
al árbol:

```gdscript
var payload: Dictionary = get_meta(&"scene_payload", {})
var spawn_point: StringName = payload.get("spawn_point", &"")
var map_data: Dictionary = payload.get("data", {})
```

Abrir y cerrar una interfaz sin reemplazar el mapa:

```gdscript
var pause_menu := await SceneLoader.show_overlay(&"pause_menu")
await SceneLoader.close_overlay(pause_menu)
```

Precargar una escena y volver a la anterior:

```gdscript
SceneLoader.preload_scene(&"route_01")
await SceneLoader.go_back()
```

Opciones de transición:

```gdscript
await SceneLoader.go_to(&"credits", {
	"transition": &"fade",
	"duration": 0.8,
	"color": Color(0.08, 0.0, 0.12),
	"pause_during_transition": true,
})
```

Para sumar transiciones futuras, se registra un nodo que implemente los
métodos asíncronos `play_out(options)` y `play_in(options)`:

```gdscript
SceneLoader.register_transition_driver(&"iris", iris_transition_node)
```

Las señales `load_started`, `load_progress`, `load_failed`, `scene_changed` y
`load_finished` permiten conectar una pantalla de carga o telemetría sin
acoplarla al cargador.
