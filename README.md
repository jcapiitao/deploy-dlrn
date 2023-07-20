# poc-dlrn-deps

## Installer
Run the commands below on a F37+ system
``` bash
cd ~/poc-dlrn-deps/installer
./bootstrap.sh

# Then copy/paste pubkey to the DLRN server
cat ~/.ssh/id_rsa.pub

# Test connection to DLRN server
ansible -i hosts.yaml all -m ping

# Run the playbook
ansible-playbook playbook.yaml
```
