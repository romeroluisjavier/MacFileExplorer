# MacFileExplorer Workspace Rules

## Release Notes ("Acerca de MacFileExplorer")

- Cada vez que se agregue o modifique una funcionalidad orientada al usuario en `MacFileExplorer`, **actualizar obligatoriamente** el catálogo de novedades en `Sources/MacFileExplorer/Models/ReleaseNotes.swift` (`ReleaseNotesCatalog.sections`) dentro del mismo cambio antes de compilar y entregar la respuesta.
- Las entradas nuevas deben agregarse en la sección más reciente (arriba de todo, en orden cronológico inverso), con fecha actualizada (`dateLabelES` / `dateLabelEN`), un ícono SF Symbol representativo, y textos en **español (`titleES` / `summaryES`) e inglés (`titleEN` / `summaryEN`)**.
- Redactar siempre en **lenguaje natural y simple que entienda cualquier persona** (evitar jerga técnica de implementación como nombres de clases, vistas, APIs o detalles internos de código; explicar claramente qué hace la novedad y cómo la usa el usuario).
