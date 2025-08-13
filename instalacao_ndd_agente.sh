#!/bin/bash

set -e

### === CONFIGURAÇÕES PERSONALIZÁVEIS === ###

# Tipo de comunicação: direta, proxy, gateway
COMUNICACAO="direta"

# Caminho do certificado exportado (não usado com atualização via GitHub)
CERT_ORIGEM="/caminho/para/certificado.cer"

# Configurações de proxy
PROXY_HOST="proxy.exemplo.com"
PROXY_PORT="3128"
PROXY_USER="usuario_proxy"
PROXY_PASS="senha_proxy"

# Configurações de gateway
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
    sleep 5
PS3="Digite o número da opção e pressione Enter: "
options=("Prefeitura (Administrativos)" "Escolas" "Saúde")
select setor in "${options[@]}"; do
    case $REPLY in
        1)
            SETOR="adm"
            break
            ;;
        2)
            SETOR="edu"
            break
            ;;
        3)
            SETOR="sau"
            break
            ;;
        *)
            echo "Opção inválida. Tente novamente."
            ;;
    esac
done

echo "Você escolheu o setor: $SETOR"
    sleep 5

read -p "Digite o nome do setor ou unidade onde está realizando a configuração: " UNIDADE

echo "Setor/unidade configurado: $UNIDADE"
    sleep 5

echo "Definindo hostname para ${SETOR}-${UNIDADE}..."
sudo hostnamectl set-hostname "${SETOR}-${UNIDADE}"

echo "📡 Verificando atualização de pacotes configurados..."
sudo apt-get update

echo "🚀 Iniciando instalação de pacotes disponiveis..."
sudo apt-get upgrade

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
    sleep 5
fi

echo "🔧 Ajustando sysctl.conf para aumentar limites do inotify..."

sudo sed -i '/fs.inotify.max_user_instances/d' /etc/sysctl.conf
sudo sed -i '/fs.inotify.max_user_watches/d' /etc/sysctl.conf

echo "fs.inotify.max_user_instances=8192" | sudo tee -a /etc/sysctl.conf
echo "fs.inotify.max_user_watches=524288" | sudo tee -a /etc/sysctl.conf

sudo sysctl -p

echo "✅ Ajustes no sysctl.conf aplicados com sucesso."

### === IMPORTAÇÃO E ATUALIZAÇÃO DO CERTIFICADO DO GATEWAY === ###

if [ "$COMUNICACAO" = "gateway" ]; then
    GITHUB_RAW_URL="https://raw.githubusercontent.com/andrhenrqui/Instalacao_NDD/main/instalacao_ndd_agente.sh"
    LOCAL_CERT="/usr/local/share/ca-certificates/nddgateway.crt"

    echo "📡 Verificando atualização do certificado do Gateway..."

    TMPFILE=$(mktemp)
    if ! wget -q -O "$TMPFILE" "$GITHUB_RAW_URL"; then
        echo "❌ Falha ao baixar o certificado remoto do GitHub."
        rm -f "$TMPFILE"
        exit 1
    fi

    if [ ! -f "$LOCAL_CERT" ]; then
        echo "❌ Certificado local não encontrado. Instalando novo certificado."
        sudo mv "$TMPFILE" "$LOCAL_CERT"
        sudo update-ca-certificates
    elif ! cmp -s "$TMPFILE" "$LOCAL_CERT"; then
        echo "⚠️ Certificado local diferente da versão remota. Atualizando..."
        sudo mv "$TMPFILE" "$LOCAL_CERT"
        sudo update-ca-certificates
    else
        echo "✔️ Certificado local está atualizado."
        rm "$TMPFILE"
    fi
fi

### === INSTALAÇÃO DO AGENTE NDD === ###

echo "📦 Adicionando repositório da NDD..."
sudo wget -O /usr/share/keyrings/ndd.public https://packages-orbix.ndd.tech/apt-repo/ndd.public
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/ndd.public] https://packages-orbix.ndd.tech/apt-repo/ stable main" | sudo tee /etc/apt/sources.list.d/ndd.list
sudo apt-get update -y && sudo apt-get upgrade -y

echo "📝 Prepare o arquivo auxiliar com as informações necessárias antes de prosseguir com a instalação."
echo "⏳ A instalação do agente começará em instantes ..."
for ((i=20; i>=0; i-=5)); do
    echo -ne "⏳ $i segundos restantes...\r"
    sleep 5
done
echo -e "\n🚀 Iniciando a instalação..."
sudo apt install ndd-dca-and-cloud-connector

echo "⚙️ Configurando o agente..."

echo "⏳ Aguardando preparação da configuração ..."
for i in 1 2 3 4; do
    sleep 5
    echo "✅ Etapa $i/4 concluída..."
done

echo "🔍 Verificando o status do serviço NDDPrinterMonitor..."

SERVICE_NAME="NDDPrinterMonitor"

if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "✅ O serviço $SERVICE_NAME está em execução."
else
    echo "⚠️ O serviço $SERVICE_NAME não está rodando. Tentando iniciar..."
    sudo systemctl enable "$SERVICE_NAME"
    sudo systemctl start "$SERVICE_NAME"
    
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo "✅ O serviço $SERVICE_NAME foi iniciado com sucesso."
    else
        echo "❌ Falha ao iniciar o serviço $SERVICE_NAME. Verifique manualmente com: sudo systemctl status $SERVICE_NAME"
    fi
fi

### === CRIAÇÃO DO SCRIPT DE VERIFICAÇÃO PARA EXECUÇÃO NO BOOT === ###

cat <<EOF | sudo tee /usr/local/bin/verificar_ndd.sh > /dev/null
#!/bin/bash
SERVICE="NDDPrinterMonitor"
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

### === CRIAÇÃO DO SERVIÇO SYSTEMD PARA RODAR O VERIFICADOR NO BOOT === ###

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

echo "✅ Instalação e configuração concluídas com sucesso!"

echo "📡 Hostname da máquina: $(hostname)"
IP_LOCAL=$(ip -4 addr show $(ip route get 8.8.8.8 | awk '{print $5; exit}') | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

echo "📡 IP local da máquina: $IP_LOCAL"

sudo systemctl status "$SERVICE_NAME"