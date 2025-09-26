#!/bin/bash
set -e

### === CONFIGURAÇÕES PERSONALIZÁVEIS === ###
COMUNICACAO="direta"  # direta, proxy, gateway
CERT_ORIGEM="/caminho/para/certificado.cer"

PROXY_HOST="proxy.exemplo.com"
PROXY_PORT="3128"
PROXY_USER="usuario_proxy"
PROXY_PASS="senha_proxy"

GATEWAY_HOST="gateway.exemplo.com"
GATEWAY_PORT="9635"

### === VERIFICAÇÃO DE PERMISSÃO SUDO === ###
if ! sudo -v; then
    echo "❌ Você precisa de permissão sudo para executar este script."
    exit 1
fi

### === PREPARAÇÃO DO AMBIENTE === ###
echo "🚀 Iniciando a preparação do ambiente..."

echo "⚠️ Selecione o setor para esta configuração: ⚠️"
PS3="Digite o número da opção e pressione Enter: "
options=("Prefeitura (Administrativos)" "Escolas" "Saúde")
select setor in "${options[@]}"; do
    case $REPLY in
        1) SETOR="adm"; break ;;
        2) SETOR="edu"; break ;;
        3) SETOR="sau"; break ;;
        *) echo "Opção inválida. Tente novamente." ;;
    esac
done
echo "Você escolheu o setor: $SETOR"

read -p "Digite o nome do setor ou unidade onde está realizando a configuração: " UNIDADE
echo "Setor/unidade configurado: $UNIDADE"

echo "Definindo hostname para ${SETOR}-${UNIDADE}..."
sudo hostnamectl set-hostname "${SETOR}-${UNIDADE}"

### === ATUALIZAÇÃO DE PACOTES COM TRATAMENTO DE ERROS === ###
echo "📡 Verificando atualização de pacotes configurados..."
if ! sudo apt-get update; then
    echo "⚠️ Erro ao atualizar pacotes. Tentando novamente com --fix-missing..."
    sudo apt-get update --fix-missing || { echo "❌ Falha ao atualizar pacotes."; exit 1; }
fi

echo "🚀 Iniciando instalação de pacotes disponíveis..."
if ! sudo apt-get upgrade -y; then
    echo "⚠️ Erro durante o upgrade. Tentando corrigir dependências..."
    sudo apt-get install -f -y
    sudo apt-get autoremove -y
    sudo apt-get autoclean -y
    echo "🔄 Tentando novamente o upgrade..."
    if ! sudo apt-get upgrade -y; then
        echo "❌ Não foi possível concluir o upgrade de pacotes."
        exit 1
    fi
fi

### === VERIFICAÇÃO SELINUX === ###
echo "🔧 Verificando SELinux..."
if command -v getenforce &> /dev/null; then
    selinux_status=$(getenforce)
    echo "→ SELinux está: $selinux_status"
    if [ "$selinux_status" = "Enforcing" ]; then
        echo "⚠️ Alterando SELinux para permissive..."
        sudo sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
        echo "⚠️ É necessário reiniciar o sistema para aplicar as mudanças no SELinux."
        read -p "Deseja reiniciar agora? (s/N): " resp
        if [[ "$resp" =~ ^[sS]$ ]]; then
            sudo reboot
            exit 0
        else
            echo "⚠️ Reinicialização adiada. Continue por sua conta e risco."
        fi
    fi
else
    echo "✔️ SELinux não está ativo ou não está instalado."
    sleep 2
fi

### === AJUSTES SYSCTL === ###
echo "🔧 Ajustando sysctl.conf para aumentar limites do inotify..."
sudo sed -i '/fs.inotify.max_user_instances/d' /etc/sysctl.conf
sudo sed -i '/fs.inotify.max_user_watches/d' /etc/sysctl.conf
echo "fs.inotify.max_user_instances=8192" | sudo tee -a /etc/sysctl.conf
echo "fs.inotify.max_user_watches=524288" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
echo "✅ Ajustes no sysctl.conf aplicados com sucesso."

### === INSTALAÇÃO DO AGENTE NDD === ###
echo -e "\n🚀 Iniciando a instalação do agente NDD..."
if ! sudo apt install ndd-dca-and-cloud-connector; then
    echo "⚠️ Erro durante a instalação do agente. Tentando corrigir problemas..."
    sudo apt-get install -f -y
    sudo apt-get autoremove -y
    sudo apt-get autoclean -y
    echo "🔄 Tentando novamente a instalação..."
    if ! sudo apt install ndd-dca-and-cloud-connector --fix-missing; then
        echo "❌ Não foi possível concluir a instalação do agente NDD mesmo após as correções."
        exit 1
    fi
fi
echo "✅ Agente NDD instalado com sucesso!"

### === CRIAÇÃO DO SCRIPT DE VERIFICAÇÃO DO SERVIÇO === ###
SERVICE_NAME="NDDPrinterMonitor"
cat <<EOF | sudo tee /usr/local/bin/verificar_ndd.sh > /dev/null
#!/bin/bash
SERVICE="$SERVICE_NAME"
echo "🔍 Verificando o status do serviço \$SERVICE no boot..."
if systemctl is-active --quiet "\$SERVICE"; then
    echo "✅ O serviço \$SERVICE está em execução."
else
    echo "⚠️ O serviço \$SERVICE não está rodando. Tentando iniciar..."
    systemctl start "\$SERVICE"
    if systemctl is-active --quiet "\$SERVICE"; then
        echo "✅ O serviço \$SERVICE foi iniciado com sucesso."
    else
        echo "❌ Não foi possível iniciar o serviço \$SERVICE. Verifique manualmente."
    fi
fi
EOF
sudo chmod +x /usr/local/bin/verificar_ndd.sh

cat <<EOF | sudo tee /etc/systemd/system/verificar-ndd.service > /dev/null
[Unit]
Description=Verifica o serviço NDDPrinterMonitor no boot
After=network.target

[Service]
ExecStart=/usr/local/bin/verificar_ndd.sh
Type=oneshot

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable verificar-ndd.service
echo "✅ Serviço de verificação criado e habilitado para iniciar com o sistema."

### === HOSTNAME E IP === ###
echo "📡 Hostname da máquina: $(hostname)"
IP_LOCAL=$(ip -4 addr show $(ip route get 8.8.8.8 | awk '{print $5; exit}') | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
echo "📡 IP local da máquina: $IP_LOCAL"

echo "✅ Instalação e configuração concluídas com sucesso!"
sudo systemctl status "$SERVICE_NAME"
