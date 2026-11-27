# Belium — contexto para Claude Code

> Generado el 2026-11-26 desde una sesión de Claude Desktop (proyecto de claude.ai «Modelado 3D»). Resume lo hecho hasta hoy, las técnicas usadas y las reglas de trabajo.
> Si algo de aquí contradice lo que ves en disco, manda el disco. Actualiza este archivo al cerrar cada hito.
> Responde siempre en **español** y de forma **concisa**.

## 1. Qué es el proyecto

**Belium** es un fangame narrativo de Pokémon sobre Cyrus (antes «Belium») y Cynthia. El mapa jugable actual es un **overworld 3D** (`Maps/map_001_3d.tscn`, pueblo **Leaftown / Hojaverde**, jugador `CynthiaPlayer3D`).

Documentación ya existente en el repo (léela solo cuando la tarea lo pida; no está importada aquí):
- `Docs/Docs_Belium/00_PROJECT_BIBLE.md` … `12_ROADMAP.md`: canon narrativo, personajes, sistemas, audio, producción.
- `Docs/Docs_Belium/07_GODOT_ARCHITECTURE.md` y `08_ASSET_PIPELINE.md`: arquitectura y pipeline de assets. Describen el plan 2D inicial; el mapa actual es 3D, así que pueden estar desactualizados.
- `Docs/camera_regions.md`, `map_layers_review.md`, `pokemon_npcs.md`, `save_system.md`, `scene_loader.md`, `tall_grass.md`.

## 2. Stack y entorno

- **Godot 4.7.2**, Forward Plus, **Jolt Physics**, D3D12 en Windows, MSAA 3D = 3. Viewport 1080×720, stretch `canvas_items`/`expand`. Escena principal: `res://Scenes/bootstrap.tscn`. Se programa en GDScript.
- **Autoloads**: `SceneLoader` (`Scripts/SceneLoader/scene_loader.gd`), `SaveManager` (`Scripts/Save/save_manager.gd`), `Ambiente` (`Scenes/Overworld/world_environment.tscn`).
- **Addons habilitados** (`project.godot`): `belium_dialogue_compiler`, `road-generator`, `sky_3d`, `terrain_3d` (**Terrain3D 1.1.0**). Presente pero **no habilitado**: `godot_ai` (ver §8).
- Capa de render 20 = «Ground Decals».
- Máquina del usuario: Windows x64. **Blender 5.2.2**.
- Rutas:
  - Proyecto Godot: `C:\Users\Beltz\Documents\demo\belium` (esta carpeta).
  - Repo de Blender: `C:\Users\Beltz\Desktop\repos\blender` (exports en `exported\`).
  - Skills de gamedev: `C:\Users\Beltz\.agents` (ver §7).
- Convenciones de recursos: `Resources/Materials/3D/{Map,Models,Shared,Textures}`.
  - `Models/` guarda los `.glb` (y los PNG que Godot extrae, con prefijo `<glb>_<nombre>.png`).
  - `Textures/` guarda las texturas canónicas (`Grass Ground.png`, `Dirt Ground.png`…). No duplicar texturas con prefijo.
  - `Shared/Materials/*.tres` son materiales externos enlazados por el nombre exacto del material dentro del GLB (`_subresources.materials` del `.glb.import`).
  - Las cabañas usan `gltf/embedded_image_handling=0`. `tree_1.glb.import` tiene `generate_lods=true` por defecto.
- Herramientas headless existentes: `Tools/Overworld/validate_map_001_3d.gd` y otros `validate_*.gd` (patrón `extends SceneTree`), `Tools/fill_tree_gap.gd` (edita regiones de Terrain3D y guarda con `ResourceSaver.save`), `Tools/inspect_terrain_instances.gd`.
- Shaders propios: `Shaders/water_pond.gdshader` (3D). El resto son shaders 2D de UI (`eye_shadows`, `menu_icon_silhouette`, `screen_glows`).

## 3. Reglas de trabajo (no negociables)

1. **Exportación desde Blender**: todo lo trabajado se exporta en **`.glb`** dentro de `exported/` (repo de Blender). **Antes de exportar algo, el usuario debe haberte dado el nombre del archivo y la autorización.** Los PNG/JSON de apoyo también se piden con nombre.
2. Los assets de las colecciones de Blender son gratuitos y el usuario tiene licencia de uso.
3. **El editor de Godot pisa el disco.** Mantiene escenas y regiones de Terrain3D en memoria y las sobrescribe al guardar o ejecutar. Antes de tocar un `.tscn` o un `.res` con el editor abierto, avisa al usuario de que cierre la pestaña **sin guardar** o use *Escena → Recargar escena guardada*, y hazlo antes de cualquier Ctrl+S o de ejecutar. (Ya costó dos incidentes: puertas y hierba.)
4. No borres archivos del usuario sin pedirlo. Los `.bak` y sobrantes de §10 los borra él.
5. Antes de sobrescribir un archivo: haz respaldo `.bak` si es una escena o región, y verifica releyendo (md5 o diff).
6. **Ningún shader se ha compilado fuera del editor.** Al escribir uno, compílalo con `godot --headless` (ver skill `godot-shaders`) y revisa que no haya `SHADER ERROR`.
7. Decisiones ya tomadas por el usuario, no las reabras:
   - El estanque se resuelve con la herramienta **Height de Terrain3D**; **no** crear una cuenca/estanque aparte.
   - El agua está en y local **−0.5**. No volver a proponer subirla.
   - La **hierba procedural en Godot fue descartada** el 2026-11-24 («No me gustó»). No retomar salvo que lo pida.

## 4. Estado del trabajo por área

### 4.1 Estanque de Hojaverde (`map_001_3d`) — hecho, agua por validar
- La meseta del mundo está a **y = 10** y el estanque es un hueco de 3 m (fondo a **y = 7**), hecho solo con alturas de Terrain3D (sin mallas ni huecos/`holes`).
- Datos: `Maps/map_001_3d_data/terrain3d-01_00.res` (región x=−1, z=0; tamaño 256, espaciado 1 m).
  - Boca: x −18…−8, z 3…13 (10×10 m). Fondo plano: x −17…−9, z 4…12 (8×8 m). Centro (−13, 8).
  - Valores exactos: meseta `10.000007629394531`, fondo `7.000007629394531`.
  - El fondo tiene textura Dirt Ground pintada (control map `0x08400000`, 81 vértices).
- **Límite geométrico explicado al usuario**: un heightmap no tiene paredes verticales (una pared ocupa ≥ 1 celda), así que con boca de 10 m el fondo plano es de 8 m. Con triangulación de diagonal uniforme, dos esquinas opuestas de la boca quedan achaflanadas (~1 m) si el agua está por debajo del borde. Los *holes* tampoco lo arreglan: Terrain3D solo quita los triángulos que tocan un vértice-hueco y sobrevive el de la meseta que no toca ninguno.
- **Agua**: nodo `LeaftownPond` (MeshInstance3D, PlaneMesh 10×10) en `World/Leaftown/Props/Leaftown`, posición local (−13, −0.5, 8) (`Props` está en y = 10, así que el agua está en y = 9.5 del mundo). Material: `Resources/Materials/3D/Shared/Materials/water_pond.tres`, que contiene **solo la referencia al shader**.
- **Shader** `Shaders/water_pond.gdshader` (v4, propio): no usa texturas ni parámetros externos; todos los valores por defecto están dentro. Ver técnicas en §5.4.
  - `uniform int rows : hint_range(0, 8) = 0` controla las filas de espuma (0 = ninguna). Dinámica a propósito, para usar distintos valores en distintos sitios con agua; si hace falta un valor por nodo con el mismo material, convertirla en `instance uniform`.
  - Estado: **la v4 nunca se ha compilado en Godot**. Falta que el usuario valide cómo se ve y que compila.
- El `water_shader.gdshader` del usuario (copia del CC0 «Simple Water with Mesh form» de DASTER) quedó sin tocar y sin uso.
- Pendiente: decidir si el jugador puede entrar al agua (las paredes de ~71° probablemente lo impiden) y si se añade rampa.

### 4.2 Textura FoliageGrass en Terrain3D — hecho
- Ranura nueva «Foliage Grass» (id 2, `uv_scale = 0.25`) en `Maps/map_001_3d.tscn`.
- Archivos en `Resources/Materials/3D/Textures/`: `FoliageGrass_albedo_height.png`, `FoliageGrass_normal_roughness.png` y `flat_normal_256.png` (las ranuras 0 y 1 ahora usan ese normal plano de 256 px; el antiguo `flat_normal.png` era de 16×16 y rompía el array). Todo a 256×256, BPTC, con `.import` propios.
- Procedimiento completo y script de empaquetado en §5.2.

### 4.3 Texturas exportadas desde Blender — hecho
- 195 PNG (~520 MB, 52 materiales de `Material-LIB.blend`) en `exported/New Textures` del repo de Blender, con nombre `<Material>_<Mapa>.png` (`BaseColor`, `Metallic`, `Roughness`, `Normal`, `Alpha`). Son los PNG originales empaquetados en el `.blend`, sin recomprimir. `Dots Stroke` no tiene texturas.

### 4.4 Menú del overworld con hora y fecha del juego — implementado, **sin probar en Godot**
- El panel superior izquierdo del menú (Enter o F) muestra la hora del juego `HH:MM:SS` y debajo el día y mes en español, sin año.
- `Scripts/ui_root.gd` (`OverworldUIRoot`): `time_of_day_path` opcional (vacío = busca un `TimeOfDay` de Sky3D bajo el padre); `_refresh_menu_clock()` lee `current_time`, `day`, `month`, suma 1 ms para evitar errores de redondeo y llama a `Menu.set_game_clock(...)`; sin `TimeOfDay` usa el reloj del sistema con `push_warning`.
- `Scripts/menu.gd` (`OverworldMenu`): `set_game_clock(hour, minute, second, day, month)` y `MONTH_NAMES`.
- `Scenes/GUI/menu.tscn`: `TimePanel` 340×84, `TimeValue` (fuente 32) y `DateValue` (fuente 24).
- En Leaftown el `TimeOfDay` tiene `system_sync = true` (hora del PC).
- Observación sin verificar: el UIRoot busca `get_player()` en la raíz del mapa y esta no lo publica, así que el menú no bloquea el movimiento de Cynthia.

### 4.5 Puertas de las cabañas — implementado (v2), **sin probar en Godot**
- Cada puerta es un `DoorEntrance` (`Scripts/Overworld/door_entrance.gd`, `Area3D`) con un hijo `Trigger` (caja 1×1.5×1 m) sobre la baldosa frente a la puerta. El Area3D no usa física; solo se lee la forma.
- Secuencia: Cynthia empuja hacia la puerta (+X) → el edificio bloquea y el jugador emite `step_blocked` → `DoorEntrance` comprueba dirección y que el centro del jugador esté en la caja → desactiva control, `Door_Open`, `walk_scripted()` hasta el centro de la hoja, oculta el sprite, `Door_Close`, `_finish_entry()`.
- `Scripts/Overworld/player_character_3d.gd`: señal `step_blocked`, `_scripted_motion`, `walk_scripted(destino, duración)` (tween sin física).
- Nodos en `Maps/map_001_3d.tscn`: `World/Leaftown/Doors/{DoorLucasDawnHouse, DoorBarryHouse, DoorHouse1, DoorHouse2}`. Centros de caja (x, z): (−1, 18), (14, −5), (−1, −5), (14, 18).
- Las colisiones de los edificios son `CollisionShape3D` de un único `StaticBody3D` (`World/Leaftown/Collisions/LeafTown`); no se tocaron.
- **Variante TEMPORAL a retirar**: `DoorEntrance._temporary_fade_and_quit()` (fundido + `get_tree().quit()`), usada mientras `interior_scene_id` esté vacío. Para sustituirla: registrar el mapa del interior en `SceneLoader` como `MAP`, asignar `interior_scene_id` e `interior_spawn` en cada puerta, y borrar la función y su llamada en `_finish_entry()`.
- Por verificar: que cada caja esté sobre el camino, que la caminata deje a Cynthia en el centro de la puerta y que exista `walk_up` en `cynthia_grown_frames.tres`. Falta la secuencia de **salida** del interior.

### 4.6 Camino de tierra (DirtRoad) — hecho, **por validar**
- 156 decales planos del usuario (bajo `World/Leaftown/Roads/Leaftown`) → **un solo `Decal` `DirtRoad`** con borde oscuro horneado en la textura (un `Decal` no admite shaders).
- Textura nueva `Resources/Materials/3D/Textures/dirt_road_leaftown.png` (1391×1766, ≈56 px/m). Nodo: centro (6.4898257, 0, 7.9204874), size (24.845583, 1, 31.53736), `cull_mask = 524288` (capa 20), `normal_fade = 0.5`, distance fade 80/20.
- No se tocó `dirt_road.png` (el usuario lo necesita para futuros caminos) ni los nodos ocultos `DirtRoad2/3/4`.
- Respaldo de la escena: `Maps/map_001_3d.tscn.before_dirtroad_leaftown.bak`.
- Por validar: orientación (se asumió u = +X, v = +Z del decal sin rotación), aspecto del borde y nitidez (56 px/m).
- Técnica y script en §5.3.

### 4.7 Hierba procedural y tulipanes — Blender hecho, Godot **descartado**
- Blender: `hierba_mechon.glb`, `tulipan.glb`, `hierba_degradado.png`, `tulipan_paleta.png` y `hierba_plano_instancias.json` en `exported/` (repo de Blender). La escena de trabajo es `animegrass.blend` (originalmente en `C:\Users\Beltz\Downloads`).
- La integración en Godot (shader de viento, populador de instancias en Terrain3D) se hizo el 2026-11-24 y el usuario pidió **revertirla**. El `.tscn` ya está revertido; quedan archivos sobrantes (§10) y ≈57 instancias inofensivas del id 1 en las regiones de Terrain3D (se borran con clic central sobre su tile en el dock).
- Otros `.glb` en `exported/` que no son de esta tarea: `breakable_rock`, `cabin_1..8`, `mailbox`, `molino`, `prof_rowan_lab`, `tall_grass`, `tree_1`. Problema conocido: la capa Snow de `tree_1.glb` se ve negra en Godot.

## 5. Técnicas usadas (receta de cada una)

### 5.1 Leer y parchear una región de Terrain3D desde fuera de Godot
- El archivo `terrain3d-*.res` es un contenedor **RSCC**: cabecera de 16 bytes (magic, modo = 2 zstd, tamaño de bloque = 4096, tamaño total sin comprimir), tabla de tamaños de bloque (uint32 por bloque), bloques zstd y pie `RSCC`.
- **Alturas**: 65 536 floats (256×256) desde el byte **680** de los datos descomprimidos. Celda (px, pz) en `680 + 4*(pz*256 + px)`, con `px = x − 256*rx`.
- **Control map**: 65 536 uint32 desde el byte **262978** (el marcador 262144 está en 262974). Bits: base `<<27`, overlay `<<22`, blend `<<14`, ángulo UV `<<10`, escala UV `<<7`, hueco `<<2`, navegación `<<1`, autoshader `<<0`. Valores vistos: `0x00000001` (autoshader), `0x08400000` (Dirt Ground pintado).
- Node 22+ trae `zlib.zstdDecompressSync/zstdCompressSync`. Recomprime solo los bloques afectados, guarda un `.bak`, escribe con guarda de mtime y verifica releyendo.
- Regla de oro: tras parchear, el usuario debe recargar la escena antes de cualquier Ctrl+S.

### 5.2 Material de Blender → textura de Terrain3D
1. **Exportar** los PNG originales del `.blend` (script en Blender con el MCP): para cada nodo de imagen, seguir sus enlaces hasta el Principled BSDF (pasando por `NORMAL_MAP` y nodos intermedios) y guardar `image.packed_file.data` tal cual; verificar la firma PNG. Una imagen que alimenta varias entradas se guarda una sola vez como `_BaseColor`. El normal de la librería es **OpenGL (+Y)**, que es lo que espera Terrain3D.
2. **Copiar** BaseColor, Normal y Roughness a `Resources/Materials/3D/Textures/`.
3. **Mirar qué usa el terreno**: todos los albedo del array deben tener el mismo tamaño y formato, y todos los normal también. Aquí: 256×256, `compress/mode=2`, `compress/high_quality=true` (BPTC).
4. **Empaquetar** (Python con numpy y Pillow):
   - `<prefijo>_albedo_height.png`: RGB = albedo, **A = altura** (no es transparencia).
   - `<prefijo>_normal_roughness.png`: RGB = normal OpenGL, **A = roughness**.
   - Reducir al tamaño del terreno por **promedio de bloques** (2048 → 256 = bloques 8×8; exacto y respeta el tileo). Albedo promediado en luz lineal; normal promediado y renormalizado.
   - La librería no trae mapa de altura: se **reconstruye desde el normal** (Frankot-Chellappa por FFT, periódico) y se normaliza con percentiles 1–99 al rango 0.15–1.0, para que el alfa nunca sea 0 (de ahí venía el albedo «transparente»).
   - También se genera `flat_normal_<tamaño>.png` (127, 127, 255, 255).
5. **`.import`** junto a cada PNG, sin `uid` ni `path` (Godot los completa): `importer="texture"`, `compress/mode=2`, `compress/high_quality=true`, `compress/normal_map=2` (**Disabled**, también para el normal empaquetado), `mipmaps/generate=true`, `process/fix_alpha_border=false`.
6. **Ranura en Terrain3D**: en el editor (nodo `Terrain` → Textures → Add New) o editando `Maps/map_001_3d.tscn`: `ext_resource` nuevos más un `Terrain3DTextureAsset` (`name`, `id`, `albedo_texture`, `normal_texture`, `uv_scale`).
7. **Verificar**: los `.import` reescritos con `uid`/`path.bptc`, y los `.bptc.ctex` en `.godot/imported/` (un 256×256 BPTC con mipmaps pesa 87 460 bytes).
- Errores que ya ocurrieron: albedo 2048 en DXT5 frente a ranuras 256 BPTC; alfa en 0 sin mapa de altura; normal plano de 16×16 junto a uno de 256; importar el normal con «Normal Map = Enable».
- Para subir la resolución hay que subir **todas** las texturas del terreno al mismo tamaño y reimportarlas igual.
- El script completo (`pack_terrain3d.py <origen> <salida> <tamaño> <prefijo>`) está en el doc del Project `claude/terrain3d_foliagegrass.md`; si hace falta, pídele al usuario que lo copie al repo.

### 5.3 Combinar decales en uno con borde oscuro horneado
- Un `Decal` no admite shaders propios (solo albedo/normal/ORM/emisión y modulate), así que el efecto va en la textura.
- Mapeo asumido de Godot para un decal sin rotación: **u = +X, v = +Z**, textura estirada al tamaño del nodo.
- Algoritmo (Python con numpy, scipy, opencv, Pillow; entrada: JSON con `origin` y `size` por decal, **en orden de nodos**):
  1. Componer con mezcla alfa «over» en premultiplicado, usando `cv2.warpAffine` por decal a ≈56 px/m.
  2. Rellenar huecos **interiores** de la silueta con un cierre morfológico (radio 0.35 m); una zona añadida se rellena si toca poco el exterior «grueso» (disco de 0.6 m) respecto a su largo (ratio ≤ 0.40). Los entrantes del borde exterior se conservan. El color del relleno copia tierra vecina desplazada.
  3. Borde oscuro: distancia al exterior dentro de la máscara, degradado de 0.30 m con ancho irregular por ruido, tinte multiplicativo ≈ (0.66, 0.56, 0.48), fuerza 0.85.
  4. Rellenar el color bajo la transparencia con el píxel opaco más cercano (evita halos por mipmaps).
- El script (`bake_leaftown.py`) está en los docs del Project `claude/dirt_road_leaftown_bake.md` y `claude/dirt_road_bake.md`.

### 5.4 Shader de agua (`water_pond.gdshader`)
- **Ruido simplex 2D** (Ashima Arts / Ian McEwan, MIT) dentro del propio shader: el ruido de valor dejaba una rejilla cuadrada y líneas planas. La línea `x12.xy -= i1;` se escribió como `x12 = vec4(x12.xy - i1, x12.zw);` por precaución con el swizzle.
- Arrugas: 3 octavas (`ripple_cell` 0.25 m y mitad y cuarto, `ripple_height` 0.009, `ripple_speed`); las octavas más finas que un píxel se apagan con `fwidth` para que no centelleen. La normal sale por diferencias finitas (e = 0.02) y va a `NORMAL_MAP`.
- Filas de espuma: bucle con `MAX_ROWS = 8` y `break` según `rows`. Cada fila avanza hacia la orilla con su velocidad y fase, se deforma con su propio ruido (`row_wobble`, `row_drift`), deja estela (`row_trail`), se rompe en burbujas (`lace_cell`, `lace_cut`, `lace_fill`), y pasa de redondeada al centro a cuadrada cerca de la orilla (`row_round`, distancia al rectángulo redondeado).
- Franja de espuma de orilla siempre activa (`shore_width`, `shore_pulse`). Color turquesa → azul profundo (`shallow_color`, `deep_color`, `depth_falloff`). `plane_size` = lado del PlaneMesh (10).
- Es **lit** (reacciona a Sky3D) con `base_glow` y `foam_glow`; reflejo moderado (`gloss_roughness` 0.30, `gloss_specular` 0.35). `cull_disabled`.
- **Lección**: Godot reescribió `water_pond.tres` y descartó parámetros y `NoiseTexture2D` al cambiar el shader con el editor abierto. El juego lee el disco; el editor, la memoria. Por eso los valores por defecto viven en el shader y el `.tres` solo referencia el shader.
- Los valores se calibraron con una simulación aproximada en CPU (sin luz): son punto de partida.

### 5.5 Edición de escenas y recursos desde fuera del editor
- Los `.tscn` son texto: se editan con cambios mínimos (bloques de nodo y `ext_resource`), con respaldo y comprobación de que solo cambió lo esperado.
- El `.tres`/`.import` mínimo (sin `uid`) es válido: Godot lo completa al enfocar el editor.
- Escribe con guarda de mtime y vuelve a leer el archivo para comprobarlo.

### 5.6 Terrain3D 1.1.0 — datos útiles
- `Terrain3DMeshAsset`: `scene_file`, `material_override` (**uno solo**), `lod0_range…lod9_range` (0 = sin culling), `last_lod`, `last_shadow_lod`, `fade_margin`, `cast_shadows`, `height_offset`, `density`. Se usa la primera malla y se ignoran las transformaciones del nodo. LODs de artista: nodos hermanos con sufijo `LOD0`, `LOD1`… y `generate_lods=false` en el import.
- Instancias en celdas de **32×32 m**, sin colisión ni culling individual. API: `Terrain3DInstancer.add_transforms(mesh_id, transforms, colors, update)`, `clear_by_mesh/location/region`, `update_mmis()`. Datos: `region.instances[mesh_id][Vector2i celda]`.
- El color de instancia del MultiMesh se multiplica por el `COLOR` del vértice.
- Viento/interacción no vienen incluidos: van en un `ShaderMaterial` como `material_override`.
- Viento 2D existente (UI, no 3D): `Scripts/Overworld/overworld_wind_effect.gd` y `Scripts/wind_particles.gd` (`wind_direction = Vector2(1.0, −0.055)`, ráfaga `0.91 + sin(t*0.34)*0.07 + sin(t*0.13 + 1.7)*0.035`). Sky3D tiene `wind_direction = 2.356` rad (135°).
- Cámara del mapa: `CameraRig/Camera3D` fov 42°, pitch 45°, a (−12, 12, 0) del jugador, far 256. Jugador `CynthiaPlayer3D` en (−1.965, 0, 14.485).

### 5.7 Trampas de Blender ya resueltas
- Instancias por partículas: escala = `particle_size × hair_length × (1 − random)`, con `hair_length = normal_factor*4` (fijar `normal_factor` DESPUÉS de `hair_length`).
- El eje X de la partícula es «arriba»: para mallas Z-up hace falta un proxy rotado Y+90° y `use_rotation_instance=True`.
- Las fuentes de instancias deben tener `hide_viewport=False` (ocultar con `hide_set(True)`) y `hide_render=True`.
- Blender 5.2: poner `image_settings.media_type='IMAGE'` antes de `file_format='PNG'`. Las imágenes generadas en memoria salían negras al empaquetar: guardar PNG temporal, recargar y entonces `pack()`.
- `child_nbr` no existe (usar `child_percent` / `rendered_child_count`). `get_screenshot_of_area_as_image` requiere `area_ui_type="VIEW_3D"`.
- glTF: `export_vertex_color='ACTIVE'` exporta `COLOR_0`; doble cara = `use_backface_culling=False`; Z-up → Y-up (Godot x, z, −y).

## 6. Plugin de Blender (MCP): instalación y uso

**Qué es.** Un add-on dentro de Blender que abre un servidor local (por defecto `localhost:9876`) y un servidor MCP que lo conecta con Claude. Permite inspeccionar la escena, ejecutar Python en Blender, tomar capturas y renderizar. En esta máquina está instalado como conector **«Blender»** de Claude Desktop (estado: activo). Por los nombres de las herramientas parece el **add-on oficial de Blender Lab** (requiere Blender 5.1 o superior; aquí es 5.2.2). Esa identificación es una deducción, no está verificada.

**Herramientas disponibles** (en Claude Desktop con prefijo `mcp__remote-devices__Blender__`; en Claude Code aparecerán como `mcp__blender__<herramienta>`):
- Escena y objetos: `get_objects_summary`, `get_object_detail_summary`.
- Archivo `.blend`: `get_blendfile_summary_datablocks`, `…_missing_files`, `…_of_linked_libraries`, `…_path_info`, `…_usage_guess` (y variantes `_for_cli`).
- Código: `execute_blender_code` (y `_for_cli`).
- Documentación: `get_python_api_docs`, `search_api_docs`, `search_manual_docs`.
- Capturas y vistas: `get_screenshot_of_area_as_image`, `get_screenshot_of_window_as_image`, `get_screenshot_of_window_as_json`, `render_viewport_to_path`, `render_thumbnail_to_path`.
- Navegación: `jump_to_tab_by_name`, `jump_to_tab_by_space_type`, `jump_to_view3d_object_by_name`, `jump_to_view3d_object_data_by_name`.

**Instalación en Claude Desktop** (según un artículo que probó el add-on oficial v1.0.0 en Desktop y en Code):
1. Settings → Connectors → buscar «blender» → instalar el conector.
2. En Blender 5.1 o superior: arrastrar a la ventana de Blender los enlaces de instalación de la página del servidor Blender Lab MCP. El primero añade el repositorio; el segundo instala el add-on.
3. Edit → Preferences → Add-ons → **MCP**: Host `localhost`, Port `9876`, Auto Start activado. Debe decir «Server is running».
4. Probar pidiendo `get_objects_summary`.

**Instalación en Claude Code.**
- `claude mcp add-from-claude-desktop` **no** lista los conectores instalados como extensión, porque solo lee `claude_desktop_config.json`. Hay que registrar el ejecutable que Claude Desktop extrajo.
- En macOS el artículo lo encontró en `…/Claude/Claude Extensions/ant.dir.gh.blender.blender-mcp/.venv/bin/blender-mcp`. **En Windows no está verificado**: la carpeta probable es `%APPDATA%\Claude\Claude Extensions\ant.dir.gh.blender.blender-mcp\` con el ejecutable bajo `.venv\Scripts\`. Para localizarlo:
  `Get-ChildItem "$env:APPDATA\Claude\Claude Extensions" -Recurse -Filter "blender-mcp*" | Select FullName`
- Registrar (usa `--scope user` para que la ruta absoluta no quede en el repo; el artículo usó `--scope project`, que escribe `.mcp.json`):
  `claude mcp add --scope user blender -- "<ruta al ejecutable blender-mcp>"`
- **Reiniciar la sesión de Claude Code**, comprobar con `claude mcp list` (o `/mcp`) que `blender` aparece conectado y probar `get_objects_summary`.
- Alternativa comunitaria (otro servidor y otro add-on, con herramientas distintas; no mezclar con el oficial): `claude mcp add blender uvx blender-mcp` (proyecto `ahujasid/blender-mcp`; requiere `uv`).

**Precauciones.**
- Blender debe estar abierto con el add-on activo; si no, las llamadas fallan.
- El código que genera el modelo se ejecuta en Blender **sin protecciones reales**. Trabaja sobre copias del `.blend` y guarda antes de scripts destructivos.
- No está documentado si dos clientes (Desktop y Code) pueden conectarse a la vez al mismo Blender. Usa uno por vez.

**Cómo se usa en este proyecto.**
- Flujo típico: `get_objects_summary` → inspeccionar con `get_object_detail_summary` → `execute_blender_code` para cambios → `get_screenshot_of_area_as_image` (con `area_ui_type="VIEW_3D"`) para comprobar.
- Aislar modelos dentro de las colecciones de Blender ya creadas y exportarlos a `.glb` en `exported/`, **solo con nombre y autorización previos** (regla §3.1).
- Las trampas de §5.7 aplican a cualquier script.

## 7. Skills de gamedev (carpeta `.agents`)

- En `C:\Users\Beltz\.agents\skills` hay **37 skills** en formato Agent Skills (`SKILL.md` con `name` y `description`): 36 de `gamedev-skills/awesome-gamedev-agent-skills` (16 de Godot, 15 de disciplinas, 4 de flujos de trabajo, 1 de géneros) y `find-skills` de `vercel-labs/skills`. Las instaló el CLI `npx skills` para otros agentes (Cursor, Codex, Gemini CLI, etc.), **no para Claude Code**.
- **Claude Code no lee `.agents/skills`.** Lee `~/.claude/skills/`, `.claude/skills/` del proyecto y plugins. Para activarlas:
  - `npx skills add gamedev-skills/awesome-gamedev-agent-skills -a claude-code -g` (el CLI requiere Node.js 22.20 o superior; `--list` muestra qué instalaría), **o**
  - plugin: `/plugin marketplace add gamedev-skills/awesome-gamedev-agent-skills` y luego `/plugin install godot@awesome-gamedev-agent-skills`, **o**
  - copiar a mano las carpetas de `.agents\skills` a `~/.claude/skills/`.
- En Claude Desktop no se cargan solas: se suben como ZIP en Customize → Skills, con descripción de máx. 200 caracteres y solo 6 campos de frontmatter; las que revisé tienen 300–400 caracteres.
- Más útiles aquí (apuntan a Godot 4.7): `godot-shaders` (incluye compilación headless), `godot-3d-essentials`, `godot-nodes-scenes` (revisa rutas `res://` y uids rotos con `scripts/check_godot_project.py`), `godot-resources`, `godot-gdscript-headless-testing`, `shader-programming`, `level-design`, `camera-systems`, `create-game-assets`, `game-docs`.

## 8. Plugin Godot AI (opcional)

- `addons/godot_ai` (v4.3.1, MIT) conecta clientes MCP, incluido Claude Code, con el editor de Godot en vivo: inspeccionar escenas, crear nodos, cambiar propiedades, ejecutar pruebas y buscar archivos.
- Está en el repo pero **no habilitado** en `project.godot`. Para usarlo: Project → Project Settings → Plugins → activar «Godot AI»; elegir el cliente (Claude Code) en el dock **Godot AI** y pulsar **Configure**. Arranca el servidor MCP solo y conecta por WebSocket. Requiere Godot 4.7+ y [uv](https://docs.astral.sh/uv/).
- No se ha probado en este proyecto. Es un addon de terceros que modifica el editor abierto: revisa qué permisos pide antes de habilitarlo. La regla de §3.3 sigue vigente para cualquier cambio que se escriba directamente en el `.tscn` o el `.res`.

## 9. Pendientes

**Por validar con el usuario:**
- Shader de agua v4 (compila y se ve bien) y el uniform `rows`.
- Menú con hora y fecha.
- Secuencia de puertas en las otras tres casas (`DoorBarryHouse`, `DoorHouse1`, `DoorHouse2`).
- Camino `DirtRoad` combinado.
- Elección de la corrección del parpadeo del suelo (*floor-flicker*): el detalle no está en este archivo; pregúntale.

**Sin empezar (necesitan su visto bueno):**
- Sustituir `_temporary_fade_and_quit()` por el interior real, y la secuencia de salida.
- Hierba alta (`tall_grass.glb`, `Docs/tall_grass.md`): shader opcional, autoload y `Shared/Materials/tall_grass.tres`.
- Física/colisión del agua y rampa del estanque.

## 10. Archivos sobrantes (los borra el usuario a mano)

- Estanque: `Scenes/World/pond_basin.tscn`, `Maps/map_001_3d_data/terrain3d-01_00.res.before_pond_hole.bak`, `Maps/map_001_3d_data/terrain3d-01_00.res.before_pond_square.bak`, `Maps/map_001_3d.tscn.before_pond_hole.bak`, `Maps/map_001_3d.tscn.before_pond_brim.bak`.
- Camino: `Maps/map_001_3d.tscn.before_dirtroad.bak` y `…before_dirtroad_leaftown.bak` (cuando valide).
- Hierba descartada: `Scripts/Overworld/grass_field_populator.gd`, `Shaders/vegetation_wind.gdshader`, `Resources/Materials/3D/Shared/Materials/hierba.tres` y `tulipan.tres`, `Resources/Materials/3D/Models/hierba_mechon.glb` y `tulipan.glb` (con sus PNG duplicados `hierba_mechon_hierba_degradado.png` y `tulipan_tulipan_paleta.png`), `Resources/Materials/3D/Textures/hierba_degradado.png` y `tulipan_paleta.png`, `Resources/Vegetation/hierba_plano_instancias.json`.
- Antes de borrar nada, confirma con `git status` y con el usuario que no los usa.

## 11. Dónde está el detalle largo

Los docs del Project de claude.ai «Modelado 3D» (`claude/*.md`) guardan los scripts completos y el historial: `estanque_hojaverde`, `terrain3d_foliagegrass`, `menu_reloj_juego`, `puertas_cabanas`, `dirt_road_bake`, `dirt_road_leaftown_bake`, `hierba_procedural_contexto`. Claude Code no los ve salvo que se copien al repo (por ejemplo a `Docs/claude/`).
