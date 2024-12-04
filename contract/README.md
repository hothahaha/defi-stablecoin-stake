# 部署合约

forge script script/DeployLocalTest.s.sol --rpc-url http://localhost:8545 --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

forge script script/DeployL2CustomERC20.s.sol --rpc-url http://localhost:9545 --broadcast
--private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

forge script script/DeployLocalTest.s.sol --rpc-url http://localhost:8545 --private-key "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" --broadcast

forge script script/DeployLocalTest.s.sol --rpc-url http://localhost:9545 --private-key "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" --broadcast
