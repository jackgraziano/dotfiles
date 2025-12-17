#!/bin/bash

# Script de configuração do servidor
# Requer privilégios de root
# Uso: sudo ./configserver.sh [username] [password]

# curl -fsSL https://raw.githubusercontent.com/jackgraziano/dotfiles/refs/heads/main/configserver.sh | sudo bash

if [ "$EUID" -ne 0 ]; then
    echo "Este script precisa ser executado como root (sudo)"
    exit 1
fi

# Parâmetros configuráveis
USERNAME=${1:-myria-user}
PASSWORD=${2:-myria}
MPICH_URL="https://www.mpich.org/static/downloads/4.2.1/mpich-4.2.1.tar.gz"

echo "Criando usuário $USERNAME..."
useradd -m -s /bin/bash "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd

echo "Usuário $USERNAME criado com sucesso!"

echo "Atualizando repositórios..."
apt update

echo "Instalando pacotes essenciais..."
apt install -y build-essential htop zsh gcc gfortran git wget openssh-server

echo "Configurando SSH..."
systemctl enable ssh
systemctl start ssh
ufw allow 22/tcp 2>/dev/null || true

echo "Instalando Docker..."
apt install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "Configurando Docker..."
systemctl enable docker
systemctl start docker
usermod -aG docker "$USERNAME"

echo "Configurando zsh como shell padrão..."
chsh -s /bin/zsh "$USERNAME"

echo "Instalando oh-my-zsh..."
sudo -u "$USERNAME" sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

echo "Configurando .zshrc..."
sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="agnoster"/' /home/"$USERNAME"/.zshrc
echo "export TERM=xterm-256color" >> /home/"$USERNAME"/.zshrc

echo "Baixando MPICH..."
sudo -u "$USERNAME" wget -P /home/"$USERNAME" "$MPICH_URL"

echo "Descompactando MPICH..."
MPICH_FILE=$(basename "$MPICH_URL")
MPICH_DIR=$(basename "$MPICH_FILE" .tar.gz)
sudo -u "$USERNAME" tar xfz /home/"$USERNAME"/"$MPICH_FILE" -C /home/"$USERNAME"

echo "MPICH descompactado em: /home/$USERNAME/$MPICH_DIR"

echo "Criando diretórios para instalação do MPICH..."
sudo -u "$USERNAME" mkdir -p /home/"$USERNAME"/"$MPICH_DIR"-install
mkdir -p /tmp/"$MPICH_DIR"
cd /tmp/"$MPICH_DIR"

echo "Configurando MPICH..."
/home/"$USERNAME"/"$MPICH_DIR"/configure --prefix=/home/"$USERNAME"/"$MPICH_DIR"-install --with-device=ch3:nemesis

echo "Compilando MPICH..."
make -j"$(nproc)"

echo "Instalando MPICH..."
make install

echo "Configurando PATH para MPICH..."
echo "export PATH=/home/$USERNAME/$MPICH_DIR-install/bin:\$PATH" >> /home/"$USERNAME"/.zshrc
sudo -u "$USERNAME" bash -c "source /home/$USERNAME/.zshrc"

echo "Gerando chave SSH..."
sudo -u "$USERNAME" mkdir -p /home/"$USERNAME"/.ssh
sudo -u "$USERNAME" ssh-keygen -t ed25519 -N "" -f /home/"$USERNAME"/.ssh/id_ed25519

echo ""
echo "==================================================="
echo "Chave SSH criada com sucesso!"
echo "==================================================="
echo ""
echo "Chave pública:"
cat /home/"$USERNAME"/.ssh/id_ed25519.pub
echo ""
echo "---------------------------------------------------"
echo "Para copiar a chave de outra máquina, conecte via SSH:"
echo ""
SERVER_IP=$(hostname -I | awk '{print $1}')
echo "  ssh $USERNAME@$SERVER_IP"
echo "  Senha: $PASSWORD"
echo ""
echo "Depois execute:"
echo "  cat ~/.ssh/id_ed25519.pub"
echo ""
echo "---------------------------------------------------"
echo ""
echo "Por favor, adicione esta chave ao GitHub antes de continuar."
echo "Pressione ENTER quando estiver pronto..."
read

echo "Clonando repositório server_kit..."
sudo -u "$USERNAME" git clone --recursive git@github.com:easywave-energy/server_kit.git /home/"$USERNAME"/server_kit

echo "Configurando permissões de execução..."
chmod +x /home/"$USERNAME"/server_kit/bin/*

echo "Instalação concluída!"
