set -x
set -e

sudo dnf update -y
sudo dnf install -y git vim ansible-core libselinux-python3
ansible-galaxy collection install ansible.posix community.general community.crypto

if [ ! -f $HOME/.ssh/id_rsa ]; then
  ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa
fi

if [ ! -d $HOME/ansible-role-dlrn ]; then
  git clone https://github.com/rdo-infra/ansible-role-dlrn.git $HOME/ansible-role-dlrn
fi

if [ ! -d $HOME/sf-infra ]; then
  git clone https://github.com/softwarefactory-project/sf-infra $HOME/sf-infra
fi

echo "Bootstrap OK"
echo "Run: ansible-playbook playbook.yaml"
