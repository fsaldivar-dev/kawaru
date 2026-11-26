# Kawaru

Efectos y rótulos para tus videollamadas, con un gesto de la mano. Kawaru es una cámara virtual para
macOS: lee tus manos con la cámara y pone sobre tu imagen lo que le pidas, en Meet, Zoom, Teams o
cualquier app de video. Todo se procesa en tu Mac.

Creado por Francisco Javier Saldivar Rubio ·
[LinkedIn](https://www.linkedin.com/in/fsaldivar-dev/) · [GitHub](https://github.com/fsaldivar-dev)

## Qué hace

- **Efectos** que se activan con un gesto, un atajo o desde la barra de menús: sustitución, clones,
  cartel de ausencia, globo de pregunta, confeti, descanso con cuenta atrás y foco.
- **Rótulos** sobre el video: tercio inferior, banner, insignia, tarjeta completa y redes sociales, en
  cinco temas (uno de ellos con tus propios colores, letra y forma). Varios a la vez, sin encimarse.
- **Tus propios gestos**: graba la posición de manos que quieras para cada efecto o rótulo.
- **En segundo plano**: vive en la barra de menús y solo enciende tu cámara cuando una llamada la usa.

## Requisitos

- macOS 14 o posterior.
- Para compilar: Xcode con tu cuenta de desarrollador, y `xcodegen` (`brew install xcodegen`).

## Usarla

1. Abre el `.dmg` y arrastra Kawaru a Aplicaciones (la cámara virtual solo se instala desde ahí).
2. Ábrela y sigue el tutorial: permiso de cámara, instalar la cámara virtual y tu primer gesto.
3. En tu app de videollamadas, elige la cámara «Kawaru».

## Compilar

```bash
scripts/provision.sh        # una vez: obtiene de Xcode el perfil para la cámara virtual
scripts/build.sh --install  # compila e instala en /Applications
```

`scripts/previews.sh` regenera las imágenes y videos de la galería pasando las fotos de `assets/modelo`
por el compositor real de la app.

## Publicar una versión

```bash
scripts/provision.sh --release                    # una vez: perfil Developer ID
xcrun notarytool store-credentials kawaru-notary  # una vez: tus credenciales de Apple, en el llavero
scripts/release.sh                                # deja build/release/Kawaru-<versión>.dmg
```

Sin las credenciales de notarización el `.dmg` sale firmado pero sin notarizar, y otras Mac se negarán
a abrirlo.

## Privacidad

La imagen de la cámara no sale de tu Mac. Lo único que se guarda, en
`~/Library/Application Support/Kawaru`, son las fotos que se toman al grabar una posición de manos y los
iconos que elijas para tus rótulos.

## Recursos de terceros

- Los logos de redes sociales vienen de [Simple Icons](https://simpleicons.org) (CC0). Siguen siendo
  marcas de sus dueños.
- Las ilustraciones, las placas de los rótulos y las fotos de los modelos de la galería se generaron
  con IA; las personas que aparecen no existen.
