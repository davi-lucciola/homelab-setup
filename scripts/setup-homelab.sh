#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Setup Idempotente de Segurança e Docker para Homelab
# Testado em: Debian / Ubuntu
# ==============================================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}==> Iniciando configuração idempotente do servidor...${NC}"

# 1. Atualizar lista de pacotes
echo -e "${BLUE}==> Atualizando pacotes do sistema...${NC}"
sudo apt-get update -y

# 2. Instalar dependências essenciais
echo -e "${BLUE}==> Instalando dependências base...${NC}"
sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    ufw

# ==============================================================================
# 3. Configuração do Firewall (UFW)
# ==============================================================================
echo -e "${BLUE}==> Configurando o Firewall (UFW)...${NC}"

# Define regras padrão de forma idempotente
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Libera portas necessárias (UFW ignora se a regra já existir)
sudo ufw allow 22/tcp comment 'SSH'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'

# Ativa o UFW de forma não interativa se não estiver ativo
if ! sudo ufw status | grep -q "Status: active"; then
    echo -e "${GREEN}Ativando o UFW...${NC}"
    sudo ufw --force enable
else
    echo "UFW já está ativo."
fi

# ==============================================================================
# 4. Instalação Idempotente do Docker (Repositório Oficial)
# ==============================================================================
echo -e "${BLUE}==> Verificando/Instalando Docker Engine e Docker Compose...${NC}"

if ! command -v docker &> /dev/null; then
    echo -e "${GREEN}Docker não encontrado. Instalando via repositório oficial...${NC}"

    # Cria diretório de chaves GPG com permissões estritas (padrão recente)
    sudo install -m 0755 -d /etc/apt/keyrings

    # Baixa e configura a chave GPG oficial do Docker se ainda não existir
    if [ ! -f /etc/apt/keyrings/docker.asc ]; then
        sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
        sudo chmod a+r /etc/apt/keyrings/docker.asc
    fi

    # Adiciona o repositório oficial do Docker às fontes do APT
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Atualiza repositórios e instala os pacotes oficiais do Docker Engine
    sudo apt-get update -y
    sudo apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin
else
    echo "Docker já está instalado ($(docker --version))."
fi

# ==============================================================================
# 5. Pós-instalação do Docker (Execução sem sudo)
# ==============================================================================
echo -e "${BLUE}==> Configurando permissões do Docker para o usuário '$USER'...${NC}"

# Garante a existência do grupo docker
if ! getent group docker > /dev/null; then
    sudo groupadd docker
fi

# Adiciona o usuário atual ao grupo docker de forma idempotente
if ! groups "$USER" | grep &>/dev/null '\bdocker\b'; then
    echo -e "${GREEN}Adicionando $USER ao grupo docker...${NC}"
    sudo usermod -aG docker "$USER"
    echo -e "${GREEN}Nota: Pode ser necessário fazer logoff e login novamente para aplicar as permissões.${NC}"
else
    echo "Usuário '$USER' já pertence ao grupo docker."
fi

# Garante que os serviços do Docker iniciam com o sistema
sudo systemctl enable docker
sudo systemctl start docker

echo -e "${BLUE}==> Verificando rede Docker 'proxy'...${NC}"

if ! sudo docker network ls --format '{{.Name}}' | grep -q "^proxy$"; then
    echo -e "${GREEN}Criando rede Docker 'proxy'...${NC}"
    sudo docker network create proxy
else
    echo "Rede 'proxy' já existe."
fi

echo -e "${GREEN}======================================================================${NC}"
echo -e "${GREEN} Configuração concluída com sucesso! ${NC}"
echo -e "${GREEN}======================================================================${NC}"
