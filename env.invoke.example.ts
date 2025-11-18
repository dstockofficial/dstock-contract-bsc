#
# Environment example for TypeScript scripts under script/ts/
# Copy into .env or .env.local and override with real values.
#

# --- Invoke scripts: RPC + Keys ---
BSC_TESTNET_RPC=https://example-rpc
PRIVATE_KEY=0x{64-hex}          # signer for tx scripts (wrap/unwrap/compliance setters)
ADMIN_PK=0x{64-hex}             # optional fallback for utils

# --- Invoke scripts: Common addresses ---
WRAPPER=0xYourWrapperAddress
UNDERLYING=0xUnderlyingTokenAddress
FACTORY=0xFactoryRegistryAddress
COMPLIANCE=0xComplianceContractAddress
ACCOUNT=0xAccountToInspect       # used by sharesOf or preview scripts
TO=0xRecipientAddress            # optional wrap/unwrap recipient
TARGET=0xAddressToModify         # used by compliance set scripts

# --- Amount helpers (choose one) ---
AMOUNT_WEI=1000000000000000000   # raw units (token decimals)
#AMOUNT="1.0"

# --- Invoke scripts: Wrapper governance setters ---
NEW_COMPLIANCE=0x
NEW_TREASURY=0x
WRAP_FEE_BPS_NEW=0
UNWRAP_FEE_BPS_NEW=0
CAP_NEW="1000000"
MIN_INITIAL_DEPOSIT_NEW="100"
TERMS_URI_NEW=https://terms
TOKEN_NAME_NEW=dASSET
TOKEN_SYMBOL_NEW=DASSET
PAUSED_BY_FACTORY=false
WRAP_UNWRAP_PAUSED=false
SPLIT_UNDERLYING=0x
SPLIT_NUMERATOR=1
SPLIT_DENOMINATOR=1
REBASING_UNDERLYING=0x
REBASING_FEE_MODE=0
REBASING_FEE_PER_PERIOD_RAY=0
REBASING_PERIOD_LENGTH=0
FORCE_MOVE_FROM=0x
FORCE_MOVE_AMOUNT_18=1000000000000000000
UNDERLYING_TO_ADD=0x
UNDERLYING_TOGGLE=0x
UNDERLYING_ENABLED=true

# --- Invoke scripts: Factory specific ---
WRAPPER_INIT_FILE=./wrapper-init.json
UNDERLYINGS_LIST=0xAAA,0xBBB
TARGET_WRAPPER=0xWrapperNeedingUpdate
TARGET_PAUSED=false
DEPRECATE_REASON="sunsetting"
UNDERLYING_REMOVE=0x
WRAPPER_IMPL_NEW=0x
FACTORY_NEW_COMPLIANCE=0x

# --- Invoke scripts: Compliance flags / batch ops ---
FLAGS_WRAPPER=0xWrapperForFlags
FLAGS_ENFORCE_SANCTIONS=false
FLAGS_TRANSFER_RESTRICTED=false
FLAGS_WRAP_TO_CUSTODY_ONLY=false
FLAGS_UNWRAP_FROM_CUSTODY_ONLY=false
FLAGS_KYC_ON_WRAP=true
FLAGS_KYC_ON_UNWRAP=true
KYC_BATCH_ADDRESSES=0xA,0xB,0xC
KYC_BATCH_VALUE=true
COMPLIANCE_TOKEN=0xWrapperToken
TRANSFER_FROM=0x
TRANSFER_TO=0x
TRANSFER_AMOUNT_WEI=0
TRANSFER_ACTION=1   # 0=Transfer,1=Wrap,2=Unwrap

# --- Invoke scripts: Pagination helpers ---
OFFSET=0
LIMIT=20

