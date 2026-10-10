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

// Quita acentos, pasa a minúsculas y trata _ y - como espacios
function normalizar(texto) {
    return texto
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '')
        .replace(/[_-]/g, ' ')
        .toLowerCase();
}
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

            const todos = datos.archivos;
            const carpetas = datos.subcarpetas || [];
            const contenedorPestanas = document.getElementById('pestanas');
            const aviso = document.getElementById('sinArchivos');
            let textoBusqueda = '';
            let filtroActual = null; // null = "Todos"

            // Dibuja las tarjetas según la pestaña elegida
            function dibujarArchivos() {
                contenedorArchivos.innerHTML = '';
                const porCarpeta = filtroActual === null
                    ? todos
                    : todos.filter(a => a.grupo === filtroActual);

                const visibles = textoBusqueda === ''
                    ? porCarpeta
                    : porCarpeta.filter(a => normalizar(a.nombre).includes(textoBusqueda));

                if (textoBusqueda !== '') {
                    aviso.textContent = 'No se encontraron archivos con esa búsqueda.';
                } else {
                    aviso.textContent = filtroActual === null
                        ? 'No hay archivos disponibles en esta área.'
                        : 'No hay archivos en esta carpeta.';
                }
                aviso.style.display = visibles.length === 0 ? 'block' : 'none';

                visibles.forEach(archivo => {
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
            }

            // Cambia el filtro y vuelve a dibujar las tarjetas
            function activarPestana(valor) {
                filtroActual = valor;
                dibujarArchivos();
            }

            // El selector solo aparece si el área tiene subcarpetas
            if (carpetas.length > 0) {
                const etiqueta = document.createElement('label');
                etiqueta.setAttribute('for', 'selectorCarpeta');
                etiqueta.textContent = 'Carpeta:';

                const selector = document.createElement('select');
                selector.id = 'selectorCarpeta';
                selector.className = 'selector-carpeta';

                const opcionTodos = document.createElement('option');
                opcionTodos.value = '';
                opcionTodos.textContent = `Todos (${todos.length})`;
                selector.appendChild(opcionTodos);

                carpetas.forEach(c => {
                    const opcion = document.createElement('option');
                    opcion.value = c;
                    opcion.textContent = `${c} (${todos.filter(a => a.grupo === c).length})`;
                    selector.appendChild(opcion);
                });

                selector.addEventListener('change', () => {
                    activarPestana(selector.value === '' ? null : selector.value);
                });

                contenedorPestanas.appendChild(etiqueta);
                contenedorPestanas.appendChild(selector);
                contenedorPestanas.style.display = 'flex';
            }
            const buscador = document.getElementById('buscador');
            buscador.addEventListener('input', () => {
                textoBusqueda = normalizar(buscador.value.trim());
                dibujarArchivos();
            });

            activarPestana(null); // empieza en "Todos"
            
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
