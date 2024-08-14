#!/bin/bash
# Set up a Exocore service to join the Exocore Release testnet.

# Configuration
# You should only have to modify the values in this block
# ***
NODE_HOME=~/.exocored
NODE_MONIKER=release-testnet
SERVICE_NAME=exocore
EXOCORE_VERSION=1.0.2
CHAIN_BINARY_URL=https://github.com/ExocoreNetwork/exocore/releases/download/v$EXOCORE_VERSION/exocore_$EXOCORE_VERSION\_Linux_amd64.tar.gz
STATE_SYNC=true
GAS_PRICE=0.0001aexo
# ***

CHAIN_BINARY='exocored'
CHAIN_ID=exocoretestnet_233-4
GENESIS_ZIPPED_URL=https://github.com/ExocoreNetwork/testnets/raw/main/genesis/exocoretestnet_233-4.json
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
wget $CHAIN_BINARY_URL
tar -xvf exocore_$EXOCORE_VERSION\_Linux_amd64.tar.gz
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
    CURRENT_BLOCK=$(curl -s $SYNC_RPC_1/block | jq -r '.result.block.header.height')
    TRUST_HEIGHT=$(($CURRENT_BLOCK - 1000))
    TRUST_BLOCK=$(curl -s $SYNC_RPC_1/block\?height\=$TRUST_HEIGHT)
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
wget $GENESIS_ZIPPED_URL
cp $CHAIN_ID.json $NODE_HOME/config/genesis.json

sudo rm /etc/systemd/system/$SERVICE_NAME.service
sudo touch /etc/systemd/system/$SERVICE_NAME.service

echo "[Unit]" | sudo tee /etc/systemd/system/$SERVICE_NAME.service
echo "Description=Exocore service" | sudo tee /etc/systemd/system/$SERVICE_NAME.service -a
echo "After=network-online.target" | sudo tee /etc/systemd/system/$SERVICE_NAME.service -a
echo "" | sudo tee /etc/systemd/system/$SERVICE_NAME.service -a
echo "[Service]" | sudo tee /etc/systemd/system/$SERVICE_NAME.service -a
echo "User=$USER" | sudo tee /etc/systemd/system/$SERVICE_NAME.service -a
echo "ExecStart=$HOME/go/bin/$CHAIN_BINARY start --x-crisis-skip-assert-invariants --home $NODE_HOME" | sudo tee /etc/systemd/system/$SERVICE_NAME.service -a
echo "Restart=no" | sudo tee /etc/systemd/system/$SERVICE_NAME.service -a
echo "LimitNOFILE=4096" | sudo tee /etc/systemd/system/$SERVICE_NAME.service -a
echo "" | sudo tee /etc/systemd/system/$SERVICE_NAME.service -a
echo "[Install]" | sudo tee /etc/systemd/system/$SERVICE_NAME.service -a
echo "WantedBy=multi-user.target" | sudo tee /etc/systemd/system/$SERVICE_NAME.service -a

# Start service
echo "Starting $SERVICE_NAME.service..."
sudo systemctl daemon-reload
sudo systemctl enable $SERVICE_NAME.service
sudo systemctl start $SERVICE_NAME.service
sudo systemctl restart systemd-journald

# Add go and exocored to the path
echo "Setting up paths for go and exocored bin..."
echo "export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin" >>.profile

echo "***********************"
echo "To see the Exocore log enter:"
echo "journalctl -fu $SERVICE_NAME.service"
echo "***********************"
