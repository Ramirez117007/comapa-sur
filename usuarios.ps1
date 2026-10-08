# usuarios.ps1
# Herramienta de administracion de usuarios para el proyecto COMAPA Sur.
# Las contrasenas se guardan cifradas (PBKDF2) en usuarios.json, nunca en texto plano.
# Ejecutala con doble clic en usuarios.bat

$carpeta = $PSScriptRoot
$rutaUsuarios = Join-Path $carpeta "usuarios.json"
$raizDocumentos = Join-Path $carpeta "documentos"
$iteraciones = 100000

# ---------- Utilidades ----------

function Nuevo-Hash($password) {
    $sal = New-Object byte[] 16
    $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    $rng.GetBytes($sal)
    $rng.Dispose()

    $pbkdf2 = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($password, $sal, $iteraciones)
    $hash = $pbkdf2.GetBytes(32)
    $pbkdf2.Dispose()

    return 'pbkdf2$' + $iteraciones + '$' + [Convert]::ToBase64String($sal) + '$' + [Convert]::ToBase64String($hash)
}

function Leer-Password($mensaje) {
    $seguro = Read-Host $mensaje -AsSecureString
    $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($seguro)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
}

function Cargar-Usuarios {
    $lista = New-Object System.Collections.ArrayList
    if (Test-Path $rutaUsuarios) {
        $texto = Get-Content -Path $rutaUsuarios -Raw -Encoding UTF8
        if ($texto -and $texto.Trim().Length -gt 0) {
            $cargados = $texto | ConvertFrom-Json
            foreach ($u in $cargados) { [void]$lista.Add($u) }
        }
    }
    return ,$lista
}

function Guardar-Usuarios($lista) {
    $arreglo = $lista.ToArray()
    $json = ConvertTo-Json -InputObject $arreglo -Depth 5
    [System.IO.File]::WriteAllText($rutaUsuarios, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Estado-Password($u) {
    if ($u.hash) { return "cifrada" }
    if ($u.password) { return "TEXTO PLANO" }
    return "sin contrasena"
}

function Obtener-Areas {
    if (Test-Path $raizDocumentos) {
        return @(Get-ChildItem -Path $raizDocumentos -Directory | Sort-Object Name | ForEach-Object { $_.Name })
    }
    return @()
}

function Mostrar-Usuarios($usuarios) {
    Write-Host ""
    if ($usuarios.Count -eq 0) {
        Write-Host "  (no hay usuarios registrados)"
        return
    }
    for ($i = 0; $i -lt $usuarios.Count; $i++) {
        $u = $usuarios[$i]
        Write-Host ("  {0}) {1,-16} {2,-18} contrasena: {3}" -f ($i + 1), $u.area, $u.usuario, (Estado-Password $u))
    }
}

function Elegir-Numero($mensaje, $maximo) {
    $texto = Read-Host $mensaje
    $n = 0
    if ([int]::TryParse($texto, [ref]$n) -and $n -ge 1 -and $n -le $maximo) { return $n }
    return 0
}

function Pedir-PasswordNueva {
    $p1 = Leer-Password "Contrasena (minimo 6 caracteres)"
    if ($p1.Length -lt 6) {
        Write-Host "  La contrasena debe tener al menos 6 caracteres." -ForegroundColor Yellow
        return $null
    }
    $p2 = Leer-Password "Repite la contrasena"
    if ($p1 -cne $p2) {
        Write-Host "  Las contrasenas no coinciden." -ForegroundColor Yellow
        return $null
    }
    return $p1
}

# ---------- Acciones ----------

function Agregar-Usuario {
    $usuarios = Cargar-Usuarios
    $areas = @(Obtener-Areas)
    if ($areas.Count -eq 0) {
        Write-Host "  No hay carpetas dentro de documentos/ (una por gerencia)." -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "  Areas disponibles (carpetas de documentos/):"
    for ($i = 0; $i -lt $areas.Count; $i++) { Write-Host ("    {0}) {1}" -f ($i + 1), $areas[$i]) }

    $n = Elegir-Numero "Numero de area" $areas.Count
    if ($n -eq 0) { Write-Host "  Opcion no valida." -ForegroundColor Yellow; return }
    $area = $areas[$n - 1]

    $nombre = (Read-Host "Nombre de usuario").Trim()
    if ($nombre.Length -eq 0) { Write-Host "  El usuario no puede estar vacio." -ForegroundColor Yellow; return }

    foreach ($u in $usuarios) {
        if ($u.area -ceq $area -and $u.usuario -ceq $nombre) {
            Write-Host "  Ya existe ese usuario en esa area." -ForegroundColor Yellow
            return
        }
    }

    $password = Pedir-PasswordNueva
    if ($password -eq $null) { return }

    [void]$usuarios.Add([PSCustomObject]@{ area = $area; usuario = $nombre; hash = (Nuevo-Hash $password) })
    Guardar-Usuarios $usuarios
    Write-Host "  Usuario agregado." -ForegroundColor Green
}

function Eliminar-Usuario {
    $usuarios = Cargar-Usuarios
    Mostrar-Usuarios $usuarios
    if ($usuarios.Count -eq 0) { return }

    $n = Elegir-Numero "Numero del usuario a eliminar" $usuarios.Count
    if ($n -eq 0) { Write-Host "  Opcion no valida." -ForegroundColor Yellow; return }

    $u = $usuarios[$n - 1]
    $confirmar = Read-Host ("Eliminar a '{0}' de '{1}'? (s/n)" -f $u.usuario, $u.area)
    if ($confirmar -eq 's') {
        $usuarios.RemoveAt($n - 1)
        Guardar-Usuarios $usuarios
        Write-Host "  Usuario eliminado." -ForegroundColor Green
    } else {
        Write-Host "  Cancelado."
    }
}

function Cambiar-Password {
    $usuarios = Cargar-Usuarios
    Mostrar-Usuarios $usuarios
    if ($usuarios.Count -eq 0) { return }

    $n = Elegir-Numero "Numero del usuario" $usuarios.Count
    if ($n -eq 0) { Write-Host "  Opcion no valida." -ForegroundColor Yellow; return }

    $password = Pedir-PasswordNueva
    if ($password -eq $null) { return }

    $u = $usuarios[$n - 1]
    $u.PSObject.Properties.Remove('password')
    Add-Member -InputObject $u -NotePropertyName hash -NotePropertyValue (Nuevo-Hash $password) -Force
    Guardar-Usuarios $usuarios
    Write-Host "  Contrasena actualizada." -ForegroundColor Green
}

function Cifrar-ExistentesEnTextoPlano {
    $usuarios = Cargar-Usuarios
    $convertidos = 0

    foreach ($u in $usuarios) {
        if ($u.password -and -not $u.hash) {
            $nuevoHash = Nuevo-Hash ([string]$u.password)
            $u.PSObject.Properties.Remove('password')
            Add-Member -InputObject $u -NotePropertyName hash -NotePropertyValue $nuevoHash -Force
            $convertidos++
        }
    }

    if ($convertidos -gt 0) {
        Guardar-Usuarios $usuarios
        Write-Host ("  Se cifraron {0} contrasena(s). Las contrasenas siguen siendo las mismas." -f $convertidos) -ForegroundColor Green
    } else {
        Write-Host "  No habia contrasenas en texto plano."
    }
}

# ---------- Menu ----------

while ($true) {
    $usuarios = Cargar-Usuarios
    $enPlano = 0
    foreach ($u in $usuarios) { if ($u.password -and -not $u.hash) { $enPlano++ } }

    Write-Host ""
    Write-Host "=== Administracion de usuarios - COMAPA Sur ===" -ForegroundColor Cyan
    if ($enPlano -gt 0) {
        Write-Host ("  AVISO: hay {0} usuario(s) con contrasena en texto plano. Usa la opcion 5." -f $enPlano) -ForegroundColor Yellow
    }
    Write-Host "  1) Ver usuarios"
    Write-Host "  2) Agregar usuario"
    Write-Host "  3) Eliminar usuario"
    Write-Host "  4) Cambiar contrasena de un usuario"
    Write-Host "  5) Cifrar contrasenas existentes en texto plano"
    Write-Host "  0) Salir"

    $opcion = Read-Host "Elige una opcion"

    switch ($opcion) {
        "1" { Mostrar-Usuarios (Cargar-Usuarios) }
        "2" { Agregar-Usuario }
        "3" { Eliminar-Usuario }
        "4" { Cambiar-Password }
        "5" { Cifrar-ExistentesEnTextoPlano }
        "0" { exit }
        default { Write-Host "  Opcion no valida." -ForegroundColor Yellow }
    }
}
