// =====================================================
// Datos comunes
// =====================================================

// Lee el parámetro "area" de la URL (ej: login.html?area=tecnica)
const params = new URLSearchParams(window.location.search);
const areaSolicitada = params.get('area');

// Nombres de las áreas para mostrar en la interfaz
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
                } else if (respuesta.status === 429) {
                    return respuesta.json().then(d => {
                        mensajeError.textContent =
                            `Demasiados intentos fallidos. Intenta de nuevo en ${d.minutos} minuto(s).`;
                    });
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

    // Tipos que el servidor convierte a PDF con Microsoft Office
    const tiposOffice = ['word', 'excel', 'powerpoint'];

    // Cada vez que se abre un archivo sube este número; así, si el usuario
    // cambia de archivo antes de que termine la conversión, se ignora la respuesta vieja.
    let aperturaActual = 0;
    let urlTemporal = null; // URL "blob:" del PDF convertido (se libera al cerrar)

    // Crea un elemento con clase y texto sin usar innerHTML (evita inyectar HTML con el nombre del archivo)
    function crear(etiqueta, clase, texto) {
        const el = document.createElement(etiqueta);
        if (clase) el.className = clase;
        if (texto) el.textContent = texto;
        return el;
    }

    // urlVista: lo que se muestra (el PDF). urlOriginal: el archivo que se descarga.
    function mostrarVisorPdf(contenedor, urlVista, urlOriginal, nombre) {
        const iframe = crear('iframe', 'iframe-pdf');
        iframe.src = urlVista;
        iframe.title = 'Vista previa de ' + nombre;

        const pestana = crear('a', 'btn-secundario', 'Abrir en una pestaña nueva');
        pestana.href = urlVista;
        pestana.target = '_blank';

        contenedor.replaceChildren(iframe, filaAcciones(pestana, botonDescargar(urlOriginal)));
    }

    function botonDescargar(url) {
        const enlace = crear('a', 'btn-descargar', 'Descargar');
        enlace.href = url;
        enlace.setAttribute('download', '');
        return enlace;
    }

    // Agrupa los botones en una fila con espacio entre ellos
    function filaAcciones(...botones) {
        const fila = crear('div', 'acciones-vista');
        fila.append(...botones);
        return fila;
    }

    function abrirModalArchivo(archivo) {
        const numero = ++aperturaActual;
        liberarUrlTemporal();

        document.getElementById('modalNombreArchivo').textContent = archivo.nombre;
        document.getElementById('modalTipoArchivo').textContent = archivo.tipo.toUpperCase();

        const contenedorPrevia = document.getElementById('modalVistaPrevia');
        const url = urlSegura(archivo.ruta);
        document.getElementById('modalArchivo').style.display = 'flex';

        if (archivo.tipo === 'pdf') {
            mostrarVisorPdf(contenedorPrevia, url, url, archivo.nombre);

        } else if (archivo.tipo === 'imagen') {
            const img = crear('img', 'vista-imagen');
            img.src = url;
            img.alt = archivo.nombre;
            contenedorPrevia.replaceChildren(img, filaAcciones(botonDescargar(url)));

        } else if (archivo.tipo === 'texto') {
            contenedorPrevia.replaceChildren(crear('p', 'vista-cargando', 'Cargando...'));
            fetch(url)
                .then(r => r.ok ? r.text() : Promise.reject(r.status))
                .then(texto => {
                    if (numero !== aperturaActual) return;
                    const pre = crear('pre', 'vista-texto');
                    pre.textContent = texto; // textContent: se muestra tal cual, sin interpretar HTML
                    contenedorPrevia.replaceChildren(pre, filaAcciones(botonDescargar(url)));
                })
                .catch(() => {
                    if (numero !== aperturaActual) return;
                    contenedorPrevia.replaceChildren(
                        crear('p', 'vista-error', 'No se pudo leer el archivo.'),
                        filaAcciones(botonDescargar(url)));
                });

        } else if (tiposOffice.includes(archivo.tipo)) {
            // El servidor convierte el archivo a PDF. La primera vez tarda unos segundos;
            // después se reutiliza el PDF guardado mientras el original no cambie.
            const cargando = crear('div', 'vista-cargando');
            cargando.append(crear('span', 'spinner'), crear('span', '', 'Generando vista previa...'));
            contenedorPrevia.replaceChildren(cargando);

            fetch('/api/vista?ruta=' + encodeURIComponent(archivo.ruta))
                .then(respuesta => {
                    if (respuesta.status === 401) { window.location.href = 'index.html'; return null; }
                    if (!respuesta.ok) {
                        return respuesta.json()
                            .catch(() => ({}))
                            .then(d => Promise.reject(d.error || 'error ' + respuesta.status));
                    }
                    return respuesta.blob();
                })
                .then(pdf => {
                    if (!pdf || numero !== aperturaActual) return;
                    urlTemporal = URL.createObjectURL(pdf);
                    // Se ve el PDF convertido, pero se descarga el archivo original (.docx, .xlsx, .pptx)
                    mostrarVisorPdf(contenedorPrevia, urlTemporal, url, archivo.nombre);
                })
                .catch(motivo => {
                    if (numero !== aperturaActual) return;
                    console.error(motivo);
                    const mensaje = typeof motivo === 'string'
                        ? 'No se pudo generar la vista previa (' + motivo + ').'
                        : 'No se pudo generar la vista previa.';
                    contenedorPrevia.replaceChildren(
                        crear('p', 'vista-error', mensaje),
                        filaAcciones(botonDescargar(url)));
                });

        } else {
            contenedorPrevia.replaceChildren(
                crear('p', '', 'Este tipo de archivo no se puede previsualizar en el navegador.'),
                filaAcciones(botonDescargar(url)));
        }
    }

    function liberarUrlTemporal() {
        if (urlTemporal) {
            URL.revokeObjectURL(urlTemporal);
            urlTemporal = null;
        }
    }

    function cerrarModalArchivo() {
        aperturaActual++; // cancela cualquier conversión que siga en camino
        document.getElementById('modalArchivo').style.display = 'none';
        document.getElementById('modalVistaPrevia').replaceChildren();
        liberarUrlTemporal();
    }

    // Cerrar el modal con la tecla Escape
    document.addEventListener('keydown', (evento) => {
        if (evento.key === 'Escape') cerrarModalArchivo();
    });

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
                    tarjeta.append(
                        crear('p', 'nombre-archivo', archivo.nombre),
                        crear('span', 'tipo-archivo', archivo.tipo.toUpperCase())
                    );

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
