#!/bin/bash
set -e

### === VERIFICAÇÃO DO SISTEMA === ###
echo "🔍 Verificando versão do sistema..."

# Obtém o nome e a versão da distro
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$NAME
    VERSAO=$VERSION_ID
else
    echo "❌ Não foi possível identificar o sistema operacional."
    exit 1
fi

echo "📦 Sistema detectado: $DISTRO $VERSAO"

# Converte versão em número inteiro simples para comparação
# (ex: "20.04" vira "2004")
NUMERO_VERSAO=$(echo "$VERSAO" | tr -d '.')

# Verifica compatibilidade conforme distro
case "$DISTRO" in
    "Ubuntu"*)
        if (( NUMERO_VERSAO < 2004 )); then
            echo "⚠️ Requer Ubuntu 20.04 ou superior (x64)."
            exit 1
        fi
        ;;
    "Debian"*)
        if (( NUMERO_VERSAO < 12 )); then
            echo "⚠️ Requer Debian 12 ou superior (x64)."
            exit 1
        fi
        ;;
    "Fedora"*)
        if (( NUMERO_VERSAO < 38 )); then
            echo "⚠️ Requer Fedora 38 ou superior (x64)."
            exit 1
        fi
        ;;
    "Linux Mint"*)
        if (( NUMERO_VERSAO < 22 )); then
            echo "⚠️ Requer Linux Mint 22 ou superior (x64)."
            exit 1
        fi
        ;;
    *)
        echo "⚠️ Distribuição não suportada: $DISTRO"
        echo "Compatíveis: Ubuntu 20.04+, Debian 12+, Fedora 38+, Mint 22+"
        exit 1
        ;;
esac

# Confirma arquitetura
ARQUITETURA=$(uname -m)
if [[ "$ARQUITETURA" != "x86_64" ]]; then
    echo "⚠️ Requer sistema 64 bits (x64). Arquitetura detectada: $ARQUITETURA"
    exit 1
fi

echo "✅ Sistema compatível. Prosseguindo com a instalação..."
echo

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

echo "🔍 Verificando informações do sistema..."
CURRENT_HOSTNAME=$(hostname)
echo "📡 Hostname atual: $CURRENT_HOSTNAME"

read -p "Deseja alterar o hostname? (s/N): " RESP

if [[ "$RESP" =~ ^[Ss]$ ]]; then
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

    NEW_HOSTNAME="${SETOR}-${UNIDADE}"
    echo "Definindo hostname para ${NEW_HOSTNAME}..."
    sudo hostnamectl set-hostname "$NEW_HOSTNAME"
    echo "✅ Hostname alterado para: $(hostname)"
else
    echo "➡️ Mantendo hostname: $CURRENT_HOSTNAME"
fi

### === ATUALIZAÇÃO DE PACOTES COM TRATAMENTO DE ERROS === ###
echo "📡 Verificando atualização de pacotes configurados..."
sudo systemctl stop cups-browsed.service
sudo systemctl disable cups-browsed.service
sudo dpkg --configure -a
sudo apt-get install net-tools -y
sudo systemctl restart cups
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
    sudo wget -O /usr/share/keyrings/ndd.public packages-orbix.ndd.tech/apt-repo/ndd.public
else
    echo "ℹ️ Chave pública da NDD já existente. Pulando download."
fi

echo "📦 Configurando repositório da NDD..."
if [ ! -f /etc/apt/sources.list.d/ndd.list ]; then
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/ndd.public] https://packages-orbix.ndd.tech/apt-repo/  stable main" | sudo tee /etc/apt/sources.list.d/ndd.list
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

### === REMOÇÃO DO ARQUIVO SingletonLock DE NAVEGADORES BASEADOS NO CHROME === ###
echo "🧹 Verificando arquivos de bloqueio (SingletonLock) de navegadores baseados no Chrome..."

# Lista de diretórios de configuração possíveis
BROWSERS=(
    "$HOME/.config/google-chrome"
    "$HOME/.config/chromium"
)

for DIR in "${BROWSERS[@]}"; do
    LOCK_FILE="$DIR/SingletonLock"
    if [ -f "$LOCK_FILE" ]; then
        echo "⚠️ Arquivo SingletonLock encontrado em: $LOCK_FILE"
        echo "🗑️ Removendo arquivo de bloqueio..."
        rm -f "$LOCK_FILE"
        if [ ! -f "$LOCK_FILE" ]; then
            echo "✅ Arquivo SingletonLock removido com sucesso de: $DIR"
        else
            echo "❌ Falha ao remover o arquivo SingletonLock em: $DIR"
        fi
    else
        echo "ℹ️ Nenhum arquivo SingletonLock encontrado em: $DIR"
    fi
done

echo "✅ Verificação de arquivos SingletonLock concluída."

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

### === HOSTNAME, IP, MÁSCARA E GATEWAY === ###
echo "📡 Hostname da máquina: $(hostname)"

# Detecta interface ativa automaticamente
INTERFACE=$(ip route get 8.8.8.8 | awk '{print $5; exit}')

# Captura IP e máscara CIDR
IP_INFO=$(ip -4 addr show "$INTERFACE" | grep -oP 'inet\s+\K[\d./]+')
IP_LOCAL=${IP_INFO%/*}
CIDR_MASK=${IP_INFO#*/}

# Obtém máscara decimal usando ipcalc
if ! command -v ipcalc &> /dev/null; then
    echo "📦 Instalando utilitário ipcalc para cálculo de máscara..."
    sudo apt-get install ipcalc -y >/dev/null 2>&1
fi

DEC_MASK=$(ipcalc "$IP_LOCAL/$CIDR_MASK" | grep -oP 'Netmask:\s+\K[\d.]+')

# Obtém o gateway padrão
GATEWAY=$(ip route | grep default | awk '{print $3}')

echo "📡 Interface ativa: $INTERFACE"
echo "📡 IP local da máquina: $IP_LOCAL"
echo "📡 Máscara CIDR: /$CIDR_MASK"
echo "📡 Máscara decimal: $DEC_MASK"
echo "🚪 Gateway padrão: $GATEWAY"

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