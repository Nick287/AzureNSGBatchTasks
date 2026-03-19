#!/bin/bash

# ==========================================
# 1. 在这里配置您的 Azure 资源参数
# ==========================================
SUBSCRIPTION="xxxxxxxx-xxxxxxxx-xxxxxxxx-xxxxxxxx-xxxxxxxx"
RESOURCE_GROUP="mysql-rg"
NSG_NAME="mysql-rg-vnet-default-nsg-centralus"
RULE_NAME="rule001"
IP_FILE="ip-list.csv"
DESCRIPTION="允许临时白名单IP访问所有端口进行测试"

# ==========================================
# 2. 读取 IP 文件
# ==========================================
if [ ! -f "$IP_FILE" ]; then
    echo "错误: 找不到IP文件 $IP_FILE"
    exit 1
fi

# 声明一个 Bash 数组来存放干净的 IP
IP_ARRAY=()

# 逐行读取文件
while IFS= read -r line || [[ -n "$line" ]]; do
    # 清洗逻辑：
    # 1. tr -d '\r'：去除 Windows 的换行符
    # 2. sed 's/^\xEF\xBB\xBF//'：强制去除 UTF-8 的 BOM 隐藏头
    # 3. xargs：去除首尾可能存在的多余空格
    clean_ip=$(echo "$line" | tr -d '\r' | sed 's/^\xEF\xBB\xBF//' | xargs)
    
    # 如果清洗后 IP 不为空，则压入数组
    if [ -n "$clean_ip" ]; then
        IP_ARRAY+=("$clean_ip")
    fi
done < "$IP_FILE"

# 检查数组是否为空
if [ ${#IP_ARRAY[@]} -eq 0 ]; then
    echo "错误: $IP_FILE 中没有提取到有效的IP地址"
    exit 1
fi

echo "准备执行 NSG 规则配置..."
echo "目标订阅: $SUBSCRIPTION"
echo "资源组: $RESOURCE_GROUP"
echo "NSG 名称: $NSG_NAME"
echo "规则名称: $RULE_NAME"
echo "规则描述: $DESCRIPTION"
echo "读取到的白名单IP: ${IP_ARRAY[*]}"
echo "----------------------------------------"

# ==========================================
# 3. 登录并切换订阅
# ==========================================
echo "正在切换到指定订阅..."
az account set --subscription "$SUBSCRIPTION"

if [ $? -ne 0 ]; then
    echo "错误: 无法切换到订阅 $SUBSCRIPTION ，请确认已执行 az login"
    exit 1
fi

# ==========================================
# 4. 创建或更新 NSG 规则
# ==========================================
echo "正在配置 IP 的所有端口和协议..."

# 使用 "${IP_ARRAY[@]}" 将数组安全地展开为多个独立的参数传递给 Azure CLI
az network nsg rule create \
    -g "$RESOURCE_GROUP" \
    --nsg-name "$NSG_NAME" \
    -n "$RULE_NAME" \
    --priority 1000 \
    --source-address-prefixes "${IP_ARRAY[@]}" \
    --destination-address-prefixes '*' \
    --source-port-ranges '*' \
    --destination-port-ranges '*' \
    --protocol '*' \
    --access Allow \
    --direction Inbound \
    --description "$DESCRIPTION"

if [ $? -eq 0 ]; then
    echo "----------------------------------------"
    echo "规则 [$RULE_NAME] 配置成功！以上 IP 已获得全部访问权限。"
else
    echo "----------------------------------------"
    echo "规则 [$RULE_NAME] 配置失败，请检查报错信息。"
fi