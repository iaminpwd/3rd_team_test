#!/bin/bash
# scripts/cleanup_vpn.sh

# 온라인 상태인 인스턴스 ID 추출
INSTANCE_ID=$(aws ssm describe-instance-information \
  --query "InstanceInformationList[?PingStatus=='Online'].InstanceId" \
  --output text | grep -oE '(i-|mi-)[a-f0-9]+' | head -n 1)

if [ -n "$INSTANCE_ID" ] && [ "$INSTANCE_ID" != "None" ] && [ "$INSTANCE_ID" != "null" ]; then
  echo "✅ 온프레미스 서버($INSTANCE_ID)를 발견했습니다. 초기화 명령을 전송합니다."
  
  # Cleanup 파워쉘 스크립트 로드 및 인코딩
  B64_SCRIPT=$(cat ./scripts/vpn_bgp_cleanup.ps1 | base64 -w 0)
  EXEC_CMD="[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('$B64_SCRIPT')) | Invoke-Expression"
  
  # 비동기 명령 전송 (Fire and Forget)
  COMMAND_ID=$(aws ssm send-command \
    --document-name "AWS-RunPowerShellScript" \
    --targets "Key=InstanceIds,Values=$INSTANCE_ID" \
    --parameters "commands=[\"$EXEC_CMD\"]" \
    --query "Command.CommandId" \
    --output text)
    
  echo "🚀 스크립트 전송 완료 (Command ID: $COMMAND_ID)"
  echo "윈도우 서버가 백그라운드에서 초기화를 진행하는 동안 다음 단계를 진행합니다."
  
  # SSM 인스턴스 등록 해제
  aws ssm deregister-managed-instance --instance-id "$INSTANCE_ID"
  echo "✅ AWS SSM 인스턴스($INSTANCE_ID) 등록 해제 완료."

else
  echo "ℹ️ 온라인 상태인 서버를 찾을 수 없어 내부 초기화를 건너뜁니다."
fi