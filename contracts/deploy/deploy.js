const { ethers } = require("ethers");
const { Wallet, Provider } = require("zksync-ethers");
const fs = require("fs");

async function main() {
  // Check if the script is running for mainnet deployment
  const isMainnet = process.argv.includes("--mainnet");
  // Check if mock contracts should be used
  const useMocks = process.argv.includes("--mock");

  // Configure provider based on network
  const provider = new Provider(
    isMainnet
      ? "https://mainnet.era.zksync.io"
      : "https://testnet.era.zksync.io"
  );

  // Load or generate deployer wallet
  let deployer;
  if (process.env.PRIVATE_KEY) {
    // Create a new wallet instance using the provided private key
    deployer = new Wallet(process.env.PRIVATE_KEY, provider);
  } else {
    // Throw an error if no private key is provided
    throw "deployer private key is required";
  }

  // Load contract artifacts
  const UntronCore = require("./zkout/UntronCore.sol/UntronCore.json");
  const MockSpokePool = require("./zkout/MockSpokePool.sol/MockSpokePool.json");
  const MockAggregationRouter = require("./zkout/MockAggregationRouter.sol/MockAggregationRouter.json");
  const SP1MockVerifier = require("./zkout/SP1MockVerifier.sol/SP1MockVerifier.json");
  const MockUSDT = require("./zkout/MockUSDT.sol/MockUSDT.json");

  // Deploy mock contracts if needed
  let usdtAddress = "0x493257fD37EDB34451f62EDf8D2a0C418852bA4C"; // https://era.zksync.network/token/0x493257fd37edb34451f62edf8d2a0c418852ba4c
  let spokePoolAddress = "0xE0B015E54d54fc84a6cB9B666099c46adE9335FF"; // https://docs.across.to/reference/contract-addresses/zksync-chain-id-324
  let aggregationRouterAddress = "0x6fd4383cB451173D5f9304F041C7BCBf27d561fF"; // https://era.zksync.network/address/0x6fd4383cb451173d5f9304f041c7bcbf27d561ff
  let sp1VerifierAddress = "0x..."; // TODO: find it out

  // Deploy mock contracts for non-mainnet environments
  if (!isMainnet) {
    // Deploy and set MockUSDT
    const mockUSDT = await deployContract(deployer, MockUSDT);
    usdtAddress = mockUSDT.address;

    // Deploy and set MockSpokePool
    const mockSpokePool = await deployContract(deployer, MockSpokePool);
    spokePoolAddress = mockSpokePool.address;

    // Deploy and set MockAggregationRouter
    const mockAggregationRouter = await deployContract(
      deployer,
      MockAggregationRouter
    );
    aggregationRouterAddress = mockAggregationRouter.address;
  }

  // Deploy mock SP1Verifier for non-mainnet or when using mocks
  if (!isMainnet || useMocks) {
    const mockSP1Verifier = await deployContract(deployer, SP1MockVerifier);
    sp1VerifierAddress = mockSP1Verifier.address;
  }

  // Deploy UntronCore implementation
  const untronImplementation = await deployContract(deployer, UntronCore);

  // Prepare initialization data for the proxy
  const initData = UntronCore.interface.encodeFunctionData("initialize", [
    spokePoolAddress,
    usdtAddress,
    aggregationRouterAddress,
  ]);

  // Load ERC1967Proxy artifact
  const ERC1967Proxy = require("./artifacts/ERC1967Proxy.json");
  // Deploy ERC1967Proxy with UntronCore implementation
  const proxy = await deployContract(deployer, ERC1967Proxy, [
    untronImplementation.address,
    initData,
  ]);

  // Create UntronCore instance using the proxy address
  const untron = new ethers.Contract(proxy.address, UntronCore.abi, deployer);

  // Get addresses for different roles from environment variables
  const admin = process.env.ADMIN_ADDRESS;
  const unlimitedCreator = process.env.UNLIMITED_CREATOR_ADDRESS;
  const registrar = process.env.REGISTRAR_ADDRESS;

  // Transfer admin roles if admin address is provided
  if (admin) {
    await untron.grantRole(await untron.DEFAULT_ADMIN_ROLE(), admin);
    await untron.grantRole(await untron.UPGRADER_ROLE(), admin);
    await untron.revokeRole(
      await untron.DEFAULT_ADMIN_ROLE(),
      deployer.address
    );
    await untron.revokeRole(await untron.UPGRADER_ROLE(), deployer.address);
  }
  // Transfer unlimited creator role if address is provided
  if (unlimitedCreator) {
    await untron.grantRole(
      await untron.UNLIMITED_CREATOR_ROLE(),
      unlimitedCreator
    );
    await untron.revokeRole(
      await untron.UNLIMITED_CREATOR_ROLE(),
      deployer.address
    );
  }
  // Transfer registrar role if address is provided
  if (registrar) {
    await untron.grantRole(await untron.REGISTRAR_ROLE(), registrar);
    await untron.revokeRole(await untron.REGISTRAR_ROLE(), deployer.address);
  }

  // Set UntronZK variables
  const vkey = process.env.SP1_VKEY || ethers.constants.HashZero;
  await untron.setUntronZKVariables(sp1VerifierAddress, vkey);

  // Prepare deployment data for export
  const deploymentData = {
    network: isMainnet ? "mainnet" : "testnet",
    untron: untron.address,
    untronImplementation: untronImplementation.address,
    spokePool: spokePoolAddress,
    aggregationRouter: aggregationRouterAddress,
    usdt: usdtAddress,
    sp1Verifier: sp1VerifierAddress,
    admin,
    unlimitedCreator,
    registrar,
    deployer: deployer.address,
  };

  // Write deployment data to a JSON file
  fs.writeFileSync("deployment.json", JSON.stringify(deploymentData, null, 2));
  console.log("Deployment data saved to deployment.json");
}

async function deployContract(wallet, contractArtifact, args = []) {
  const factory = new ethers.ContractFactory(
    contractArtifact.abi,
    contractArtifact.bytecode,
    wallet
  );
  const contract = await factory.deploy(...args);
  await contract.deployed();
  console.log(
    `Deployed ${contractArtifact.contractName} at ${contract.address}`
  );
  return contract;
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
