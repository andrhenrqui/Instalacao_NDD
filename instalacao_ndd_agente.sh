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
    sleep 5
    sudo apt-get update --fix-missing || { echo "❌ Falha ao atualizar pacotes."; exit 1; }
fi

echo "🚀 Iniciando instalação de pacotes disponíveis..."
if ! sudo apt-get upgrade -y; then
    echo "⚠️ Erro durante o upgrade. Tentando corrigir dependências..."
    sleep 5
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
sudo sed -i '/fs.inotify.max_user_instances/d' /etc/sysctl.conf || true
sudo sed -i '/fs.inotify.max_user_watches/d' /etc/sysctl.conf || true
echo "fs.inotify.max_user_instances=8192" | sudo tee -a /etc/sysctl.conf
echo "fs.inotify.max_user_watches=524288" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p || true
echo "✅ Ajustes no sysctl.conf aplicados com sucesso."

### === REPOSITÓRIO NDD === ###
echo "🔑 Importando chave pública da NDD..."
if [ ! -f /usr/share/keyrings/ndd.public ]; then
    wget -qO - https://packages-orbix.ndd.tech/apt-repo/ndd.gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/ndd.public
else
    echo "ℹ️ Chave pública da NDD já existente. Pulando download."
fi

echo "📦 Configurando repositório da NDD..."
if [ ! -f /etc/apt/sources.list.d/ndd.list ]; then
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/ndd.public] https://packages-orbix.ndd.tech/apt-repo/ stable main" | sudo tee /etc/apt/sources.list.d/ndd.list
else
    echo "ℹ️ Repositório da NDD já configurado. Pulando criação do arquivo."
fi

echo "🔄 Atualizando pacotes após adicionar repositório da NDD..."
if ! sudo apt-get update -y; then
    echo "⚠️ Erro ao atualizar pacotes do repositório da NDD. Tentando novamente com --fix-missing..."
    sleep 5
    sudo apt-get update --fix-missing -y || { echo "❌ Falha ao atualizar pacotes da NDD."; exit 1; }
fi

### === INSTALAÇÃO DO AGENTE NDD === ###
echo -e "\n🚀 Iniciando a instalação do agente NDD..."
if ! sudo apt install ndd-dca-and-cloud-connector; then
    echo "⚠️ Erro durante a instalação do agente. Tentando corrigir problemas..."
    sleep 5
    sudo apt-get install -f -y
    sudo apt-get autoremove -y
    sudo apt-get autoclean -y
    echo "🔄 Tentando novamente a instalação..."
    sleep 5
    if ! sudo apt install ndd-dca-and-cloud-connector --fix-missing; then
        echo "❌ Não foi possível concluir a instalação do agente NDD mesmo após as correções."
        exit 1
    fi
fi
echo "✅ Agente NDD instalado com sucesso!"

# Lista de serviços que devem estar rodando
SERVICOS=(
    "NDDDCAandCloudConnector.service"
    "NDDPrinterUsbMonitor.service"
    "NDDPrinterMonitor.service"
)

for SERVICE_NAME in "${SERVICOS[@]}"; do
    echo -e "\n🔍 Garantindo que o serviço $SERVICE_NAME esteja habilitado..."
    sudo systemctl enable "$SERVICE_NAME"

    echo "🔍 Verificando o status do serviço $SERVICE_NAME..."
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo "✅ O serviço $SERVICE_NAME já está em execução."
    else
        echo "⚠️ O serviço $SERVICE_NAME não está rodando. Tentando iniciar..."
        sleep 5
        sudo systemctl start "$SERVICE_NAME"

        if systemctl is-active --quiet "$SERVICE_NAME"; then
            echo "✅ O serviço $SERVICE_NAME foi iniciado com sucesso."
        else
            echo "❌ Falha ao iniciar o serviço $SERVICE_NAME."
            echo "   ➡️ Verifique manualmente com: sudo systemctl status $SERVICE_NAME"
            sleep 5
        fi
    fi
done


### === CRIAÇÃO DO SCRIPT DE VERIFICAÇÃO DE MÚLTIPLOS SERVIÇOS COM RESUMO === ###
cat <<'EOF' | sudo tee /usr/local/bin/verificar_ndd.sh > /dev/null
#!/bin/bash

SERVICOS=(
    "NDDDCAandCloudConnector.service"
    "NDDPrinterUsbMonitor.service"
    "NDDPrinterMonitor.service"
)

echo "🔍 Iniciando verificação dos serviços NDD..."

for SERVICE in "${SERVICOS[@]}"; do
    if systemctl is-active --quiet "$SERVICE"; then
        STATUS="ativo ✅"
    else
        echo "⚠️ O serviço $SERVICE não está rodando. Tentando iniciar e habilitar no boot..."
        sudo systemctl enable "$SERVICE"
        sudo systemctl start "$SERVICE"
        if systemctl is-active --quiet "$SERVICE"; then
            STATUS="iniciado e habilitado ✅"
        else
            STATUS="falha ❌"
        fi
    fi
    echo "• $SERVICE → $STATUS"
done

echo "🔹 Resumo final da verificação concluída!"
EOF

sudo chmod +x /usr/local/bin/verificar_ndd.sh

### === CRIAÇÃO DO SERVIÇO SYSTEMD PARA RODAR NO BOOT === ###
cat <<EOF | sudo tee /etc/systemd/system/verificar-ndd.service > /dev/null
[Unit]
Description=Verifica os serviços NDD no boot
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

### === HOSTNAME, IP E STATUS DOS SERVIÇOS === ###
echo "📡 Hostname da máquina: $(hostname)"
IP_LOCAL=$(ip -4 addr show $(ip route get 8.8.8.8 | awk '{print $5; exit}') | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
echo "📡 IP local da máquina: $IP_LOCAL"

echo -e "\n🔍 Resumo do status dos serviços NDD..."

for SERVICE_NAME in "${SERVICOS[@]}"; do
    # Verifica se está habilitado
    if systemctl is-enabled --quiet "$SERVICE_NAME"; then
        STATUS_ENABLED="habilitado"
    else
        STATUS_ENABLED="❌ desabilitado"
    fi

    # Verifica se está ativo
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        STATUS_ACTIVE="em execução"
    else
        STATUS_ACTIVE="❌ parado"
    fi

    echo "🔹 $SERVICE_NAME → $STATUS_ENABLED / $STATUS_ACTIVE"
done

echo -e "\n✅ Instalação e configuração concluídas com sucesso!"
