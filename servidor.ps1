# servidor.ps1
# Servidor local simple para el proyecto COMAPA Sur.
# Sirve todos los archivos de esta misma carpeta y abre el navegador automaticamente.

$puerto = 5500
$carpeta = $PSScriptRoot   # la carpeta donde vive este mismo script

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
Write-Host "Para detenerlo, cierra esta ventana o presiona Ctrl+C."
Write-Host ""

Start-Process "http://localhost:$puerto/index.html"

while ($listener.IsListening) {
    $context = $listener.GetContext()
    $request = $context.Request
    $response = $context.Response

    $rutaSolicitada = $request.Url.LocalPath.TrimStart('/')
    if ($rutaSolicitada -eq "") { $rutaSolicitada = "index.html" }

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
