# Guía de Despliegue con Kamal en DigitalOcean

Este documento detalla los pasos necesarios para desplegar la aplicación `yuntapp` en un servidor de DigitalOcean utilizando Kamal.

## 1. Requisitos Previos

### En DigitalOcean:
1.  **Crear un Droplet**:
    -   Imagen: Ubuntu 24.04 (LTS) x64.
    -   Plan: Basic (o el que necesites).
    -   Autenticación: **SSH Key**. Asegúrate de agregar tu clave pública SSH local al Droplet durante la creación.
2.  **Container Registry**:
    -   Puedes usar **DigitalOcean Container Registry** (gratuito para 1 repositorio) o **Docker Hub**.
    -   Si usas DigitalOcean, crea un registro y obtén un token de acceso (API Token) con permisos de lectura/escritura.

### En tu máquina local:
Asegúrate de tener instalados:
-   Docker (corriendo).
-   Ruby y la gema `kamal` (ya incluida en el proyecto).

## 2. Configuración de Variables de Entorno

El archivo `config/deploy.yml` ha sido configurado para leer valores sensibles desde variables de entorno. Antes de desplegar, debes definir estas variables en tu terminal.

Crea un archivo `.env` (si no existe, y asegúrate de que esté en `.gitignore`) o exporta las variables manualmente:

```bash
# Dirección IP de tu Droplet
export SERVER_IP="tu_direccion_ip_aqui"

# Configuración del Registro (ejemplo para Docker Hub)
# Si usas DigitalOcean Registry, el servidor suele ser registry.digitalocean.com/nombre-de-tu-registro
export KAMAL_REGISTRY_SERVER="docker.io"
export KAMAL_REGISTRY_USERNAME="tu_usuario_docker"
export KAMAL_REGISTRY_PASSWORD="tu_token_o_password"

# Nombre completo de la imagen (debe coincidir con el registro)
# Ej: docker.io/usuario/yuntapp o registry.digitalocean.com/mi-registro/yuntapp
export KAMAL_REGISTRY_IMAGE="usuario/yuntapp"

# La Master Key de Rails (contenido de config/master.key)
export RAILS_MASTER_KEY="contenido_de_tu_master_key"
```

> **Nota**: `RAILS_MASTER_KEY` es fundamental para que la aplicación pueda desencriptar las credenciales y arrancar.

## 3. Primer Despliegue

Una vez que tengas el servidor corriendo y las variables exportadas, ejecuta el comando de configuración inicial. Esto instalará Docker en el servidor y configurará los servicios necesarios.

```bash
kamal setup
```

Este proceso:
1.  Conectará al servidor vía SSH.
2.  Instalará Docker.
3.  Hará build de la imagen Docker localmente.
4.  Subirá la imagen al registro.
5.  Arrancará la aplicación y el proxy (Traefik) en el servidor.

## 4. Despliegues Posteriores

Para desplegar nuevas versiones de la aplicación después de hacer cambios en el código:

```bash
kamal deploy
```

## Solución de Problemas Comunes

-   **Error de SSH**: Asegúrate de que puedes entrar al servidor manualmente (`ssh root@$SERVER_IP`) con tu clave SSH.
-   **Falta Master Key**: Si el contenedor no arranca, revisa los logs con `kamal app logs`. A menudo es porque falta la `RAILS_MASTER_KEY`.
-   **Permisos de Registro**: Verifica que el usuario y token del registro tengan permisos de escritura (push).
