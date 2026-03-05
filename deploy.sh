#!/bin/bash
set -e

exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

SCRIPT_URL="https://raw.githubusercontent.com/jhenderson-tamu/ISTM_622_Module2/cab49aea9748396a8cc98ccfa32a7e2b8ac75e4b/Module2_GoodScript.bash"

curl -fsSL "$SCRIPT_URL" -o /root/deploy.sh

# Convert Windows line endings to Linux
sed -i 's/\r$//' /root/deploy.sh

chmod +x /root/deploy.sh

bash /root/deploy.sh
