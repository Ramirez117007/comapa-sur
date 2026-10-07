# servidor.ps1
# Servidor local simple para el proyecto COMAPA Sur.
# Sirve todos los archivos de esta misma carpeta y abre el navegador automaticamente.
# Ademas, genera "archivos.json" en automatico escaneando la carpeta documentos/,
# para que agregar un archivo nuevo no requiera tocar ningun codigo.

$puerto = 5500
$carpeta = $PSScriptRoot   # la carpeta donde vive este mismo script

function Generar-ArchivosJson {
    $raizDocumentos = Join-Path $carpeta "documentos"
    $areasJson = @()

    if (Test-Path $raizDocumentos) {
        $carpetasArea = Get-ChildItem -Path $raizDocumentos -Directory | Sort-Object Name

        foreach ($carpetaArea in $carpetasArea) {
            $area = $carpetaArea.Name
            $archivosJson = @()

            $archivos = Get-ChildItem -Path $carpetaArea.FullName -File | Sort-Object Name

            foreach ($archivo in $archivos) {
                $extension = $archivo.Extension.ToLower()
                $tipo = switch ($extension) {
                    ".pdf"  { "pdf" }
                    ".xlsx" { "excel" }
                    ".xls"  { "excel" }
                    ".doc"  { "word" }
                    ".docx" { "word" }
                    default { "archivo" }
                }

                # Escapa comillas dobles por si algun nombre de archivo las trajera
                $nombreEscapado = $archivo.Name -replace '"', '\"'
                $rutaEscapada = "documentos/$area/$nombreEscapado"

                $archivosJson += "{ `"nombre`": `"$nombreEscapado`", `"tipo`": `"$tipo`", `"ruta`": `"$rutaEscapada`" }"
            }

            $listaTexto = "[" + ($archivosJson -join ",") + "]"
            $areasJson += "`"$area`": $listaTexto"
        }
    }

    return "{" + ($areasJson -join ",") + "}"
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$puerto/")

try {
    $listener.Start()
} catch {
    Write-Host "No se pudo iniciar el servidor en el puerto $puerto."
    Write-Host "Puede que ya haya otro programa usando ese puerto (por ejemplo Live Server)."
    Write-Host "Cierra ese otro programa e intenta de nuevo, o cambia el numero de puerto en este script."
    pause
    exit
}

Write-Host "Servidor COMAPA Sur corriendo en http://localhost:$puerto/"
Write-Host "La lista de archivos se genera en automatico desde la carpeta documentos/"
Write-Host "Para detenerlo, cierra esta ventana o presiona Ctrl+C."
Write-Host ""

Start-Process "http://localhost:$puerto/index.html"

while ($listener.IsListening) {
    $context = $listener.GetContext()
    $request = $context.Request
    $response = $context.Response

    $rutaSolicitada = $request.Url.LocalPath.TrimStart('/')
    if ($rutaSolicitada -eq "") { $rutaSolicitada = "index.html" }

    if ($rutaSolicitada -eq "archivos.json") {
        # En vez de leer un archivo fijo, lo generamos en vivo
        $json = Generar-ArchivosJson
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)

        $response.ContentType = "application/json; charset=utf-8"
        $response.ContentLength64 = $bytes.Length
        $response.OutputStream.Write($bytes, 0, $bytes.Length)
        $response.OutputStream.Close()
        continue
    }

    $rutaCompleta = Join-Path $carpeta $rutaSolicitada

    if (Test-Path $rutaCompleta -PathType Leaf) {
        $bytes = [System.IO.File]::ReadAllBytes($rutaCompleta)

        switch ([System.IO.Path]::GetExtension($rutaCompleta)) {
            ".html" { $response.ContentType = "text/html; charset=utf-8" }
            ".css"  { $response.ContentType = "text/css" }
            ".js"   { $response.ContentType = "application/javascript" }
            ".json" { $response.ContentType = "application/json" }
            ".jpg"  { $response.ContentType = "image/jpeg" }
            ".jpeg" { $response.ContentType = "image/jpeg" }
            ".png"  { $response.ContentType = "image/png" }
            ".pdf"  { $response.ContentType = "application/pdf" }
            ".xlsx" { $response.ContentType = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" }
            default { $response.ContentType = "application/octet-stream" }
        }

        $response.ContentLength64 = $bytes.Length
        $response.OutputStream.Write($bytes, 0, $bytes.Length)
    } else {
        $response.StatusCode = 404
        $mensaje = [System.Text.Encoding]::UTF8.GetBytes("404 - Archivo no encontrado: $rutaSolicitada")
        $response.OutputStream.Write($mensaje, 0, $mensaje.Length)
    }

    $response.OutputStream.Close()
}
