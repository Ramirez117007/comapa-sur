# servidor.ps1
# Servidor local para el proyecto COMAPA Sur, con sesiones del lado del servidor.
#
# - El login se valida AQUI (usuarios.json nunca se envia al navegador).
# - Al iniciar sesion, el servidor entrega una cookie con un identificador aleatorio.
# - Los archivos de documentos/<area>/ solo se entregan si la sesion pertenece a esa area.
# - La lista de archivos se genera en vivo escaneando documentos/<area>/.

$puerto = 5500
$carpeta = $PSScriptRoot
$carpetaBase = $carpeta.TrimEnd('\') + '\'
$raizDocumentos = Join-Path $carpeta "documentos"
$raizDocsConSlash = $raizDocumentos.TrimEnd('\') + '\'
$duracionSesionHoras = 8

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
    ".xlsx"  = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
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

function Listar-ArchivosArea($area) {
    $items = @()
    $carpetaArea = Join-Path $raizDocumentos $area

    if (Test-Path $carpetaArea -PathType Container) {
        $archivos = Get-ChildItem -Path $carpetaArea -File | Sort-Object Name
        foreach ($archivo in $archivos) {
            $tipo = switch ($archivo.Extension.ToLower()) {
                ".pdf"  { "pdf" }
                ".xlsx" { "excel" }
                ".xls"  { "excel" }
                ".doc"  { "word" }
                ".docx" { "word" }
                default { "archivo" }
            }
            $nombre = Escapar-Json $archivo.Name
            $ruta = Escapar-Json "documentos/$area/$($archivo.Name)"
            $items += "{ `"nombre`": `"$nombre`", `"tipo`": `"$tipo`", `"ruta`": `"$ruta`" }"
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

    try {
        $rutaUsuarios = Join-Path $carpeta "usuarios.json"
        $usuarios = Get-Content -Path $rutaUsuarios -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Enviar-Texto $response 500 '{"ok":false}' $json
        return
    }

    $encontrado = $null
    foreach ($u in $usuarios) {
        if ($u.usuario -ceq $datos.usuario -and $u.password -ceq $datos.password -and $u.area -ceq $datos.area) {
            $encontrado = $u
            break
        }
    }

    if ($encontrado -eq $null) {
        Start-Sleep -Milliseconds 500   # frena un poco los intentos repetidos
        Enviar-Texto $response 401 '{"ok":false}' $json
        return
    }

    $token = Nuevo-Token
    $sesiones[$token] = @{
        area   = $encontrado.area
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
            Enviar-Texto $response 200 "{ `"area`": `"$area`", `"archivos`": $lista }" $json
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
