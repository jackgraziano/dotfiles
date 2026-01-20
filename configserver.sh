#!/bin/bash

# Script de configuração do servidor
# Requer privilégios de root
# Uso: sudo ./configserver.sh

# sudo apt update && sudo apt install -y curl && curl -fsSL https://raw.githubusercontent.com/jackgraziano/dotfiles/refs/heads/main/configserver.sh | sudo bash

if [ "$EUID" -ne 0 ]; then
    echo "Este script precisa ser executado como root (sudo)"
    exit 1
fi

# Parâmetros configuráveis
USERNAME="sinapse"

# Solicita a senha do usuário
echo "Digite a senha para o usuário $USERNAME:"
read -s PASSWORD
echo ""
echo "Confirme a senha:"
read -s PASSWORD_CONFIRM
echo ""

if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
    echo "Erro: As senhas não coincidem!"
    exit 1
fi

if [ -z "$PASSWORD" ]; then
    echo "Erro: A senha não pode estar vazia!"
    exit 1
fi
MPICH_URL="https://www.mpich.org/static/downloads/4.2.1/mpich-4.2.1.tar.gz"

echo "Criando usuário $USERNAME..."
useradd -m -s /bin/bash "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd

echo "Usuário $USERNAME criado com sucesso!"

echo "Removendo repositórios inválidos..."
rm -f /etc/apt/sources.list.d/*griffo* /etc/apt/sources.list.d/*docker* 2>/dev/null || true

echo "Atualizando repositórios..."
apt update

echo "Instalando pacotes essenciais..."
apt install -y build-essential htop zsh gcc gfortran git wget openssh-server vim curl lm-sensors sensors-applet

echo "Configurando SSH..."
systemctl enable ssh
systemctl start ssh
ufw allow 22/tcp 2>/dev/null || true

echo "Desabilitando suspend/hibernação..."
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
# Desabilita suspend no GNOME
if command -v gsettings &> /dev/null; then
    sudo -u "$USERNAME" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u $USERNAME)/bus" gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing' 2>/dev/null || true
    sudo -u "$USERNAME" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u $USERNAME)/bus" gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing' 2>/dev/null || true
fi

echo "Instalando Docker..."
apt install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings

# Detecta a distribuição corretamente
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DOCKER_DISTRO="$ID"
else
    DOCKER_DISTRO="ubuntu"
fi

curl -fsSL https://download.docker.com/linux/${DOCKER_DISTRO}/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${DOCKER_DISTRO} $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "Configurando Docker..."
systemctl enable docker
systemctl start docker
usermod -aG docker "$USERNAME"

echo "Instalando Tailscale..."
curl -fsSL https://pkgs.tailscale.com/stable/${DOCKER_DISTRO}/$(lsb_release -sc).noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
curl -fsSL https://pkgs.tailscale.com/stable/${DOCKER_DISTRO}/$(lsb_release -sc).tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list
apt update
apt install -y tailscale
systemctl enable tailscaled
systemctl start tailscaled

echo "Instalando ferramentas adicionais..."
# Tenta adicionar repositório griffo.io, mas continua mesmo se falhar
if curl -sS https://debian.griffo.io/EA0F721D231FDD3A0A17B9AC7808B4DD62C41256.asc | gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/debian.griffo.io.gpg 2>/dev/null; then
    echo "deb https://debian.griffo.io/apt $(lsb_release -sc 2>/dev/null) main" | tee /etc/apt/sources.list.d/debian.griffo.io.list
    apt update
    # Instala pacotes disponíveis, ignora os que falharem
    apt install -y zig ghostty lazygit yazi eza uv fzf zoxide bun tigerbeetle 2>/dev/null || true
else
    echo "Aviso: Repositório griffo.io não disponível, pulando instalação de algumas ferramentas..."
fi

echo "Configurando zsh como shell padrão..."
chsh -s /bin/zsh "$USERNAME"

echo "Instalando oh-my-zsh..."
su - "$USERNAME" -c "sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\" \"\" --unattended"

echo "Configurando .zshrc..."
if [ -f /home/"$USERNAME"/.zshrc ]; then
    sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="agnoster"/' /home/"$USERNAME"/.zshrc
    echo "export TERM=xterm-256color" >> /home/"$USERNAME"/.zshrc
else
    echo "Erro: .zshrc não foi criado. Instalação do oh-my-zsh falhou."
fi

echo "Baixando MPICH..."
su - "$USERNAME" -c "wget -P /home/$USERNAME \"$MPICH_URL\""

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
echo ""
echo "Depois execute:"
echo "  cat ~/.ssh/id_ed25519.pub"
echo ""
echo "---------------------------------------------------"
echo ""
echo "Por favor, adicione esta chave ao GitHub antes de continuar."
echo "Pressione ENTER quando estiver pronto..."
read < /dev/tty

echo "Adicionando GitHub aos known_hosts..."
sudo -u "$USERNAME" ssh-keyscan github.com >> /home/"$USERNAME"/.ssh/known_hosts 2>/dev/null

echo "Clonando repositório server_kit..."
sudo -u "$USERNAME" git clone --recursive git@github.com:easywave-energy/server_kit.git /home/"$USERNAME"/server_kit

echo "Configurando permissões de execução..."
chmod +x /home/"$USERNAME"/server_kit/bin/*

echo "Desabilitando Hyper-Threading permanentemente..."
if [ -f /sys/devices/system/cpu/smt/control ]; then
    echo off > /sys/devices/system/cpu/smt/control
else
    echo "Aviso: Sistema não suporta controle de SMT/Hyper-Threading"
fi

# Torna a desabilitação do Hyper-Threading permanente
cat > /etc/systemd/system/disable-smt.service << 'EOF'
[Unit]
Description=Disable SMT/Hyper-Threading
DefaultDependencies=no
After=sysinit.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo off > /sys/devices/system/cpu/smt/control'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl enable disable-smt.service

echo "Instalação concluída!"
