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
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME/.cargo/env"
rustup install stable
rustup default stable
export PATH="$HOME/.cargo/bin:$PATH"
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
sudo apt update && sudo apt install git
git clone https://github.com/Eclipse-Laboratories-Inc/testnet-deposit
cd testnet-deposit

# npm 인스톨
apt install npm
npm install bs58@4.0.1
echo

# Solana CLI 제거
echo -e "${YELLOW}Solana CLI를 제거하는 중입니다...${NC}"
echo
rm -rf ~/.local/share/solana
export PATH="/path/to/solana-cli:$PATH"
source ~/.bashrc

# Solana CLI 설치
echo -e "${YELLOW}Solana CLI를 설치하는 중입니다...${NC}"
echo
sh -c "$(curl -sSfL https://release.solana.com/v1.17.34/install)"
export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"
source ~/.bashrc

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

    # Solana 개인키를 base58에서 바이너리로 변환
    cat <<EOF > decode-private-key.cjs
const { Keypair } = require('@solana/web3.js');
const bs58 = require('bs58');
const fs = require('fs');

// 환경 변수로부터 개인키를 가져옵니다.
const privateKeyBase58 = process.env.SOLANA_PRIVATE_KEY;

// base58 인코딩된 개인키를 디코딩하여 바이너리 형식으로 변환합니다.
const privateKeyBytes = Buffer.from(bs58.decode(privateKeyBase58));

// 바이너리 형식의 개인키로부터 Keypair 객체를 생성합니다.
const keypair = Keypair.fromSecretKey(privateKeyBytes);

// 지갑 파일로 Keypair의 비밀키를 저장합니다.
fs.writeFileSync(process.env.WALLET_FILE, JSON.stringify(Array.from(keypair.secretKey)), 'utf8');

console.log('Solana 지갑 파일이 저장되었습니다:', process.env.WALLET_FILE);
EOF

    # 환경 변수 설정
    export SOLANA_PRIVATE_KEY="$solana_private_key"
    export WALLET_FILE="$WALLET_FILE"

    # 필요한 Node.js 패키지 설치
    if ! npm list bs58 &>/dev/null; then
        echo "bs58 패키지가 없습니다. 설치 중입니다..."
        echo
        npm install bs58@4.0.1
        echo
    fi

    node decode-private-key.cjs
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

# 브릿지 스크립트 실행
if [ -d "testnet-deposit" ]; then
    execute_and_prompt "testnet-deposit 폴더를 제거하는 중입니다..." "rm -rf testnet-deposit"
fi

read -p "Solana 주소를 입력하세요. 위에 초록색으로 나온 주소와 같습니다.: " solana_address
read -p "Ethereum 개인키를 입력하세요: " ethereum_private_key
read -p "브릿징 트랜잭션 반복 횟수 입력 (1-5 추천): " repeat_count
echo

for ((i=1; i<=repeat_count; i++)); do
    echo -e "${YELLOW}브릿징 스크립트 실행 (트랜잭션 $i)...${NC}"
    echo
    node bin/cli.js -k pvt-key.txt -d "$solana_address" -a 0.01 --sepolia
    echo
    sleep 3
done

echo -e "${RED}브릿징 컨펌을 위해 4분 정도 소요됩니다. 아무 것도 하지 말고 기다리세요.${NC}"
sleep 1

echo -e "${YELLOW}Solana Hello World 레포지토리를 클론하는 중입니다...${NC}"
echo
git clone https://github.com/solana-labs/example-helloworld
cd example-helloworld
echo

# Cargo.toml 파일 수정 및 의존성 업데이트
echo -e "${YELLOW}Cargo.toml 파일을 수정하고 의존성을 업데이트하는 중입니다...${NC}"
sed -i 's/^solana-program = ".*"/solana-program = "1.17.34"/' src/program-rust/Cargo.toml
sed -i 's/^solana-sdk = ".*"/solana-sdk = "1.17.34"/' src/program-rust/Cargo.toml
sed -i 's/^solana-program-test = ".*"/solana-program-test = "1.17.34"/' src/program-rust/Cargo.toml

# Cargo 업데이트
echo -e "${YELLOW}Cargo를 업데이트하는 중입니다...${NC}"
cd src/program-rust
rm -f Cargo.lock
cargo update
cd ../..
echo

# 프로젝트 빌드
echo "프로젝트를 빌드하는 중입니다..."
npm install bs58@4.0.1
echo

# 스마트 컨트랙 빌드
echo -e "${YELLOW}스마트 컨트랙을 빌드하는 중입니다...시간이 오래 걸립니다.${NC}"
npm run build:program-rust
echo

# Eclipse Testnet에 스마트 컨트랙 배포
echo -e "${YELLOW}Eclipse Testnet에 컨트랙을 배포하는 중입니다...${NC}"
echo
solana program deploy dist/program/helloworld.so
echo

# 컨트랙이 성공적으로 배포되었는지 확인
echo -e "${YELLOW}컨트랙이 성공적으로 배포되었는지 확인하는 중입니다...${NC}"
echo
npm run start
echo

# 홈 디렉토리로 이동
cd $HOME

# 토큰 생성
execute_and_prompt "토큰을 생성하는 중입니다..." "spl-token create-token --enable-metadata -p TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"
echo

# 사용자 토큰 주소를 입력받음
echo -e "${YELLOW}위에 출력된 Token address를 그대로 입력하세요.${NC}"
token_address=$(prompt "Enter your Token Address: ")
echo

# 토큰 계좌 생성
echo -e "${YELLOW}토큰 계좌를 생성하는 중입니다...${NC}"
execute_and_prompt "토큰 계좌를 생성하는 중입니다..." "spl-token create-account $token_address"
echo

# 토큰 발행
echo -e "${YELLOW}토큰을 발행하는 중입니다...${NC}"
execute_and_prompt "토큰을 발행하는 중입니다..." "spl-token mint $token_address 10000"

# @solana/web3.js 설치 및 비밀키 출력
cd $HOME

echo -e "${YELLOW}@solana/web3.js를 설치하는 중입니다...${NC}"
npm install @solana/web3.js

ENCRYPTED_KEY=$(cat my-wallet.json)

cat <<EOF > private-key.cjs
const solanaWeb3 = require('@solana/web3.js');

const byteArray = JSON.parse(process.env.ENCRYPTED_KEY);
const secretKey = new Uint8Array(byteArray);
const keypair = solanaWeb3.Keypair.fromSecretKey(secretKey);

console.log("Solana 주소:", keypair.publicKey.toBase58());
console.log("Solana 지갑의 비밀키:", Buffer.from(keypair.secretKey).toString('hex'));
EOF

export ENCRYPTED_KEY="$(cat my-wallet.json)"
node private-key.cjs

echo
echo -e "${YELLOW}다음 경로에 있는 파일에 중요한 정보가 저장되어 있습니다.:${NC}"
echo -e "Solana 개인키 파일: $HOME/my-wallet.json"
echo -e "Ethereum 개인키 파일: $HOME/pvt-key.txt"
echo -e "MetaMask 시드 문구 파일: $HOME/secrets.json"
echo -e "${GREEN}새지갑을 만든 경우 비밀키를 안전한 곳에 저장하세요. 향후 에어드랍이 있을 경우, 이 지갑으로부터 수령할 수 있습니다.${NC}"
echo -e "${GREEN}스크립트작성자-https://t.me/kjkresearch${NC}"

