# MacFileExplorer Workspace Rules

## Release Notes ("Acerca de MacFileExplorer")

- Cada vez que se agregue o modifique una funcionalidad orientada al usuario en `MacFileExplorer`, **actualizar obligatoriamente** el catálogo de novedades en `Sources/MacFileExplorer/Models/ReleaseNotes.swift` (`ReleaseNotesCatalog.sections`) dentro del mismo cambio antes de compilar y entregar la respuesta.
- Las entradas nuevas deben agregarse en la sección más reciente (arriba de todo, en orden cronológico inverso), con fecha actualizada (`dateLabelES` / `dateLabelEN`), un ícono SF Symbol representativo, y textos en **español (`titleES` / `summaryES`) e inglés (`titleEN` / `summaryEN`)**.
- Redactar siempre en **lenguaje natural y simple que entienda cualquier persona** (evitar jerga técnica de implementación como nombres de clases, vistas, APIs o detalles internos de código; explicar claramente qué hace la novedad y cómo la usa el usuario).

## Política de Git Push

- **NO hacer `git push` en cada cambio.**
- Solo realizar `git push` cuando el usuario lo indique explícitamente (ej. "hacé push", "subí los cambios") o cuando solicite generar una versión (ej. "generá una versión x", release/corte de versión).
- En el flujo de trabajo habitual se compila, prueba y verifica localmente sin empujar al repositorio remoto hasta recibir la instrucción directa.

## Actualización de Ayuda (Help), README y Web (GitHub Pages + GIFs) en Releases o Push

- Cada vez que se cree un release o el usuario indique generar una versión / pushear cambios al repositorio, **actualizar obligatoriamente**:
  1. **Pantalla de Ayuda (`Sources/MacFileExplorer/Views/Toolbar/HelpGuideView.swift`):** incorporar todas las funcionalidades, configuraciones y atajos nuevos en las secciones correspondientes (`Destacadas`, `Todas las funciones`, `Atajos de teclado` y `Configuraciones`), en español e inglés, con lenguaje claro y práctico para el usuario final.
  2. [`README.md`](./README.md) y [`releases/README.md`](./releases/README.md) con el número de versión actual, el enlace de descarga al nuevo `.dmg` y el detalle claro de las novedades.
  3. [`GithubPages/index.html`](./GithubPages/index.html) y **GIFs animados (`GithubPages/assets/*.gif`)**:
     - Actualizar el número de versión (`nav-version-pill`, `hero-release-badge`, etiquetas de descarga), los enlaces directos al nuevo `.dmg` (`nav-download-cta`, `hero-download-cta`, `install-download-cta`) y la lista de novedades (`STATIC_RELEASES`).
     - Generar/incluir **GIFs animados** en `GithubPages/assets/` para todas las funcionalidades nuevas relevantes (y sumarlos a `DEMO_ITEMS` actualizando los contadores de filtros y descripciones EN/ES), manteniendo siempre un **lenguaje sencillo orientado al usuario final no técnico**.
