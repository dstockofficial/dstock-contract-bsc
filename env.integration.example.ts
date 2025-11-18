#
# Environment example for TypeScript scripts under script/ts/
# Copy into .env or .env.local and override with real values.
#

# Environment example dedicated to integration tests under script/ts/integration/.
# Use together with env.invoke.example.ts or merge into your root .env.

# --- Integration: RPC + Keys ---
BSC_TESTNET_RPC=https://example-rpc
PRIVATE_KEY=0x{64-hex}          # signer for tx scripts (wrap/unwrap/compliance setters)
ADMIN_PK=0x{64-hex}             # optional fallback for utils

# --- Integration: Common addresses ---
WRAPPER=0xYourWrapperAddress
UNDERLYING=0xUnderlyingTokenAddress
FACTORY=0xFactoryRegistryAddress
COMPLIANCE=0xCurrentCompliance
OLD_COMPLIANCE=0xOldCompliance
NEW_COMPLIANCE=0xNewCompliance
ACCOUNT=0xAccountToInspect
TO=0xRecipientAddress

# --- Wrapper admin scenario ---
ADMIN_SCENARIO_WRAP_FEE_BPS=50
ADMIN_SCENARIO_UNWRAP_FEE_BPS=50
ADMIN_SCENARIO_CAP="1000000"
ADMIN_SCENARIO_MIN_INITIAL_DEPOSIT="100"
ADMIN_SCENARIO_WRAP_UNWRAP_PAUSED=false
TEST_AUTO_KYC=true
TEST_AUTO_CUSTODY=false

# --- Compliance migration scenario ---
FLAGS_COPY_TOKENS=0xWrapper1,0xWrapper2
KYC_COPY_ADDRESSES=0xUser1,0xUser2
CUSTODY_COPY_ADDRESSES=0xCustodian1
SANCTION_COPY_ADDRESSES=
FLAGS_WRAPPER=0xWrapperNeedingOverride

# --- Factory upgrade scenario ---
WRAPPER_IMPL_NEW=0xNewWrapperImplAddress


