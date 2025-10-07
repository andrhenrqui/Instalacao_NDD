#!/bin/bash
set -e

echo "🧹 Iniciando limpeza automática dos pacotes NDD..."

# Localiza todos os pacotes relacionados à NDD
PACOTES=$(dpkg -l | grep ndd | awk '{print $3}')

if [ -z "$PACOTES" ]; then
    echo "✅ Nenhum pacote NDD encontrado no sistema."
    exit 0
fi

echo "📦 Pacotes encontrados:"
echo "$PACOTES"
echo

read -p "Deseja remover TODOS esses pacotes? (s/N): " RESP
if [[ ! "$RESP" =~ ^[Ss]$ ]]; then
    echo "❌ Operação cancelada."
    exit 1
fi

# Remove scripts quebrados do dpkg
echo "🚫 Removendo scripts defeituosos..."

sudo apt autoclean
sudo apt clean

# Força remoção dos pacotes
echo "⚙️  Removendo pacotes NDD..."
sudo rm -f /var/lib/dpkg/info/ndd-dca-and-cloud-connector.*
sudo rm -f /var/lib/dpkg/info/ndd-dca-printer-network-agent.*

sudo dpkg --purge --force-all ndd-dca-and-cloud-connector
sudo dpkg --purge --force-all ndd-dca-printer-network-agent
sudo dpkg --purge --force-all ndd-dca-printer-monitor-usb-agent

# Corrige dependências quebradas
echo "🔧 Reconfigurando pacotes..."
sudo apt-get install -f -y
sudo dpkg --configure -a

# Limpeza final
echo "🧽 Limpando cache e dependências..."
sudo apt-get clean
sudo apt-get autoremove -y

echo
echo "📋 Verificando se restou algo:"
dpkg -l | grep ndd || echo "✅ Nenhum pacote NDD encontrado."

echo
echo "🎯 Limpeza completa concluída!"
