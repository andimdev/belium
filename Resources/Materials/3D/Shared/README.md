# Materiales 3D compartidos

Esta carpeta contiene los materiales externos reutilizados por las cabañas.
Las texturas canónicas viven en `res://Resources/Materials/3D/Textures`.

## Flujo de importación

- Los GLB de `Models/cabin_1.glb` a `Models/cabin_8.glb` conservan únicamente
  la geometría y los materiales que no usan texturas compartidas.
- Sus archivos `.glb.import` usan `gltf/embedded_image_handling=0` para que
  Godot no vuelva a extraer las imágenes incrustadas.
- Cada material texturizado se enlaza a uno de los `.tres` de esta carpeta por
  el nombre exacto que tiene el material dentro del GLB.
- Si un modelo se vuelve a exportar desde Blender, hay que conservar los
  nombres de sus materiales. Si se renombran, también debe actualizarse su
  entrada en `_subresources.materials` dentro del archivo `.glb.import`.

No se deben volver a copiar texturas con prefijos como `cabin_1_` o
`cabin_2_`. Cuando varias construcciones compartan una imagen, se agrega una
sola copia a `Textures` y se crea o reutiliza aquí su material externo.
