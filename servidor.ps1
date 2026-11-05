# servidor.ps1
# Servidor local para COMAPA Sur, con sesiones del lado del servidor.
#
# - El login se valida AQUI (usuarios.json nunca se envia al navegador).
# - Al iniciar sesion el servidor entrega una cookie con un identificador aleatorio.
# - Los archivos de documentos/<area>/ solo se entregan si la sesion pertenece a esa area.
# - La lista de archivos se genera en vivo escaneando documentos/<area>/.
# - Word, Excel y PowerPoint se convierten a PDF (con Microsoft Office) para la vista previa.

$puerto = 5500
$carpeta = $PSScriptRoot
$carpetaBase = $carpeta.TrimEnd('\') + '\'
$raizDocumentos = Join-Path $carpeta "documentos"
$raizDocsConSlash = $raizDocumentos.TrimEnd('\') + '\'
$duracionSesionHoras = 8

# Carpeta donde se guardan los PDF generados para la vista previa (se crea sola).
# No es publica: el servidor nunca entrega .pdf fuera de documentos/.
$carpetaVistas = Join-Path $carpeta "cache_vistas"
$segundosMaxConversion = 90

# Sesiones activas en memoria: token -> @{ area; expira }
$sesiones = @{}

$tiposContenido = @{
    ".html"  = "text/html; charset=utf-8"
    ".css"   = "text/css; charset=utf-8"
    ".js"    = "application/javascript; charset=utf-8"
    ".jpg"   = "image/jpeg"
    ".jpeg"  = "image/jpeg"
    ".png"   = "image/png"
    ".gif"   = "image/gif"
    ".webp"  = "image/webp"
    ".svg"   = "image/svg+xml"
    ".ico"   = "image/x-icon"
    ".pdf"   = "application/pdf"
    ".txt"   = "text/plain; charset=utf-8"
    ".csv"   = "text/plain; charset=utf-8"
    ".doc"   = "application/msword"
    ".docx"  = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    ".xls"   = "application/vnd.ms-excel"
    ".xlsx"  = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    ".ppt"   = "application/vnd.ms-powerpoint"
    ".pptx"  = "application/vnd.openxmlformats-officedocument.presentationml.presentation"
}

# Extensiones que se pueden convertir a PDF para la vista previa, y con que programa de Office
$convertiblesOffice = @{
    ".doc"  = "word";  ".docx" = "word";  ".rtf" = "word";  ".odt" = "word"
    ".xls"  = "excel"; ".xlsx" = "excel"; ".ods" = "excel"
    ".ppt"  = "powerpoint"; ".pptx" = "powerpoint"; ".odp" = "powerpoint"
}

# Fuera de documentos/ solo se sirven estos tipos (todo lo demas: .json, .ps1, .bat, etc. se bloquea)
$extensionesPublicas = @(".html", ".css", ".js", ".jpg", ".jpeg", ".png", ".gif", ".webp", ".svg", ".ico")

function Enviar-Texto($response, $codigo, $texto, $tipo) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($texto)
    $response.StatusCode = $codigo
    $response.ContentType = $tipo
    $response.ContentLength64 = $bytes.Length
    $response.OutputStream.Write($bytes, 0, $bytes.Length)
    $response.OutputStream.Close()
}

function Escapar-Json($texto) {
    return ($texto -replace '\\', '\\\\' -replace '"', '\"')
}

function Obtener-Sesion($request) {
    $cookie = $request.Cookies["sesion"]
    if ($cookie -eq $null) { return $null }

    $token = $cookie.Value
    if ($sesiones.ContainsKey($token)) {
        $sesion = $sesiones[$token]
        if ($sesion.expira -gt (Get-Date)) { return $sesion }
        $sesiones.Remove($token)
    }
    return $null
}

function Nuevo-Token {
    $bytes = New-Object byte[] 32
    $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    $rng.GetBytes($bytes)
    $rng.Dispose()
    return (($bytes | ForEach-Object { $_.ToString("x2") }) -join "")
}

# ---------- Contrasenas cifradas ----------
# Formato guardado en usuarios.json (campo "hash"):
#   pbkdf2$<iteraciones>$<sal en base64>$<hash en base64>
# Se generan con usuarios.ps1. Nunca se guarda la contrasena original.

function Calcular-Hash($password, [byte[]]$sal, $iteraciones) {
    $pbkdf2 = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($password, $sal, $iteraciones)
    $bytes = $pbkdf2.GetBytes(32)
    $pbkdf2.Dispose()
    return $bytes
}

# Compara dos arreglos de bytes sin detenerse en la primera diferencia
function Comparar-Bytes([byte[]]$a, [byte[]]$b) {
    if ($a.Length -ne $b.Length) { return $false }
    $dif = 0
    for ($i = 0; $i -lt $a.Length; $i++) {
        $dif = $dif -bor ($a[$i] -bxor $b[$i])
    }
    return ($dif -eq 0)
}

function Verificar-Password($password, $guardado) {
    if ($password -eq $null -or $guardado -eq $null) { return $false }

    $partes = ([string]$guardado).Split('$')
    if ($partes.Count -ne 4 -or $partes[0] -ne 'pbkdf2') { return $false }

    try {
        $iteraciones = [int]$partes[1]
        $sal = [Convert]::FromBase64String($partes[2])
        $esperado = [Convert]::FromBase64String($partes[3])
    } catch {
        return $false
    }

    $calculado = Calcular-Hash ([string]$password) $sal $iteraciones
    return (Comparar-Bytes $calculado $esperado)
}

function Listar-ArchivosArea($area) {
    $items = @()
    $carpetaArea = Join-Path $raizDocumentos $area

    if (Test-Path $carpetaArea -PathType Container) {
        $prefijo = (Get-Item $carpetaArea).FullName.TrimEnd('\') + '\'
        $archivos = Get-ChildItem -Path $carpetaArea -File -Recurse | Sort-Object FullName

        foreach ($archivo in $archivos) {
            $tipo = switch ($archivo.Extension.ToLower()) {
                ".pdf"  { "pdf" }
                { $_ -in ".xls", ".xlsx", ".ods" }  { "excel" }
                { $_ -in ".doc", ".docx", ".rtf", ".odt" } { "word" }
                { $_ -in ".ppt", ".pptx", ".odp" }  { "powerpoint" }
                { $_ -in ".jpg", ".jpeg", ".png", ".gif", ".webp" } { "imagen" }
                { $_ -in ".txt", ".csv" }           { "texto" }
                default { "archivo" }
            }

            # Ruta dentro del area, por ejemplo "Sindicato\Acta.pdf" o solo "Acta.pdf"
            $relativa = $archivo.FullName.Substring($prefijo.Length)

            # El "grupo" es la subcarpeta de primer nivel (vacio si el archivo esta suelto en el area)
            $grupo = ""
            if ($relativa.Contains('\')) { $grupo = $relativa.Split('\')[0] }

            $rutaWeb = "documentos/$area/" + ($relativa -replace '\\', '/')

            $nombre = Escapar-Json $archivo.Name
            $grupoJson = Escapar-Json $grupo
            $ruta = Escapar-Json $rutaWeb
            $items += "{ `"nombre`": `"$nombre`", `"tipo`": `"$tipo`", `"grupo`": `"$grupoJson`", `"ruta`": `"$ruta`" }"
        }
    }
    return "[" + ($items -join ",") + "]"
}

function Listar-Subcarpetas($area) {
    $items = @()
    $carpetaArea = Join-Path $raizDocumentos $area

    if (Test-Path $carpetaArea -PathType Container) {
        $carpetas = Get-ChildItem -Path $carpetaArea -Directory | Sort-Object Name
        foreach ($c in $carpetas) {
            $items += ('"' + (Escapar-Json $c.Name) + '"')
        }
    }
    return "[" + ($items -join ",") + "]"
}

function Procesar-Login($request, $response) {
    $json = "application/json; charset=utf-8"

    $lector = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
    $cuerpo = $lector.ReadToEnd()
    $lector.Close()

    try {
        $datos = $cuerpo | ConvertFrom-Json
    } catch {
        Enviar-Texto $response 400 '{"ok":false}' $json
        return
    }

    $minutos = Minutos-Bloqueo-Restantes $datos.usuario
    if ($minutos -gt 0) {
        Registrar-Evento "LOGIN_BLOQUEADO" $datos.usuario $datos.area "intento durante bloqueo"
        Enviar-Texto $response 429 ('{"ok":false,"bloqueado":true,"minutos":' + $minutos + '}') $json
        return
    }

    try {
        $rutaUsuarios = Join-Path $carpeta "usuarios.json"
        $usuarios = Get-Content -Path $rutaUsuarios -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Enviar-Texto $response 500 '{"ok":false}' $json
        return
    }

    $encontrado = $null
    foreach ($u in $usuarios) {
        if ($u.usuario -ceq $datos.usuario -and $u.area -ceq $datos.area) {
            if (Verificar-Password $datos.password $u.hash) { $encontrado = $u }
            break
        }
    }

    if ($encontrado -eq $null) {
        Registrar-Fallo $datos.usuario
        Registrar-Evento "LOGIN_FALLO" $datos.usuario $datos.area "usuario o contrasena incorrectos"
        if ((Minutos-Bloqueo-Restantes $datos.usuario) -gt 0) {
            Registrar-Evento "BLOQUEO" $datos.usuario $datos.area "cuenta bloqueada por intentos fallidos"
        }
        Start-Sleep -Milliseconds 500
        Enviar-Texto $response 401 '{"ok":false}' $json
        return
    }

    Limpiar-Fallos $datos.usuario
    Registrar-Evento "LOGIN_OK" $encontrado.usuario $encontrado.area ""

    $token = Nuevo-Token
    $sesiones[$token] = @{
        area   = $encontrado.area
        usuario = $encontrado.usuario
        expira = (Get-Date).AddHours($duracionSesionHoras)
    }

    $response.Headers.Add("Set-Cookie", "sesion=$token; Path=/; HttpOnly; SameSite=Strict")
    Enviar-Texto $response 200 '{"ok":true}' $json
}

function Procesar-Logout($request, $response) {
    $cookie = $request.Cookies["sesion"]
    if ($cookie -ne $null -and $sesiones.ContainsKey($cookie.Value)) {
        $sesiones.Remove($cookie.Value)
    }
    $response.Headers.Add("Set-Cookie", "sesion=; Path=/; HttpOnly; SameSite=Strict; Max-Age=0")
    Enviar-Texto $response 200 '{"ok":true}' "application/json; charset=utf-8"
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$puerto/")

try {
    $listener.Start()
} catch {
    Write-Host "No se pudo iniciar el servidor en el puerto $puerto."
    Write-Host "Puede que ya haya otro programa usando ese puerto (por ejemplo Live Server o una copia vieja de este servidor)."
    Write-Host "Cierra ese otro programa e intenta de nuevo, o cambia el numero de puerto en este script."
    pause
    exit
}

Write-Host "Servidor COMAPA Sur corriendo en http://localhost:$puerto/"
Write-Host "Las sesiones y los permisos por area se validan en este servidor."
Write-Host "Para detenerlo, cierra esta ventana o presiona Ctrl+C."
Write-Host ""

Start-Process "http://localhost:$puerto/index.html"

$json = "application/json; charset=utf-8"

# ---------- Bloqueo por intentos fallidos ----------
$maxIntentos = 5
$minutosBloqueo = 5
$intentosFallidos = @{}   # clave: usuario en minúsculas

# Devuelve 0 si puede intentar, o los minutos que le faltan si está bloqueado
function Minutos-Bloqueo-Restantes($usuario) {
    if ([string]::IsNullOrWhiteSpace($usuario)) { return 0 }
    $clave = $usuario.Trim().ToLower()
    if (-not $intentosFallidos.ContainsKey($clave)) { return 0 }

    $hasta = $intentosFallidos[$clave].bloqueadoHasta
    if ($hasta -eq $null) { return 0 }

    $restante = ($hasta - (Get-Date)).TotalMinutes
    if ($restante -le 0) {
        $intentosFallidos.Remove($clave)   # el bloqueo ya venció
        return 0
    }
    return [math]::Ceiling($restante)
}

# Suma un fallo; al llegar al máximo, activa el bloqueo
function Registrar-Fallo($usuario) {
    if ([string]::IsNullOrWhiteSpace($usuario)) { return }
    $clave = $usuario.Trim().ToLower()
    if (-not $intentosFallidos.ContainsKey($clave)) {
        $intentosFallidos[$clave] = @{ cuenta = 0; bloqueadoHasta = $null }
    }
    $intentosFallidos[$clave].cuenta++
    if ($intentosFallidos[$clave].cuenta -ge $maxIntentos) {
        $intentosFallidos[$clave].bloqueadoHasta = (Get-Date).AddMinutes($minutosBloqueo)
    }
}

# Login correcto: se borra el historial de fallos de ese usuario
function Limpiar-Fallos($usuario) {
    if ([string]::IsNullOrWhiteSpace($usuario)) { return }
    $intentosFallidos.Remove($usuario.Trim().ToLower())
}

# ---------- Bitácora de accesos ----------
$archivoBitacora = Join-Path $carpeta "bitacora.log"

# Quita saltos de línea y caracteres raros, y recorta el largo
function Limpiar-Texto-Log($texto, $max = 80) {
    if ($texto -eq $null -or "$texto" -eq "") { return "-" }
    $t = [string]$texto
    $t = $t -replace '[\x00-\x1F\x7F]', ' '
    if ($t.Length -gt $max) { $t = $t.Substring(0, $max) }
    return $t
}

function Registrar-Evento($evento, $usuario, $area, $detalle) {
    try {
        $linea = "{0} | {1} | {2} | {3} | {4}" -f `
            (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), `
            $evento, `
            (Limpiar-Texto-Log $usuario 60), `
            (Limpiar-Texto-Log $area 40), `
            (Limpiar-Texto-Log $detalle 200)
        [System.IO.File]::AppendAllText($archivoBitacora, $linea + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
    } catch { }
}

# ---------- Vista previa de Word, Excel y PowerPoint ----------
# El navegador solo sabe mostrar PDF, asi que el servidor convierte el archivo
# a PDF usando Microsoft Office (instalado en esta computadora) y guarda el
# resultado en cache_vistas/. La siguiente vez se entrega el PDF ya hecho,
# salvo que el archivo original haya cambiado.

# Se ejecuta en un proceso aparte (Start-Job) para poder cortarlo si Office se traba.
$bloqueConversion = {
    param($origen, $destino, $programa)

    $ErrorActionPreference = "Stop"
    $app = $null
    $doc = $null
    try {
        switch ($programa) {
            "word" {
                $app = New-Object -ComObject Word.Application
                $app.Visible = $false
                $app.DisplayAlerts = 0
                # (archivo, confirmar conversion, solo lectura, recientes, contrasena falsa)
                # La contrasena falsa hace que un archivo protegido falle en vez de abrir un cuadro de dialogo.
                $doc = $app.Documents.Open($origen, $false, $true, $false, "x-sin-clave")
                $doc.ExportAsFixedFormat($destino, 17)   # 17 = PDF
                $doc.Close($false)
                if ($app.Documents.Count -eq 0) { $app.Quit() }
            }
            "excel" {
                $app = New-Object -ComObject Excel.Application
                $app.Visible = $false
                $app.DisplayAlerts = $false
                # (archivo, no actualizar vinculos, solo lectura, formato, contrasena falsa)
                $doc = $app.Workbooks.Open($origen, 0, $true, 5, "x-sin-clave")
                $doc.ExportAsFixedFormat(0, $destino)    # 0 = PDF
                $doc.Close($false)
                if ($app.Workbooks.Count -eq 0) { $app.Quit() }
            }
            "powerpoint" {
                $app = New-Object -ComObject PowerPoint.Application
                # (archivo, solo lectura, sin titulo, sin ventana)  -1 = verdadero, 0 = falso
                $doc = $app.Presentations.Open($origen, -1, 0, 0)
                $doc.SaveAs($destino, 32)                # 32 = PDF
                $doc.Close()
                # PowerPoint comparte una sola ventana: solo se cierra si nadie mas lo usa
                if ($app.Presentations.Count -eq 0) { $app.Quit() }
            }
        }
        return "ok"
    } catch {
        return "error: " + $_.Exception.Message
    } finally {
        foreach ($o in @($doc, $app)) {
            if ($o -ne $null) { try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($o) } catch { } }
        }
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
    }
}

# Devuelve la ruta del PDF listo, o $null si no se pudo convertir (en $script:errorVista queda el motivo)
function Obtener-PdfVista($rutaOriginal, $programa) {
    $script:errorVista = ""

    if (-not (Test-Path -LiteralPath $carpetaVistas)) { New-Item -ItemType Directory -Path $carpetaVistas | Out-Null }

    # Nombre del PDF: huella (SHA-256) de la ruta, para no repetir nombres entre carpetas
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $huella = ($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($rutaOriginal.ToLower())) |
        ForEach-Object { $_.ToString("x2") }) -join ""
    $sha.Dispose()
    $pdf = Join-Path $carpetaVistas ($huella + ".pdf")

    # Si ya existe y es mas nuevo que el original, se reutiliza
    if (Test-Path -LiteralPath $pdf) {
        if ((Get-Item -LiteralPath $pdf).LastWriteTime -ge (Get-Item -LiteralPath $rutaOriginal).LastWriteTime) { return $pdf }
    }

    $temporal = Join-Path $carpetaVistas ($huella + ".tmp.pdf")
    if (Test-Path -LiteralPath $temporal) { Remove-Item -LiteralPath $temporal -Force }

    $trabajo = Start-Job -ScriptBlock $bloqueConversion -ArgumentList $rutaOriginal, $temporal, $programa
    $termino = Wait-Job $trabajo -Timeout $segundosMaxConversion

    if ($termino -eq $null) {
        Stop-Job $trabajo
        Remove-Job $trabajo -Force
        $script:errorVista = "la conversion tardo demasiado"
        return $null
    }

    # Se toma solo la ultima linea que devolvio el proceso ("ok" o "error: ...")
    $salida = @(Receive-Job $trabajo)
    $resultado = ""
    if ($salida.Count -gt 0) { $resultado = [string]$salida[-1] }
    Remove-Job $trabajo -Force

    if ($resultado -ne "ok" -or -not (Test-Path -LiteralPath $temporal)) {
        if ($resultado -match "80040154|ProgID|clase no registrada|class not registered") {
            $script:errorVista = "Microsoft Office no esta instalado en esta computadora"
        } else {
            $script:errorVista = $resultado
        }
        return $null
    }

    Move-Item -LiteralPath $temporal -Destination $pdf -Force
    return $pdf
}

# Revisa que una ruta web ("documentos/<area>/...") exista y sea del area de la sesion.
# Devuelve @{ codigo = 200 | 403 | 404; completa; relativa }
function Resolver-Documento($rutaWeb, $sesion) {
    $completa = [System.IO.Path]::GetFullPath((Join-Path $carpeta $rutaWeb))
    if (-not $completa.StartsWith($raizDocsConSlash, [System.StringComparison]::OrdinalIgnoreCase)) {
        return @{ codigo = 404 }
    }
    $relativa = $completa.Substring($raizDocsConSlash.Length)
    if (-not $relativa.Contains('\') -or $relativa.Split('\')[0] -ne $sesion.area) {
        return @{ codigo = 403; relativa = $relativa }
    }
    if (-not (Test-Path -LiteralPath $completa -PathType Leaf)) { return @{ codigo = 404 } }
    return @{ codigo = 200; completa = $completa; relativa = $relativa }
}

function Procesar-Vista($request, $response) {
    $response.Headers.Add("Cache-Control", "no-store")
    $response.Headers.Add("X-Content-Type-Options", "nosniff")

    $sesion = Obtener-Sesion $request
    if ($sesion -eq $null) {
        Enviar-Texto $response 401 '{"error":"no autorizado"}' $json
        return
    }

    $rutaWeb = $request.QueryString["ruta"]
    if ([string]::IsNullOrWhiteSpace($rutaWeb)) {
        Enviar-Texto $response 400 '{"error":"falta la ruta"}' $json
        return
    }

    $doc = Resolver-Documento $rutaWeb $sesion
    if ($doc.codigo -eq 403) {
        Registrar-Evento "DOC_DENEGADO" $sesion.usuario $sesion.area $rutaWeb
        Enviar-Texto $response 403 '{"error":"acceso denegado"}' $json
        return
    }
    if ($doc.codigo -ne 200) {
        Enviar-Texto $response 404 '{"error":"archivo no encontrado"}' $json
        return
    }

    $extension = [System.IO.Path]::GetExtension($doc.completa).ToLower()
    if (-not $convertiblesOffice.ContainsKey($extension)) {
        Enviar-Texto $response 415 '{"error":"este tipo de archivo no se convierte"}' $json
        return
    }

    $pdf = Obtener-PdfVista $doc.completa $convertiblesOffice[$extension]
    if ($pdf -eq $null) {
        Registrar-Evento "VISTA_ERROR" $sesion.usuario $sesion.area ($doc.relativa + " - " + $script:errorVista)
        Enviar-Texto $response 500 ('{"error":"' + (Escapar-Json (Limpiar-Texto-Log $script:errorVista 150)) + '"}') $json
        return
    }

    Registrar-Evento "DOC_VISTA" $sesion.usuario $sesion.area $doc.relativa
    $bytes = [System.IO.File]::ReadAllBytes($pdf)
    $response.ContentType = "application/pdf"
    $response.ContentLength64 = $bytes.Length
    $response.OutputStream.Write($bytes, 0, $bytes.Length)
    $response.OutputStream.Close()
}

while ($listener.IsListening) {
    $context = $listener.GetContext()
    $request = $context.Request
    $response = $context.Response

    try {
        $rutaSolicitada = $request.Url.LocalPath.TrimStart('/')
        if ($rutaSolicitada -eq "") { $rutaSolicitada = "index.html" }
        $metodo = $request.HttpMethod

        # ---------- API ----------
        if ($rutaSolicitada -eq "api/login" -and $metodo -eq "POST") {
            Procesar-Login $request $response
            continue 
        }

        if ($rutaSolicitada -eq "api/logout" -and $metodo -eq "POST") {
            Procesar-Logout $request $response
            continue
        }

        if ($rutaSolicitada -eq "api/archivos") {
            $response.Headers.Add("Cache-Control", "no-store")
            $sesion = Obtener-Sesion $request
            if ($sesion -eq $null) {
                Enviar-Texto $response 401 '{"error":"no autorizado"}' $json
                continue
            }
            $area = Escapar-Json $sesion.area
            $lista = Listar-ArchivosArea $sesion.area
            $subcarpetas = Listar-Subcarpetas $sesion.area
            Enviar-Texto $response 200 "{ `"area`": `"$area`", `"subcarpetas`": $subcarpetas, `"archivos`": $lista }" $json
            continue
        }

        if ($rutaSolicitada -eq "api/vista") {
            Procesar-Vista $request $response
            continue
        }

        if ($rutaSolicitada.StartsWith("api/")) {
            Enviar-Texto $response 404 "404" "text/plain; charset=utf-8"
            continue
        }

        # ---------- ARCHIVOS ESTATICOS ----------
        $rutaCompleta = [System.IO.Path]::GetFullPath((Join-Path $carpeta $rutaSolicitada))

        # Nunca salir de la carpeta del proyecto (evita ../)
        if (-not $rutaCompleta.StartsWith($carpetaBase, [System.StringComparison]::OrdinalIgnoreCase)) {
            Enviar-Texto $response 404 "404" "text/plain; charset=utf-8"
            continue
        }

        $extension = [System.IO.Path]::GetExtension($rutaCompleta).ToLower()
        $esDocumento = $rutaCompleta.StartsWith($raizDocsConSlash, [System.StringComparison]::OrdinalIgnoreCase)

        if ($esDocumento) {
            # Los documentos exigen sesion y que el archivo sea del area de esa sesion
            $response.Headers.Add("Cache-Control", "no-store")
            $response.Headers.Add("X-Content-Type-Options", "nosniff")

            $sesion = Obtener-Sesion $request
            if ($sesion -eq $null) {
                Enviar-Texto $response 401 "Acceso no autorizado" "text/plain; charset=utf-8"
                continue
            }

            $relativa = $rutaCompleta.Substring($raizDocsConSlash.Length)
            if (-not $relativa.Contains('\')) {
                Enviar-Texto $response 403 "Acceso denegado" "text/plain; charset=utf-8"
                continue
            }

           $areaArchivo = $relativa.Split('\')[0]
            if ($areaArchivo -ne $sesion.area) {
                Registrar-Evento "DOC_DENEGADO" $sesion.usuario $sesion.area $rutaSolicitada
                Enviar-Texto $response 403 "Acceso denegado" "text/plain; charset=utf-8"
                continue
            }
        } else {
            # Fuera de documentos/: solo tipos web publicos
            if ($extensionesPublicas -notcontains $extension) {
                Enviar-Texto $response 404 "404" "text/plain; charset=utf-8"
                continue
            }
        }

       if (Test-Path $rutaCompleta -PathType Leaf) {
            if ($esDocumento) {
                Registrar-Evento "DOC_ABIERTO" $sesion.usuario $sesion.area $relativa
            }
            $bytes = [System.IO.File]::ReadAllBytes($rutaCompleta)

            if ($tiposContenido.ContainsKey($extension)) {
                $response.ContentType = $tiposContenido[$extension]
            } else {
                $response.ContentType = "application/octet-stream"
            }

            $response.ContentLength64 = $bytes.Length
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
            $response.OutputStream.Close()
        } else {
            Enviar-Texto $response 404 "404 - Archivo no encontrado" "text/plain; charset=utf-8"
        }
    } catch {
        try { $response.Abort() } catch { }
    }
}
