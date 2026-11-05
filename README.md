# COMAPA Sur: Consulta de documentos por gerencia

Proyecto universitario (prácticas). Sitio local para consultar
documentos por gerencia, con inicio de sesión por área.
Los documentos son simulados.

## Requisitos
- Windows con PowerShell
- Navegador (Brave, Chrome, etc.)

## Cómo iniciar
1. Doble clic en `iniciar.bat`
2. Abrir http://localhost:5500

## Gerencias
General, Administrativa, Técnica, Comercial y Proyectos Estratégicos.
Cada usuario pertenece a una sola gerencia.

## Administración de usuarios
Solo el administrador crea y elimina cuentas, con `usuarios.bat`
(ver, agregar, eliminar, cambiar contraseña, cifrar existentes).
Las contraseñas se guardan cifradas (PBKDF2 con sal por usuario).
`usuarios.json` no se incluye en el repositorio (tampoco `bitacora.log` ni `cache_vistas/`).

## Agregar documentos
Copiar el archivo a `documentos/<gerencia>/` (o a una subcarpeta).
No hace falta modificar código.

## Vista previa de archivos
- PDF: se muestra directo en el navegador.
- Word, Excel y PowerPoint (.doc, .docx, .xls, .xlsx, .ppt, .pptx, .rtf, .odt, .ods, .odp):
  el servidor los convierte a PDF con Microsoft Office y muestra ese PDF.
  Requiere Office instalado en la computadora donde corre `servidor.ps1`.
  La primera vez tarda unos segundos; el PDF se guarda en `cache_vistas/`
  y se reutiliza mientras el archivo original no cambie.
- Imágenes (.jpg, .png, .gif, .webp) y texto (.txt, .csv): se muestran directo.
- Si no se puede generar la vista previa, se ofrece el botón de descarga.

## Seguridad
- Sesión con cookie HttpOnly de 8 horas
- El servidor valida la sesión y el área en cada archivo (401/403)
- `usuarios.json` no es descargable
- `cache_vistas/` tampoco se puede abrir desde el navegador; los PDF de vista previa
  solo se entregan por `/api/vista`, que valida la sesión y el área
- Solo funciona en local, sin internet público

## Estructura
- `index.html`: página de inicio y menú de gerencias
- `login.html`: inicio de sesión (compartido, `?area=`)
- `archivos.html`: lista, búsqueda y vista previa de archivos
- `servidor.ps1`: servidor local
- `usuarios.ps1` / `usuarios.bat`: administración de cuentas
- `funciones.js`, `styles.css`

## Nota
Los textos de "Significado" y "Objetivo" son de redacción propia,
no oficiales.