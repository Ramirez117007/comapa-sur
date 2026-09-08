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
