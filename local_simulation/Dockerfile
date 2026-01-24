FROM ubuntu:24.04

# Evitar prompts interactivos durante la instalación
ENV DEBIAN_FRONTEND=noninteractive

# Instalar dependencias necesarias: SSH, Docker, utilidades
RUN apt-get update && apt-get install -y \
    openssh-server \
    docker.io \
    curl \
    iproute2 \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Configurar SSH
RUN mkdir /var/run/sshd
# Permitir login como root (solo para este entorno de simulación)
RUN echo 'root:root' | chpasswd
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
# Permitir autenticación por clave pública si se monta el archivo authorized_keys
RUN mkdir -p /root/.ssh && chmod 700 /root/.ssh

# Configurar Docker para ejecutarse dentro del contenedor (Docker-in-Docker simple)
# Nota: Esto requiere que el contenedor se ejecute con --privileged
RUN mkdir -p /etc/docker

# Copiar script de inicio
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 22 80 443

ENTRYPOINT ["/entrypoint.sh"]
