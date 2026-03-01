#!/bin/bash

# --- 配置区域 ---
RULES_FILE="rule-definitions.csv"
MAPPING_FILE="nsg-mapping.csv"

# 临时文件用于存放安全的格式
RULES_TSV=$(mktemp)
MAPPING_TSV=$(mktemp)

# 关闭通配符扩展
set -f

echo -e "\e[36m=====================================================\e[0m"
echo -e "\e[36m     Azure NSG 批量同步工具 (纯 Bash/Awk 版)\e[0m"
echo -e "\e[36m=====================================================\e[0m"
echo ""

if [[ ! -f "$RULES_FILE" || ! -f "$MAPPING_FILE" ]]; then
    echo -e "\e[31m[ERROR] 找不到 CSV 文件，请确保 $RULES_FILE 和 $MAPPING_FILE 存在。\e[0m"
    exit 1
fi

echo -e "\e[34m[INFO] 正在读取并解析 CSV 文件...\e[0m"

# 1. 使用原生 awk 安全解析 CSV (替代 Python)
# 这是一个微型状态机：它能识别双引号内的逗号和换行符，去除多余空格和引号，并转换为 \t 分隔
awk_parser='
function trim(s) {
    sub(/^[ \t]+/, "", s);
    sub(/[ \t]+$/, "", s);
    return s;
}
BEGIN { 
    FS="" 
    in_quote = 0
    field = ""
    out = ""
}
{
    # 如果继承了上一行的引号状态，说明这是单元格内部的换行。
    # 我们将换行符替换为一个空格，确保最终输出的是单行的 TSV 数据。
    if (in_quote) {
        field = field " "
    }
    
    for(i=1; i<=length($0); i++) {
        c = substr($0, i, 1)
        if (c == "\"") {
            in_quote = !in_quote
        } else if (c == "," && !in_quote) {
            out = out trim(field) "\t"
            field = ""
        } else if (c == "\r") {
            # 跳过 Windows 格式的回车符
        } else {
            field = field c
        }
    }
    
    # 如果到达行尾，并且不在引号内部，说明一条完整的 CSV 记录已经结束
    if (!in_quote) {
        out = out trim(field)
        print out
        # 重置状态以读取下一条记录
        field = ""
        out = ""
    }
}'

awk "$awk_parser" "$RULES_FILE" > "$RULES_TSV"
awk "$awk_parser" "$MAPPING_FILE" > "$MAPPING_TSV"

# 声明关联数组
declare -A r_pri r_dir r_acc r_proto r_src r_src_port r_dest r_dest_port r_desc
declare -A nsg_rg
declare -A desired_rules_in_nsg

# 2. 读取规则定义 (使用制表符分割)
while IFS=$'\t' read -r code pri dir acc proto src src_port dest dest_port desc || [ -n "$code" ]; do
    # 使用通配符匹配跳过表头，免疫可能存在的 BOM 隐藏字符
    [[ -z "$code" || "$code" == *"RuleCode"* ]] && continue
    
    # 存入数组（将源/目标中的逗号替换为空格，这是 Azure CLI 支持的多 IP 格式）
    r_pri["$code"]=$pri
    r_dir["$code"]=$dir
    r_acc["$code"]=$acc
    r_proto["$code"]=$proto
    r_src["$code"]="${src//,/ }"
    r_src_port["$code"]="${src_port//,/ }"
    r_dest["$code"]="${dest//,/ }"
    r_dest_port["$code"]="${dest_port//,/ }"
    r_desc["$code"]="$desc"
done < "$RULES_TSV"

echo -e "\e[32m[INFO] 规则加载完成。\e[0m\n"

# 3. 读取映射表，按 NSG 汇总“期望存在的规则”
while IFS=$'\t' read -r nsg rg code || [ -n "$nsg" ]; do
    # 使用通配符匹配跳过表头，免疫可能存在的 BOM 隐藏字符
    [[ -z "$nsg" || "$nsg" == *"NsgName"* ]] && continue
    
    # 记录该 NSG 所属的资源组
    nsg_rg["$nsg"]="$rg"
    # 将该 NSG 期望的规则代码拼接到字符串中（用空格包围，方便后续精确匹配）
    desired_rules_in_nsg["$nsg"]="${desired_rules_in_nsg["$nsg"]} $code "
done < "$MAPPING_TSV"

# 4. 开始按 NSG 执行同步逻辑 (增、删、改)
for nsg in "${!nsg_rg[@]}"; do
    rg="${nsg_rg[$nsg]}"
    desired_str="${desired_rules_in_nsg[$nsg]}"
    
    echo "--------------------------------------------------"
    echo -e "\e[33m[INFO] 开始同步 NSG: $nsg (资源组: $rg)\e[0m"

    # --- 阶段 0: 预先校验优先级冲突 ---
    unset pri_dir_check
    declare -A pri_dir_check
    conflict=false
    for code in $desired_str; do
        if [[ -z "${r_pri["$code"]}" ]]; then continue; fi
        pri_val="${r_pri[$code]}"
        dir_val="${r_dir[$code]}"
        # 将方向和优先级组合成一个唯一的键，例如 "Inbound_100"
        key="${dir_val}_${pri_val}"
        
        if [[ -n "${pri_dir_check[$key]}" ]]; then
            echo -e "\e[31m[ERROR] 预检失败：规则冲突！\e[0m"
            echo -e "\e[31m        规则 '$code' 与 '${pri_dir_check[$key]}' 具有相同的方向 ($dir_val) 和优先级 ($pri_val)。\e[0m"
            conflict=true
        else
            pri_dir_check[$key]="$code"
        fi
    done

    if [ "$conflict" = true ]; then
        echo -e "\e[31m[ERROR] 请修改 rule-definitions.csv 以确保每个 NSG 内的规则优先级唯一。已安全跳过该 NSG 的同步。\e[0m"
        continue
    fi

    # 获取 Azure 端当前的所有自定义规则名称
    current_rules=$(az network nsg rule list -g "$rg" --nsg-name "$nsg" --query "[].name" -o tsv 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo -e "\e[31m[ERROR] 无法获取 NSG [$nsg] 的信息，可能不存在或无权限，跳过。\e[0m"
        continue
    fi
    
    # 【关键修复】将换行符替换为空格，解决多条规则时的正则表达式匹配失败问题
    current_rules=$(echo "$current_rules" | tr '\n' ' ' | tr '\r' ' ')

    # --- 阶段 A: 删除 ---
    # 遍历当前 Azure 中的规则，如果不在 CSV 的期望列表中，则删除它
    for c_rule in $current_rules; do
        # 跳过空字符串
        [[ -z "$c_rule" ]] && continue
        
        if [[ ! "$desired_str" =~ " $c_rule " ]]; then
            echo -e "\e[31m -> [删除] 发现多余规则: $c_rule (CSV中已移除，正在从 Azure 中删除...)\e[0m"
            az network nsg rule delete -g "$rg" --nsg-name "$nsg" -n "$c_rule" > /dev/null
        fi
    done

    # --- 阶段 B: 新增 / 更新 ---
    # 遍历 CSV 中期望的规则
    for code in $desired_str; do
        # 验证规则在 rule-definitions.csv 中是否定义
        if [[ -z "${r_pri["$code"]}" ]]; then
            echo -e "\e[31m -> [跳过] 找不到代号为 '$code' 的详细规则定义。\e[0m"
            continue
        fi

        # 判断 Azure 当前是否已有此规则
        if [[ " $current_rules " =~ " $code " ]]; then
            echo -e "\e[90m -> [更新] 覆写规则: $code\e[0m"
            az network nsg rule update -g "$rg" --nsg-name "$nsg" -n "$code" \
                --priority "${r_pri[$code]}" \
                --direction "${r_dir[$code]}" \
                --access "${r_acc[$code]}" \
                --protocol "${r_proto[$code]}" \
                --source-address-prefixes ${r_src[$code]} \
                --source-port-ranges ${r_src_port[$code]} \
                --destination-address-prefixes ${r_dest[$code]} \
                --destination-port-ranges ${r_dest_port[$code]} \
                --description "${r_desc[$code]}" > /dev/null
        else
            echo -e "\e[32m -> [新增] 创建规则: $code\e[0m"
            az network nsg rule create -g "$rg" --nsg-name "$nsg" -n "$code" \
                --priority "${r_pri[$code]}" \
                --direction "${r_dir[$code]}" \
                --access "${r_acc[$code]}" \
                --protocol "${r_proto[$code]}" \
                --source-address-prefixes ${r_src[$code]} \
                --source-port-ranges ${r_src_port[$code]} \
                --destination-address-prefixes ${r_dest[$code]} \
                --destination-port-ranges ${r_dest_port[$code]} \
                --description "${r_desc[$code]}" > /dev/null
        fi
    done
    
    echo -e "\e[32m > NSG [$nsg] 同步完成。\e[0m"
done

# 清理工作
rm -f "$RULES_TSV" "$MAPPING_TSV"
set +f

echo -e "\e[36m=====================================================\e[0m"
echo -e "\e[32m[INFO] 所有配置应用完毕！\e[0m"
echo -e "\e[36m=====================================================\e[0m"