#!/bin/bash

source /home/joinmarket/joinin.conf
source /home/joinmarket/_functions.sh

function installBitcoinScripts {
  if [ ! -d "/home/bitcoin/bitcoin-scripts" ];then
    cd /home/bitcoin/ || exit 1
    sudo -u bitcoin git clone https://github.com/kristapsk/bitcoin-scripts.git
    cd bitcoin-scripts || exit 1
    # from https://github.com/kristapsk/bitcoin-scripts/commits/master
    sudo -u bitcoin git checkout 45642787d2f9a0ca4d3fd1b22b86863de83d8707
    sudo -u bitcoin chmod +x *.sh
  fi
}

function installBoltzmann {
  if [ ! -f "/home/joinmarket/boltzmann/bvenv/bin/activate" ] ; then
    cd /home/joinmarket/ || exit 1
    git clone https://code.samourai.io/oxt/boltzmann.git
    cd boltzmann || exit 1
    python3 -m venv bvenv
    source bvenv/bin/activate || exit 1
    python setup.py install
  fi
}

function dialog_inputbox {
  local title=$1
  local text=$2
  local height=$3
  local width=$4
  inputdata=$(mktemp -p /dev/shm/)
  dialog --backtitle "$title" \
  --title "$title" \
  --inputbox "
  $text" $height $width 2> "$inputdata"
  openMenuIfCancelled $?
  dialog_output=$(cat $inputdata)
}

function getQRstring {
  QRstring=$(mktemp -p /dev/shm/)
  dialog --backtitle "Display a QR code from any text" \
  --title "Enter any text" \
  --inputbox "
  Enter the text to be shown as a QR code" 9 71 2> "$QRstring"
  openMenuIfCancelled $?
}

isLocalBitcoinCLI=$(sudo -u bitcoin bitcoin-cli -version|grep -c "Bitcoin Core RPC client")

# BASIC MENU INFO
HEIGHT=11
WIDTH=55
CHOICE_HEIGHT=5
TITLE="Tools"
MENU=""
OPTIONS=()
BACKTITLE="JoininBox GUI"

# Basic Options
if [ "${runningEnv}" = standalone ]; then
  OPTIONS+=(
    SPECTER "Specter Desktop options")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi
OPTIONS+=(
    QR "Display a QR code from any text"
    CUSTOMRPC "Run a custom bitcoin RPC with curl"
    SCANJM "Scan blocks for JoinMarket coinjoins")
if [ $isLocalBitcoinCLI -gt 0 ];then    
  OPTIONS+=(
    CHECKTXN "CLI transaction explorer")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi    
  OPTIONS+=(
    BOLTZMANN "Analyze the entropy of a transaction")
if [ "${runningEnv}" != mynode ]; then
  OPTIONS+=(
    PASSWORD "Change the ssh password")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi
OPTIONS+=(
    LOGS "Show the bitcoind logs on $network")

CHOICE=$(dialog \
          --clear \
          --backtitle "$BACKTITLE" \
          --title "$TITLE" \
          --ok-label "Select" \
          --cancel-label "Back" \
          --menu "$MENU" \
            $HEIGHT $WIDTH $CHOICE_HEIGHT \
            "${OPTIONS[@]}" \
            2>&1 >/dev/tty)

case $CHOICE in
  QR)
    getQRstring
    datastring=$(cat $QRstring)
    clear
    echo
    echo "Displaying the text:"
    echo "$datastring"
    echo
    if [ ${#datastring} -eq 0 ]; then
      echo "# Error='missing string'"
    fi
    qrencode -t ANSIUTF8 "${datastring}"
    echo "(To shrink QR code: MacOS press CMD- / Linux press CTRL-)"
    echo            
    echo "Press ENTER to return to the menu..."
    read key;;
  CUSTOMRPC)
    echo "***DANGER ZONE***"
    echo "# See the options at https://developer.bitcoin.org/reference/rpc/"
    echo
    echo "# Input which method (command) to use"
    read method
    echo "# Input the parameter(s) (optional)"
    read params
    customRPC "# custom RPC" "$method" "$params" 
    echo            
    echo "Press ENTER to return to the menu..."
    read key;;
  SPECTER)
    /home/joinmarket/standalone/menu.specter.sh;;
  PASSWORD)
    sudo /home/joinmarket/set.password.sh;;
  LOGS)
    showBitcoinLogs;;
  CHECKTXN)
    dialog_inputbox "CLI transaction explorer" "\nUsing: https://github.com/kristapsk/bitcoin-scripts\n\nPaste a TXID to check" 11 71
    clear
    installBitcoinScripts
    getRPC
    echo "Running the command:"
    echo "sudo -u bitcoin /home/bitcoin/bitcoin-scripts/checktransaction.sh -rpcwallet=$rpc_wallet $dialog_output"
    sudo -u bitcoin /home/bitcoin/bitcoin-scripts/checktransaction.sh -rpcwallet=$rpc_wallet $dialog_output
    echo            
    echo "Press ENTER to return to the menu..."
    read key;;
  BOLTZMANN)
    dialog_inputbox "Boltzmann transaction entropy analyses" "\nUsing: https://code.samourai.io/oxt/boltzmann\n\nPaste a TXID to analyze" 11 71
    clear
    installBoltzmann
    python /home/joinmarket/start.boltzmann.py --txid=$dialog_output
    echo            
    echo "Press ENTER to return to the menu..."
    read key;;
  SCANJM)
    BLOCKHEIGHT=$(customRPC "" "getblockchaininfo" ""\
                  |grep blocks|awk '{print $2}'|cut -d, -f1)
    dialog_inputbox "snicker-finder.py" \
    "\nUsing: https://github.com/JoinMarket-Org/joinmarket-clientserver/blob/\
master/scripts/snicker/snicker-finder.py\n\n\
Note that scanning the blocks is slow.\n\
Current blockheight is: $BLOCKHEIGHT\n\
Input how many previous blocks from the tip you want to scan" 14 108
    clear
    echo
    echo "Running the command:"
    echo "python snicker/snicker-finder.py -j $((BLOCKHEIGHT - dialog_output)) \
-f /home/joinmarket/.joinmarket/candidates.txt"
    echo
    python /home/joinmarket/joinmarket-clientserver/scripts/snicker/snicker-finder.py\
    -j $((BLOCKHEIGHT - dialog_output)) -f /home/joinmarket/.joinmarket/candidates.txt
    echo
    echo "The transaction details are saved in /home/joinmarket/.joinmarket/candidates.txt"
    echo "To display the file in the terminal use:"
    echo "'cat /home/joinmarket/.joinmarket/candidates.txt'"
    echo "or menu -> TOOLS -> CHECKTXN for a CLI transaction explorer"
    echo
    echo "Press ENTER to return to the menu..."
    read key;;  
esac