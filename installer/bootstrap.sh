set -x
set -e

sudo dnf update -y
sudo dnf install -y git vim ansible-core libselinux-python3
ansible-galaxy collection install ansible.posix community.general community.crypto

#if [ ! -f $HOME/.ssh/id_rsa ]; then
#  ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa
#fi

rm -rf $HOME/ansible-role-dlrn
git clone https://github.com/rdo-infra/ansible-role-dlrn.git ./ansible-role-dlrn

if [ ! -d $HOME/sf-infra ]; then
  git clone https://github.com/softwarefactory-project/sf-infra ./sf-infra
fi

echo "Bootstrap OK"
echo "Run: ansible-playbook playbook.yaml"
