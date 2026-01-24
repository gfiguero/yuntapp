#!/bin/bash
set -e

# Iniciar Docker Daemon en segundo plano
echo "Iniciando Docker Daemon..."
dockerd > /var/log/dockerd.log 2>&1 &

# Esperar a que Docker esté listo
echo "Esperando a que Docker esté listo..."
while ! docker info > /dev/null 2>&1; do
    sleep 1
done
echo "Docker está listo."

# Configurar authorized_keys desde el archivo montado
if [ -f /tmp/ssh_key.pub ]; then
    mkdir -p /root/.ssh
    cat /tmp/ssh_key.pub > /root/.ssh/authorized_keys
    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/authorized_keys
    echo "Claves SSH copiadas y permisos configurados."
fi

# Iniciar SSHD en primer plano (para mantener el contenedor corriendo)
echo "Iniciando servidor SSH..."
/usr/sbin/sshd -D
