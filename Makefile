-include .env

# Network RPC URLs
BASE_RPC ?= https://mainnet.base.org
POLYGON_RPC ?= https://polygon-rpc.com

# Chain IDs
BASE_CHAIN_ID ?= 8453
POLYGON_CHAIN_ID ?= 137

# Default network
network ?= base

# Network-specific configurations
ifeq ($(network),base)
	RPC_URL = $(BASE_RPC)
	CHAIN_ID = $(BASE_CHAIN_ID)
else ifeq ($(network),polygon)
	RPC_URL = $(POLYGON_RPC)
	CHAIN_ID = $(POLYGON_CHAIN_ID)
endif

# Common forge command
FORGE_CMD = forge script

# Deploy MetaVault and Gateway
deploy-vault:
	$(FORGE_CMD) script/base/DeployScript.s.sol:DeployScript \
		--rpc-url $(RPC_URL) \
		--broadcast \
		--verify

# Deploy SuperPositions Receiver
deploy-receiver:
	$(FORGE_CMD) script/base/DeploySuperPositionsReceiver.s.sol:DeploySuperPositionsReceiver \
		--rpc-url $(RPC_URL) \
		--broadcast \
		--verify

# Set Recovery Address
set-recovery:
	$(FORGE_CMD) script/base/SetRecoveryAddress.s.sol:SetRecoveryAddress \
		--rpc-url $(RPC_URL) \
		--broadcast

# Add New Vault
add-vault:
	$(FORGE_CMD) script/base/AddVaultScript.s.sol:AddVaultScript \
		--rpc-url $(RPC_URL) \
		--broadcast

# Add Functions to MetaVault
add-functions-vault:
	$(FORGE_CMD) script/base/AddFunctionsScript.s.sol:AddFunctionsScript \
		--rpc-url $(RPC_URL) \
		--broadcast

# Remove Functions from MetaVault
remove-functions-vault:
	$(FORGE_CMD) script/base/RemoveFunctionsScript.s.sol:RemoveFunctionsScript \
		--rpc-url $(RPC_URL) \
		--broadcast

# Add Functions to Gateway
add-functions-gateway:
	$(FORGE_CMD) script/base/AddFunctionsGatewayScript.s.sol:AddFunctionsGatewayScript \
		--rpc-url $(RPC_URL) \
		--broadcast

# Remove Functions from Gateway
remove-functions-gateway:
	$(FORGE_CMD) script/base/RemoveFunctionsGatewayScript.s.sol:RemoveFunctionsScript \
		--rpc-url $(RPC_URL) \
		--broadcast

# Recover Funds
recover-funds:
	$(FORGE_CMD) script/base/RecoverFundsScript.s.sol:RecoverFundsScript \
		--rpc-url $(RPC_URL) \
		--broadcast

# Full deployment sequence
deploy-all: deploy-vault deploy-receiver set-recovery

# Help command
help:
	@echo "Available commands:"
	@echo "  make deploy-vault network=<base|polygon>    - Deploy MetaVault and Gateway"
	@echo "  make deploy-receiver network=<base|polygon> - Deploy SuperPositions Receiver"
	@echo "  make set-recovery network=<base|polygon>    - Set Recovery Address"
	@echo "  make add-vault network=<base|polygon>       - Add New Vault"
	@echo "  make add-functions-vault network=<base|polygon>    - Add Functions to MetaVault"
	@echo "  make remove-functions-vault network=<base|polygon> - Remove Functions from MetaVault"
	@echo "  make add-functions-gateway network=<base|polygon>  - Add Functions to Gateway"
	@echo "  make remove-functions-gateway network=<base|polygon> - Remove Functions from Gateway"
	@echo "  make recover-funds network=<base|polygon>   - Recover Funds"
	@echo "  make deploy-all network=<base|polygon>      - Full deployment sequence"

.PHONY: deploy-vault deploy-receiver set-recovery add-vault add-functions-vault remove-functions-vault add-functions-gateway remove-functions-gateway recover-funds deploy-all help