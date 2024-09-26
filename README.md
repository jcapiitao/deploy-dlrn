# deploy-dlrn

## Installer
Run the commands below on a F37+ system
``` bash
cd ./installer
./bootstrap.sh

# Then copy/paste pubkey to the DLRN server
cat ~/.ssh/id_rsa.pub

# Test connection to DLRN server
ansible -i hosts.yaml all -m ping

# Run the playbook
ansible-playbook playbook.yaml
ansible-playbook -l cs10 playbook.yaml
```
