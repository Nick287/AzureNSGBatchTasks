# 1. 登录 Azure 账号
az login

# 2. 查看当前默认生效的订阅信息
az account show

# 3. 列出所有关联订阅，确认 ID 或名称
az account list --output table

# 只获取当前订阅的名称：
az account show --query name -o tsv

# 只获取当前订阅的 ID：
az account show --query id -o tsv

# 4. 切换到指定的订阅
# 请将 "你的订阅ID" 替换为实际的 UUID 或订阅名称
az account set --subscription "你的订阅ID"

# 模板命令
# 参数说明：
# -g：资源组名称
# --nsg-name：NSG（网络安全组）名称
# -n：规则名称
# --priority：规则优先级，数值越小优先级越高，范围为 100-4096
# --source-address-prefixes：源地址前缀，可以是 IP 地址、CIDR 块或服务标签
# --destination-address-prefixes：目的地址前缀，可以是 IP 地址、CIDR 块或服务标签
# --source-port-ranges：源端口范围，可以是单个端口、端口范围或 '*'
# --destination-port-ranges：目的端口范围，可以是单个端口、端口范围或 '*'
# --protocol：协议类型，可以是 Tcp、Udp 或 '*'
# --access：访问类型，可以是 Allow 或 Deny
# --direction：规则方向，可以是 Inbound 或 Outbound
az network nsg rule create -g <您的资源组名称> --nsg-name <您的NSG名称> -n <规则名称> --priority 1000 --source-address-prefixes 1.1.1.1 2.2.2.2 --destination-address-prefixes '*' --source-port-ranges '*' --destination-port-ranges '*' --protocol '*' --access Allow --direction Inbound

# 示例命令
az network nsg rule create -g mysql-rg --nsg-name mysql-rg-vnet-default-nsg-centralus -n rule001 --priority 1000 --source-address-prefixes 1.1.1.1 2.2.2.2 --destination-address-prefixes '*' --source-port-ranges '*' --destination-port-ranges '*' --protocol '*' --access Allow --direction Inbound --description "允许临时白名单IP访问所有端口进行测试"

# 运行结果
vscode ➜ /workspaces/AzureNSGBatchTasks (main) $ az network nsg rule create -g mysql-rg --nsg-name mysql-rg-vnet-default-nsg-centralus -n rule001 --priority 1000 --source-address-prefixes 1.1.1.1 2.2.2.2 --destination-address-prefixes '*' --source-port-ranges '*' --destination-port-ranges '*' --protocol '*' --access Allow --direction Inbound --description "允许临时白名 单IP访问所有端口进行测试"
{
  "access": "Allow",
  "description": "允许临时白名单IP访问所有端口进行测试",
  "destinationAddressPrefix": "*",
  "destinationAddressPrefixes": [],
  "destinationPortRange": "*",
  "destinationPortRanges": [],
  "direction": "Inbound",
  "etag": "W/\"fdada37f-70c6-46a9-bd38-89ca1bd87c37\"",
  "id": "/subscriptions/655bd0bc-917a-4852-a52c-4b6d43704bc1/resourceGroups/mysql-rg/providers/Microsoft.Network/networkSecurityGroups/mysql-rg-vnet-default-nsg-centralus/securityRules/rule001",
  "name": "rule001",
  "priority": 1000,
  "protocol": "*",
  "provisioningState": "Succeeded",
  "resourceGroup": "mysql-rg",
  "sourceAddressPrefixes": [
    "1.1.1.1",
    "2.2.2.2"
  ],
  "sourcePortRange": "*",
  "sourcePortRanges": [],
  "type": "Microsoft.Network/networkSecurityGroups/securityRules"
}