// =====================================================
// Datos comunes
// =====================================================

// Lee el parámetro "area" de la URL (ej: login.html?area=tecnica)
const params = new URLSearchParams(window.location.search);
const areaSolicitada = params.get('area');

// Nombres bonitos para mostrar en pantalla
const nombresArea = {
    general: "Gerencia General",
    administrativa: "Gerencia Administrativa",
    tecnica: "Gerencia Técnica",
    comercial: "Gerencia Comercial",
    proyectos: "Gerencia de Proyectos Estratégicos"
};

// Convierte "documentos/tecnica/Mi archivo #1.pdf" en una URL segura
function urlSegura(ruta) {
    return ruta.split('/').map(encodeURIComponent).join('/');
}

// =====================================================
// login.html
// =====================================================
const elementoArea = document.getElementById('nombreArea');
if (elementoArea) {
    elementoArea.textContent = nombresArea[areaSolicitada] || "Área no reconocida";
}

const formulario = document.getElementById('formLogin');
const mensajeError = document.getElementById('mensajeError');

if (formulario) {
    formulario.addEventListener('submit', function (evento) {
        evento.preventDefault(); // evita que la página se recargue sola

        const usuario = document.getElementById('usuario').value.trim();
        const password = document.getElementById('password').value;

        // El servidor valida usuario, contraseña y área, y crea la sesión (cookie)
        fetch('/api/login', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ usuario: usuario, password: password, area: areaSolicitada })
        })
            .then(respuesta => {
                if (respuesta.ok) {
                    window.location.href = 'archivos.html';
                } else {
                    mensajeError.textContent = "Usuario, contraseña o área incorrectos.";
                }
            })
            .catch(error => {
                mensajeError.textContent = "No se pudo conectar con el servidor. ¿Abriste iniciar.bat?";
                console.error(error);
            });
    });
}

// =====================================================
// archivos.html
// =====================================================
const contenedorArchivos = document.getElementById('listaArchivos');

if (contenedorArchivos) {

    function abrirModalArchivo(archivo) {
        document.getElementById('modalNombreArchivo').textContent = archivo.nombre;
        document.getElementById('modalTipoArchivo').textContent = archivo.tipo.toUpperCase();

        const contenedorPrevia = document.getElementById('modalVistaPrevia');
        const url = urlSegura(archivo.ruta);

        if (archivo.tipo === 'pdf') {
            contenedorPrevia.innerHTML = `
                <iframe src="${url}" class="iframe-pdf" title="Vista previa de ${archivo.nombre}"></iframe>
                <a href="${url}" target="_blank" class="link-pestana-nueva">Abrir en una pestaña nueva</a>
            `;
        } else {
            contenedorPrevia.innerHTML = `
                <p>Este tipo de archivo no se puede previsualizar directo en el navegador.</p>
                <a href="${url}" download class="btn-descargar">Descargar ${archivo.nombre}</a>
            `;
        }

        document.getElementById('modalArchivo').style.display = 'flex';
    }

    function cerrarModalArchivo() {
        document.getElementById('modalArchivo').style.display = 'none';
        document.getElementById('modalVistaPrevia').innerHTML = '';
    }

    // El servidor decide quién eres: si no hay sesión válida responde 401
    fetch('/api/archivos')
        .then(respuesta => {
            if (respuesta.status === 401) {
                window.location.href = 'index.html';
                return null;
            }
            return respuesta.json();
        })
        .then(datos => {
            if (!datos) return;

            document.getElementById('tituloArea').textContent = nombresArea[datos.area] || datos.area;

            if (datos.archivos.length === 0) {
                document.getElementById('sinArchivos').style.display = 'block';
                return;
            }

            datos.archivos.forEach(archivo => {
                const tarjeta = document.createElement('div');
                tarjeta.className = 'tarjeta-archivo';
                tarjeta.setAttribute('tabindex', '0'); // para poder llegar con Tab
                tarjeta.innerHTML = `
                    <p class="nombre-archivo">${archivo.nombre}</p>
                    <span class="tipo-archivo">${archivo.tipo.toUpperCase()}</span>
                `;

                tarjeta.addEventListener('click', () => abrirModalArchivo(archivo));
                tarjeta.addEventListener('keydown', (evento) => {
                    if (evento.key === 'Enter') abrirModalArchivo(archivo);
                });

                contenedorArchivos.appendChild(tarjeta);
            });
        })
        .catch(error => {
            console.error(error);
            document.getElementById('tituloArea').textContent = "Error de conexión";
        });

    // Cerrar el modal con el botón
    document.getElementById('btnCerrarModal').addEventListener('click', cerrarModalArchivo);

    // Cerrar el modal si dan clic fuera de la tarjeta blanca
    document.getElementById('modalArchivo').addEventListener('click', (evento) => {
        if (evento.target.id === 'modalArchivo') cerrarModalArchivo();
    });

    // Cerrar sesión: el servidor borra la sesión y la cookie
    document.getElementById('btnSalir').addEventListener('click', function () {
        fetch('/api/logout', { method: 'POST' })
            .finally(() => { window.location.href = 'index.html'; });
    });
}

// =====================================================
// index.html: submenú de Gerencias (clic/teclado además de hover)
// =====================================================
const menuVertical = document.querySelector('.menu-vertical');

if (menuVertical) {
    const liGerencias = menuVertical.closest('li');
    const linkGerencias = liGerencias.querySelector(':scope > a');

    linkGerencias.addEventListener('click', function (evento) {
        evento.preventDefault(); // el href="#" no debe saltar ni recargar nada
        liGerencias.classList.toggle('activo');
    });

    // Si das clic en cualquier otra parte de la página, se cierra el submenú
    document.addEventListener('click', function (evento) {
        if (!liGerencias.contains(evento.target)) {
            liGerencias.classList.remove('activo');
        }
    });
}
