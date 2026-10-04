# Sistema de guardado

Los datos persistentes se escriben en `user://Saved`, nunca dentro de `res://`.
En Windows, la ruta se resuelve normalmente dentro de
`%APPDATA%/Godot/app_userdata/belium/Saved`.

- `player_identity.json`: UUID v4, secreto aleatorio local y una firma de
  asociación con el dispositivo. El identificador bruto del dispositivo no se
  almacena.
- `save_slot_1.json`: progreso de la partida y referencia al UUID del jugador.
- `*.backup`: copia anterior conservada al reemplazar un archivo.

`SaveManager.has_save()` sólo devuelve `true` cuando identidad y guardado son
JSON válidos y ambos contienen el mismo `player_id`.

La identidad local evita colisiones accidentales, pero no debe usarse como
credencial de seguridad para un servicio online: cualquier secreto almacenado
en el equipo puede ser extraído por su propietario o por malware.
