#!/usr/bin/env bash
# Set up a Exocore service to join the Exocore Release testnet.
# Load environment variables from .env file
if [ -f .env ]; then
  export "$(cat .env | xargs)"
fi

# Configuration
# You can have these values set in .env file, and run 'source .env' before running this script.
# ***
NODE_HOME=${NODE_HOME:-$HOME/.exocored}
NODE_MONIKER=${NODE_MONIKER:-release-testnet}
STATE_SYNC=${STATE_SYNC:-true}
STATE_SYNC=$(echo "$STATE_SYNC" | tr '[:upper:]' '[:lower:]')

if [ "$STATE_SYNC" = "true" ]; then
  STATE_SYNC=true
else
  STATE_SYNC=false
fi

# Exocore configuration
# Default values for Exocore testnet
SERVICE_NAME=exocore
EXOCORE_VERSION=1.0.5
# Determine OS and architecture
OS=$(uname -s)
ARCH=$(uname -m)
if [ "$ARCH" == "x86_64" ]; then
  ARCH="amd64"
fi
if [ "$ARCH" == "aarch64" ]; then
  ARCH="arm64"
fi
CHAIN_BINARY_URL=https://github.com/ExocoreNetwork/exocore/releases/download/v$EXOCORE_VERSION/exocore_$EXOCORE_VERSION\_${OS}_${ARCH}.tar.gz
GAS_PRICE=0.0001hua
# ***

CHAIN_BINARY='exocored'
CHAIN_ID=exocoretestnet_233-6
GENESIS_URL=https://github.com/ExocoreNetwork/testnets/raw/main/genesis/$CHAIN_ID.json
SEEDS="5dfa2ddc4ce3535ef98470ffe108e6e12edd1955@seed2t.exocore-restaking.com:26656,4cc9c970fe52be4568942693ecfc2ee2cdb63d44@seed1t.exocore-restaking.com:26656"
SYNC_RPC_1=http://seed1t.exocore-restaking.com:26657
SYNC_RPC_2=http://seed2t.exocore-restaking.com:26657
SYNC_RPC_SERVERS="$SYNC_RPC_1,$SYNC_RPC_2"

# Install wget and jq
sudo apt-get install curl jq wget -y
mkdir -p $HOME/go/bin
export PATH=$PATH:$HOME/go/bin

# Install Exocore binary
echo "Installing Exocore..."

# Download Linux amd64,
wget $CHAIN_BINARY_URL || { echo "Failed to download binary"; exit 1; }
tar -xvf exocore_$EXOCORE_VERSION\_${OS}_${ARCH}.tar.gz || { echo "Failed to extract binary"; exit 1; }
cp bin/$CHAIN_BINARY $HOME/go/bin/$CHAIN_BINARY
chmod +x $HOME/go/bin/$CHAIN_BINARY

# Initialize home directory
echo "Initializing $NODE_HOME..."
rm -rf $NODE_HOME
$HOME/go/bin/$CHAIN_BINARY config chain-id $CHAIN_ID --home $NODE_HOME
$HOME/go/bin/$CHAIN_BINARY config keyring-backend test --home $NODE_HOME
$HOME/go/bin/$CHAIN_BINARY init $NODE_MONIKER --chain-id $CHAIN_ID --home $NODE_HOME
sed -i -e "/minimum-gas-prices =/ s^= .*^= \"$GAS_PRICE\"^" $NODE_HOME/config/app.toml
sed -i -e "/seeds =/ s^= .*^= \"$SEEDS\"^" $NODE_HOME/config/config.toml

if $STATE_SYNC; then
    echo "Configuring state sync..."
    CURRENT_BLOCK=$(curl -s $SYNC_RPC_1/block | jq -r '.result.block.header.height') || { echo "Failed to fetch current block"; exit 1; }
    TRUST_HEIGHT=$(($CURRENT_BLOCK - 1000))
    TRUST_BLOCK=$(curl -s $SYNC_RPC_1/block\?height\=$TRUST_HEIGHT) || { echo "Failed to fetch trust block"; exit 1; }
    TRUST_HASH=$(echo $TRUST_BLOCK | jq -r '.result.block_id.hash')
    sed -i -e '/enable =/ s/= .*/= true/' $NODE_HOME/config/config.toml
    sed -i -e '/trust_period =/ s/= .*/= "8h0m0s"/' $NODE_HOME/config/config.toml
    sed -i -e "/trust_height =/ s/= .*/= $TRUST_HEIGHT/" $NODE_HOME/config/config.toml
    sed -i -e "/trust_hash =/ s/= .*/= \"$TRUST_HASH\"/" $NODE_HOME/config/config.toml
    sed -i -e "/rpc_servers =/ s^= .*^= \"$SYNC_RPC_SERVERS\"^" $NODE_HOME/config/config.toml
else
    echo "Skipping state sync..."
fi

# # Replace genesis file
echo "Downloading genesis file..."
echo "Downloading genesis file..."
wget $GENESIS_URL || { echo "Failed to download genesis file"; exit 1; }
cp $CHAIN_ID.json $NODE_HOME/config/genesis.json

SERVICE_PATH=/etc/systemd/system/$SERVICE_NAME.service
sudo rm -f ${SERVICE_PATH}
sudo touch ${SERVICE_PATH}

echo "[Unit]" | sudo tee $SERVICE_PATH
echo "Description=Exocore service" | sudo tee $SERVICE_PATH -a
echo "After=network-online.target" | sudo tee $SERVICE_PATH -a
echo "" | sudo tee $SERVICE_PATH -a
echo "[Service]" | sudo tee $SERVICE_PATH -a
echo "Environment=HOME=/root" | sudo tee $SERVICE_PATH -a
echo "User=$USER" | sudo tee $SERVICE_PATH -a
echo "ExecStart=$HOME/go/bin/$CHAIN_BINARY start --x-crisis-skip-assert-invariants --home $NODE_HOME" | sudo tee $SERVICE_PATH -a
echo "Restart=no" | sudo tee $SERVICE_PATH -a
echo "LimitNOFILE=4096" | sudo tee $SERVICE_PATH -a
echo "" | sudo tee $SERVICE_PATH -a
echo "[Install]" | sudo tee $SERVICE_PATH -a
echo "WantedBy=multi-user.target" | sudo tee $SERVICE_PATH -a

# Start service
echo "Starting $SERVICE_NAME.service..."
sudo systemctl daemon-reload
sudo systemctl enable --now $SERVICE_NAME.service
sudo systemctl start $SERVICE_NAME.service
sudo systemctl restart systemd-journald

# Add go and exocored to the path
echo "Setting up paths for go and exocored bin..."
echo "export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin" >>.profile

echo "***********************"
echo "To see the Exocore log enter:"
echo "journalctl -fu $SERVICE_NAME.service"
echo "***********************"
