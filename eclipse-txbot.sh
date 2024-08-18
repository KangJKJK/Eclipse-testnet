#!/bin/bash

export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export NC='\033[0m'

prompt() {
    local message="$1"
    read -p "$message" input
    echo "$input"
}

execute_and_prompt() {
    local message="$1"
    local command="$2"
    echo -e "${YELLOW}${message}${NC}"
    eval "$command"
    echo -e "${GREEN}Done.${NC}"
}

# Rust 설치
echo -e "${YELLOW}Rust를 설치하는 중입니다...${NC}"
echo
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME/.cargo/env"
echo -e "${GREEN}Rust가 설치되었습니다: $(rustc --version)${NC}"
echo

# NVM 설치
echo -e "${YELLOW}NVM을 설치하는 중입니다...${NC}"
echo
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.3/install.sh | bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # NVM을 로드합니다
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # NVM bash_completion을 로드합니다
source ~/.bashrc

# NVM을 통해 최신 LTS 버전의 Node.js 설치
echo -e "${YELLOW}NVM을 사용하여 최신 LTS 버전의 Node.js를 설치하는 중입니다...${NC}"
nvm install --lts
nvm use --lts
echo -e "${GREEN}Node.js가 설치되었습니다: $(node -v)${NC}"
echo

# 기존 testnet-deposit 폴더 삭제
if [ -d "testnet-deposit" ]; then
    execute_and_prompt "기존 testnet-deposit 폴더를 제거하는 중입니다..." "rm -rf testnet-deposit"
fi

# 레포지토리 클론 및 npm 의존성 설치
echo -e "${YELLOW}레포지토리를 클론하고 npm 의존성을 설치하는 중입니다...${NC}"
echo
git clone https://github.com/Eclipse-Laboratories-Inc/testnet-deposit
cd testnet-deposit
npm install
echo

# Solana CLI 설치
echo -e "${YELLOW}Solana CLI를 설치하는 중입니다...${NC}"
echo
sh -c "$(curl -sSfL https://release.solana.com/stable/install)"
export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"

echo -e "${GREEN}Solana CLI가 설치되었습니다: $(solana --version)${NC}"
echo

# Solana 지갑 생성 또는 복구
echo -e "${YELLOW}옵션을 선택하세요:${NC}"
echo -e "1) 새로운 Solana 지갑 생성"
echo -e "2) 개인키로 Solana 지갑 복구"

read -p "선택지를 입력하세요 (1 또는 2): " choice

WALLET_FILE=~/my-wallet.json

# 기존 지갑 파일이 있는 경우 삭제
if [ -f "$WALLET_FILE" ]; then
    echo -e "${YELLOW}기존 지갑 파일을 찾았습니다. 삭제하는 중입니다...${NC}"
    rm "$WALLET_FILE"
fi

if [ "$choice" -eq 1 ]; then
    echo -e "${YELLOW}새로운 Solana 키페어를 생성하는 중입니다...${NC}"
    solana-keygen new -o "$WALLET_FILE"
    echo -e "${YELLOW}이 시드 문구를 안전한 곳에 저장하세요. 향후 에어드랍이 있을 경우, 이 지갑으로부터 수령할 수 있습니다.${NC}"
elif [ "$choice" -eq 2 ]; then
    echo -e "${YELLOW}개인키를 사용하여 Solana 키페어를 복구하는 중입니다...${NC}"
    read -p "Solana 개인키를 입력하세요 (base58로 인코딩된 문자열): " solana_private_key
    echo "$solana_private_key" | base58 -d > "$WALLET_FILE"
else
    echo -e "${RED}잘못된 선택입니다. 종료합니다.${NC}"
    exit 1
fi

# 시드 문구를 사용하여 Ethereum 개인키 도출
read -p "메타마스크 복구문자를 입력하세요: " mnemonic
echo

cat << EOF > secrets.json
{
  "seedPhrase": "$mnemonic"
}
EOF

cat << 'EOF' > derive-wallet.cjs
const { seedPhrase } = require('./secrets.json');
const { HDNodeWallet } = require('ethers');
const fs = require('fs');

const mnemonicWallet = HDNodeWallet.fromPhrase(seedPhrase);
const privateKey = mnemonicWallet.privateKey;

console.log();
console.log('ETHEREUM PRIVATE KEY:', privateKey);
console.log();
console.log('SEND MIN 0.05 SEPOLIA ETH TO THIS ADDRESS:', mnemonicWallet.address);

fs.writeFileSync('pvt-key.txt', privateKey, 'utf8');
EOF

# ethers.js 설치 여부 확인 및 필요시 설치
if ! npm list ethers &>/dev/null; then
  echo "ethers.js가 없습니다. 설치 중입니다..."
  echo
  npm install ethers
  echo
fi

node derive-wallet.cjs
echo

# Solana CLI 구성
echo -e "${YELLOW}Solana CLI를 구성하는 중입니다...${NC}"
echo
solana config set --url https://testnet.dev2.eclipsenetwork.xyz/
solana config set --keypair ~/my-wallet.json
echo
echo -e "${GREEN}Solana 주소: $(solana address)${NC}"
echo

# 브리지 스크립트 실행
if [ -d "testnet-deposit" ]; then
    execute_and_prompt "testnet-deposit 폴더를 제거하는 중입니다..." "rm -rf testnet-deposit"
fi

read -p "Solana 주소를 입력하세요: " solana_address
read -p "Ethereum 개인키를 입력하세요: " ethereum_private_key
read -p "트랜잭션 반복 횟수 입력 (4-5 추천): " repeat_count
echo

for ((i=1; i<=repeat_count; i++)); do
    echo -e "${YELLOW}브리지 스크립트 실행 (트랜잭션 $i)...${NC}"
    echo
    node bin/cli.js -k pvt-key.txt -d "$solana_address" -a 0.01 --sepolia
    echo
    sleep 3
done

echo -e "${RED}4분 정도 소요됩니다. 아무 것도 하지 말고 기다리세요.${NC}"
echo

sleep 240
execute_and_prompt "토큰을 생성하는 중입니다..." "spl-token create-token --enable-metadata -p TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"
echo

token_address=$(prompt "토큰 주소를 입력하세요: ")
echo
execute_and_prompt "토큰 계좌를 생성하는 중입니다..." "spl-token create-account $token_address"
echo

execute_and_prompt "토큰을 발행하는 중입니다..." "spl-token mint $token_address 10000"
echo
execute_and_prompt "토큰 계좌를 확인하는 중입니다..." "spl-token accounts"
echo

# @solana/web3.js 설치 및 비밀키 출력
cd $HOME

echo -e "${YELLOW}@solana/web3.js를 설치하는 중입니다...${NC}"
echo
npm install @solana/web3.js
echo

ENCRYPTED_KEY=$(cat my-wallet.json)

cat <<EOF > private-key.js
const solanaWeb3 = require('@solana/web3.js');

const byteArray = $ENCRYPTED_KEY;

const secretKey = new Uint8Array(byteArray);

const keypair = solanaWeb3.Keypair.fromSecretKey(secretKey);

console.log("Solana 주소:", keypair.publicKey.toBase58());
console.log("Solana 지갑의 비밀키:", Buffer.from(keypair.secretKey).toString('hex'));
EOF

node private-key.js

echo
echo -e "${YELLOW}다음 파일에 중요한 정보가 저장되어 있습니다:${NC}"
echo -e "Solana 개인키 파일: $HOME/my-wallet.json"
echo -e "Ethereum 비밀키 파일: $HOME/pvt-key.txt"
echo -e "MetaMask 시드 문구 파일: $HOME/secrets.json"
echo -e "${GREEN}새지갑을 만든 경우 비밀키를 안전한 곳에 저장하세요. 향후 에어드랍이 있을 경우, 이 지갑으로부터 수령할 수 있습니다.${NC}"
echo
execute_and_prompt "프로그램 주소 확인 중..." "solana address"
echo
echo -e "${Y
