#!/bin/bash

# Criar pasta scanner em /home
cd /home || exit
sudo mkdir -p scanner

# Permissões na pasta
sudo chmod 777 scanner/

# Instalar Samba
sudo apt-get update
sudo apt-get install samba -y

# Configurar smb.conf
SMB_CONF="/etc/samba/smb.conf"

# Adicionar netbios name após workgroup
after_workgroup=$(grep -n "workgroup" "$SMB_CONF" | cut -d: -f1 | head -n1)
if [ -n "$after_workgroup" ]; then
    sudo sed -i "$((after_workgroup+1))i netbios name = scanner" "$SMB_CONF"
fi

# Adicionar a configuração do compartilhamento ao final do arquivo
sudo bash -c "cat >> $SMB_CONF << 'EOF'

[scanner]
path = /home/scanner
public = yes
browseable = yes
writable = yes
read only = no
guest ok = yes
create mask = 0777
directory mask = 0777
EOF"

# Reiniciar o serviço Samba
sudo systemctl restart smbd.service

echo "Configuração concluída com sucesso."
