// 1. Lee el parámetro "area" de la URL (ej: login.html?area=tecnica)
const params = new URLSearchParams(window.location.search);
const areaSolicitada = params.get('area');

// 2. Nombres bonitos para mostrar en pantalla
const nombresArea = {
    general: "Gerencia General",
    administrativa: "Gerencia Administrativa",
    tecnica: "Gerencia Técnica",
    comercial: "Gerencia Comercial",
    proyectos: "Gerencia de Proyectos Estratégicos"
};

const elementoArea = document.getElementById('nombreArea');
if (elementoArea) {
    elementoArea.textContent = nombresArea[areaSolicitada] || "Área no reconocida";
}

// 3. Cuando envían el formulario
const formulario = document.getElementById('formLogin');
const mensajeError = document.getElementById('mensajeError');

if (formulario) {
    formulario.addEventListener('submit', function (evento) {
        evento.preventDefault(); // evita que la página se recargue sola

        const usuario = document.getElementById('usuario').value.trim();
        const password = document.getElementById('password').value;

        fetch('usuarios.json')
            .then(respuesta => respuesta.json())
            .then(usuarios => {
                const encontrado = usuarios.find(u =>
                    u.usuario === usuario &&
                    u.password === password &&
                    u.area === areaSolicitada
                );

                if (encontrado) {
                    sessionStorage.setItem('areaAutenticada', areaSolicitada);
                    window.location.href = 'archivos.html';
                } else {
                    mensajeError.textContent = "Usuario, contraseña o área incorrectos.";
                }
            })
            .catch(error => {
                mensajeError.textContent = "Error al validar. Intenta de nuevo.";
                console.error(error);
            });
    });
}


// Solo corre este bloque si estamos en archivos.html
const contenedorArchivos = document.getElementById('listaArchivos');

if (contenedorArchivos) {

    // 1. Revisa la libretita (sessionStorage) ANTES de mostrar nada
    const areaGuardada = sessionStorage.getItem('areaAutenticada');

    if (!areaGuardada) {
        // Nadie inició sesión: fuera de aquí, de regreso al inicio
        window.location.href = 'index.html';
    } else {
        // 2. Muestra el nombre del área en el título
        document.getElementById('tituloArea').textContent = nombresArea[areaGuardada] || areaGuardada;

        // 3. Trae la lista de archivos y filtra solo los de esta área
        fetch('archivos.json')
            .then(respuesta => respuesta.json())
            .then(todosLosArchivos => {
                const archivosDelArea = todosLosArchivos[areaGuardada] || [];

                if (archivosDelArea.length === 0) {
                    document.getElementById('sinArchivos').style.display = 'block';
                    return;
                }

                archivosDelArea.forEach(archivo => {
                    const tarjeta = document.createElement('div');
                    tarjeta.className = 'tarjeta-archivo';
                    tarjeta.innerHTML = `
                        <p class="nombre-archivo">${archivo.nombre}</p>
                        <span class="tipo-archivo">${archivo.tipo.toUpperCase()}</span>
                    `;
                    contenedorArchivos.appendChild(tarjeta);
                });
            });

        // 4. Botón de cerrar sesión
        document.getElementById('btnSalir').addEventListener('click', function () {
            sessionStorage.removeItem('areaAutenticada');
            window.location.href = 'index.html';
        });
    }
}

// Solo corre si estamos en index.html (donde existe el submenú de Gerencias)
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