#!/bin/bash
# scripts/setup_vpn.sh

set -e # 에러 발생 시 즉시 중단

echo "1. AWS SSM에서 Online 상태의 인스턴스를 찾는 중..."
INSTANCE_ID=""

for i in {1..15}; do
  # AWS CLI 페이징 버그 방지를 위해 grep 사용
  RAW_ID=$(aws ssm describe-instance-information --query "InstanceInformationList[?PingStatus=='Online'].InstanceId" --output text | grep -o 'mi-[0-9a-f]*' | head -n 1)
  
  if [ -n "$RAW_ID" ]; then
    INSTANCE_ID=$RAW_ID
    echo "✅ 인스턴스 인식 성공: $INSTANCE_ID"
    break
  fi
  echo "⏳ 대기 중 ($i/15)... 20초 후 다시 시도합니다."
  sleep 20
done

if [ -z "$INSTANCE_ID" ]; then
  echo "❌ 오류: 5분을 기다렸으나 Online 상태의 노드를 찾지 못했습니다."
  exit 1
fi

# 2. 파워쉘 스크립트 조립 (환경 변수로부터 값을 주입받음)
cat <<EOF > final_script.ps1
\$AwsVpcCidr = "$AWS_VPC_CIDR"
\$OnpremVpcCidr = "$ONPREM_VPC_CIDR"
\$Tunnel1Ip = "$TUNNEL1_IP"
\$Tunnel1Psk = "$TUNNEL1_PSK"
\$BgpPeer1Ip = "$BGP_PEER1_IP"
\$BgpLocal1Ip = "$BGP_LOCAL1_IP"
\$Tunnel2Ip = "$TUNNEL2_IP"
\$Tunnel2Psk = "$TUNNEL2_PSK"
\$BgpPeer2Ip = "$BGP_PEER2_IP"
\$BgpLocal2Ip = "$BGP_LOCAL2_IP"
EOF

# 메인 셋업 로직 결합
cat ./scripts/vpn_bgp_setup.ps1 >> final_script.ps1

B64_SCRIPT=$(cat final_script.ps1 | base64 -w 0)
EXEC_CMD="[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('$B64_SCRIPT')) | Invoke-Expression"

# 3. SSM 명령 전송
echo "2. 스크립트 전송 중..."
COMMAND_ID=$(aws ssm send-command \
  --document-name "AWS-RunPowerShellScript" \
  --targets "Key=InstanceIds,Values=$INSTANCE_ID" \
  --parameters "commands=[\"$EXEC_CMD\"]" \
  --timeout-seconds 600 \
  --query "Command.CommandId" \
  --output text)

echo "명령 전송 완료. Command ID: $COMMAND_ID"
echo "⏳ 윈도우 RRAS 엔진 구성 및 BGP 세션 확립 대기 중 (최대 10분)..."

# 4. 롱폴링(Long-Polling) 대기 로직
ATTEMPTS=0
MAX_ATTEMPTS=60

while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
  STATUS=$(aws ssm list-command-invocations \
    --command-id $COMMAND_ID \
    --details \
    --query "CommandInvocations[0].Status" \
    --output text)
  
  echo "Current Status: $STATUS ($ATTEMPTS/$MAX_ATTEMPTS)"
  
  if [ "$STATUS" == "Success" ]; then
    echo "✅ 모든 설정이 성공적으로 완료되었습니다!"
    exit 0
  elif [ "$STATUS" == "Failed" ] || [ "$STATUS" == "Cancelled" ] || [ "$STATUS" == "TimedOut" ]; then
    echo "❌ 명령 실행 실패! (SSM 콘솔을 확인하세요)"
    exit 1
  fi
  
  sleep 10
  ATTEMPTS=$((ATTEMPTS + 1)) # 안전한 산술 연산
done

echo "❌ 대기 시간 초과!"
exit 1