# Simulación Local de Deploy con Kamal

Esta guía te permite desplegar tu aplicación en un entorno local aislado que simula ser un servidor VPS (como un Droplet de DigitalOcean).

## Requisitos Previos

1.  **Docker Desktop** (o Docker Engine) corriendo en tu máquina.
2.  Tener tus claves SSH configuradas (`~/.ssh/id_rsa.pub` debe existir).

## Paso 1: Levantar el Servidor Simulado

Navega al directorio de simulación y levanta el contenedor:

```bash
cd local_simulation
docker-compose up -d
```

Esto iniciará un contenedor `yuntapp-mock-server` que escucha en:
-   **Puerto SSH**: 2222 (Mapeado al 22 del contenedor)
-   **Puerto Web**: 8080 (Mapeado al 80 del contenedor)

## Paso 2: Verificar Conexión

Intenta conectarte por SSH para asegurar que todo funciona. La contraseña no debería ser necesaria si tu clave pública se montó correctamente (el script busca `~/.ssh/id_ed25519.pub` por defecto).

```bash
ssh -p 2222 root@127.0.0.1
```

Si te pide contraseña y tu clave no funciona, la contraseña es `root`.

## Paso 3: Configurar Variables de Entorno

Asegúrate de tener tu archivo `.env` configurado con las credenciales de tu registro (Docker Hub o DigitalOcean). Kamal necesita subir la imagen a un registro real para que luego el servidor local la descargue.

```bash
# Ejemplo de variables necesarias (en tu terminal o .env)
export KAMAL_REGISTRY_USERNAME="tu-usuario"
export KAMAL_REGISTRY_PASSWORD="tu-token"
export KAMAL_REGISTRY_IMAGE="tu-usuario/yuntapp"
export RAILS_MASTER_KEY="contenido-de-master-key"
```

## Paso 4: Realizar el Despliegue

Desde la raíz del proyecto, ejecuta los comandos de Kamal apuntando al archivo de configuración local:

**1. Configuración Inicial (Instala Docker en el "servidor", etc):**
```bash
kamal setup -c config/deploy.local.yml
```

**2. Despliegues Posteriores:**
```bash
kamal deploy -c config/deploy.local.yml
```

## Paso 5: Ver tu Aplicación

Una vez desplegado, abre tu navegador en:
[http://localhost:8080](http://localhost:8080)

## Limpieza

Para detener y borrar el servidor simulado:

```bash
cd local_simulation
docker-compose down -v
```
