#!/bin/bash

# mssh - 交互式服务器连接工具
# 版本：1.0
# 功能：带搜索、分组和标记的服务器管理

# 配置文件路径
CONFIG_DIR="$HOME/.config"
CONFIG_FILE="$CONFIG_DIR/mssh.conf"
TAGS_FILE="$CONFIG_DIR/tags.conf"
HISTORY_FILE="$CONFIG_DIR/history.log"

# 创建必要目录和文件
mkdir -p "$CONFIG_DIR"
touch "$CONFIG_FILE"
touch "$TAGS_FILE"
touch "$HISTORY_FILE"

# 初始化默认配置（如果文件为空）
if [ ! -s "$CONFIG_FILE" ]; then
	cat >"$CONFIG_FILE" <<EOF
# 服务器配置格式：
# 别名|用户名|密码|主机/IP|端口|标签(可选)
#
# 示例：
# web01|admin|P@ssw0rd1|192.168.1.101|22|生产,重要
# db01|root|MyS3cret!|10.0.0.55|2222|生产,数据库
# backup|backup|simplepass|backup.example.com|22|备份
# dev01|deploy|d3ployKey!|172.16.8.42|22|开发
#
# 分组使用空行分隔：
# [开发环境]
# dev02|devuser|devpass|192.168.2.10|22|开发
#
# [测试环境]
# test01|tester|testpass|192.168.3.20|22|测试
EOF
	echo "已创建初始配置文件: $CONFIG_FILE"
	echo "请编辑该文件添加服务器信息"
	exit 0
fi

# 显示标题
show_header() {
	clear
	echo "=============================================="
	echo "  服务器管理工具 (v1.0) - 共 $(grep -vE '^#|^$|^\[' "$CONFIG_FILE" | wc -l) 台服务器"
	echo "=============================================="
}

# 显示菜单选项
show_menu() {
	echo "请选择操作:"
	echo " 1) 连接服务器"
	echo " 2) 搜索服务器"
	echo " 3) 按标签筛选"
	echo " 4) 显示历史记录"
	echo " 5) 编辑服务器配置"
	echo " 6) 管理标签"
	echo " 7) 退出"
	echo "----------------------------------------------"
	echo -n "请输入选择 (1-7): "
}

# 显示服务器列表
display_servers() {
	local config="$1"
	local counter=1
	local current_group=""

	while IFS= read -r line; do
		# 处理分组标题
		if [[ "$line" =~ ^\[(.*)\]$ ]]; then
			current_group="${BASH_REMATCH[1]}"
			echo ""
			echo "===== ${current_group} ====="
			continue
		fi

		# 跳过注释和空行
		[[ "$line" == \#* ]] || [ -z "$line" ] && continue

		# 解析服务器配置
		IFS='|' read -r alias user pass host port tags <<<"$line"

		# 设置默认值
		port=${port:-22}
		tags=${tags:-无标签}

		# 显示服务器信息
		if [ -z "$current_group" ]; then
			printf "%2d) %-15s - %s@%s:%s [%s]\n" "$counter" "$alias" "$user" "$host" "$port" "$tags"
		else
			printf "%2d) [%-10s] %-15s - %s@%s:%s [%s]\n" "$counter" "$current_group" "$alias" "$user" "$host" "$port" "$tags"
		fi

		# 保存到临时菜单文件
		echo "$counter|$alias|$user|$pass|$host|$port|$tags" >>"$TMP_MENU"

		((counter++))
	done <"$config"

	echo "----------------------------------------------"
	echo -n "输入选择 (1-$((counter - 1)), b返回主菜单: "
}

# 连接服务器
connect_server() {
	IFS='|' read -r num alias user pass host port tags <<<"$1"

	# 记录连接历史
	timestamp=$(date +"%Y-%m-%d %H:%M:%S")
	echo "$timestamp|$user@$host:$port ($alias)" >>"$HISTORY_FILE"

	# 使用expect自动登录
	echo "正在连接: $user@$host:$port ($alias)..."
	expect -c "
  set timeout 15
  spawn ssh -p $port $user@$host
  expect {
      \"yes/no\" { send \"yes\r\"; exp_continue }
      \"*password:\" { send \"$pass\r\" }
      timeout { send_user \"连接超时，请检查网络或服务器状态\n\"; exit 1 }
  }
  interact
  "
}

# 搜索服务器
search_servers() {
	show_header
	echo "搜索服务器 (按别名、主机、用户或标签搜索)"
	echo "----------------------------------------------"
	echo -n "输入搜索关键词 (或按回车返回): "
	read search_term

	[ -z "$search_term" ] && return

	# 创建临时配置文件用于搜索结果
	TMP_SEARCH=$(mktemp)
	grep -iE "$search_term" "$CONFIG_FILE" >"$TMP_SEARCH"

	if [ ! -s "$TMP_SEARCH" ]; then
		echo "未找到匹配的服务器"
		read -n1 -p "按任意键返回..."
		rm -f "$TMP_SEARCH"
		return
	fi

	TMP_MENU=$(mktemp)
	show_header
	echo "搜索结果: \"$search_term\""
	display_servers "$TMP_SEARCH"

	while true; do
		read choice

		[ "$choice" == "b" ] && break

		if [[ "$choice" =~ ^[0-9]+$ ]]; then
			selected=$(awk -F'|' -v choice="$choice" '$1 == choice {print $0}' "$TMP_MENU")
			if [ -n "$selected" ]; then
				rm -f "$TMP_SEARCH" "$TMP_MENU"
				connect_server "$selected"
				return
			fi
		fi

		echo -n "无效选择，请重新输入: "
	done

	rm -f "$TMP_SEARCH" "$TMP_MENU"
}

# 按标签筛选
filter_by_tag() {
	# 提取所有标签
	all_tags=$(grep -vE '^#|^$|^\[' "$CONFIG_FILE" | awk -F'|' '{print $6}' | tr ',' '\n' | sort | uniq | grep -v '^$')

	if [ -z "$all_tags" ]; then
		show_header
		echo "没有可用的标签"
		read -n1 -p "按任意键返回..."
		return
	fi

	show_header
	echo "可用的标签:"
	echo "----------------------------------------------"

	# 显示标签菜单
	tag_counter=1
	declare -A tag_map
	for tag in $all_tags; do
		echo "$tag_counter) $tag"
		tag_map[$tag_counter]=$tag
		((tag_counter++))
	done

	echo "----------------------------------------------"
	echo -n "选择标签 (1-$((tag_counter - 1)), b返回): "

	read tag_choice
	[ "$tag_choice" == "b" ] && return

	if [[ "$tag_choice" =~ ^[0-9]+$ ]] && [ "$tag_choice" -ge 1 ] && [ "$tag_choice" -lt $tag_counter ]; then
		selected_tag=${tag_map[$tag_choice]}

		# 创建临时配置文件用于标签结果
		TMP_TAG=$(mktemp)
		grep -i "$selected_tag" "$CONFIG_FILE" >"$TMP_TAG"

		if [ ! -s "$TMP_TAG" ]; then
			echo "没有找到标签为 '$selected_tag' 的服务器"
			read -n1 -p "按任意键返回..."
			rm -f "$TMP_TAG"
			return
		fi

		TMP_MENU=$(mktemp)
		show_header
		echo "标签: $selected_tag"
		display_servers "$TMP_TAG"

		while true; do
			read choice

			[ "$choice" == "b" ] && break

			if [[ "$choice" =~ ^[0-9]+$ ]]; then
				selected=$(awk -F'|' -v choice="$choice" '$1 == choice {print $0}' "$TMP_MENU")
				if [ -n "$selected" ]; then
					rm -f "$TMP_TAG" "$TMP_MENU"
					connect_server "$selected"
					return
				fi
			fi

			echo -n "无效选择，请重新输入: "
		done

		rm -f "$TMP_TAG" "$TMP_MENU"
	else
		echo "无效选择"
		read -n1 -p "按任意键返回..."
	fi
}

# 显示连接历史
show_history() {
	show_header
	echo "最近连接历史:"
	echo "----------------------------------------------"
	tail -n 10 "$HISTORY_FILE" | awk -F'|' '{printf "%-19s %s\n", $1, $2}'
	echo "----------------------------------------------"
	read -n1 -p "按任意键返回..."
}

# 编辑服务器配置
edit_config() {
	show_header
	echo "编辑服务器配置"
	echo "----------------------------------------------"
	echo "将在默认编辑器中打开配置文件:"
	echo "$CONFIG_FILE"
	echo "----------------------------------------------"
	read -n1 -p "按任意键继续 (Ctrl+C取消)..."

	# 检测可用编辑器
	for editor in "$EDITOR" nano vim vi; do
		if command -v "$editor" >/dev/null; then
			"$editor" "$CONFIG_FILE"
			return
		fi
	done

	echo "未找到可用的文本编辑器!"
}

# 管理标签
manage_tags() {
	while true; do
		show_header
		echo "标签管理"
		echo "----------------------------------------------"
		echo "1) 查看所有标签"
		echo "2) 重命名标签"
		echo "3) 删除标签"
		echo "4) 返回主菜单"
		echo "----------------------------------------------"
		echo -n "请选择操作 (1-4): "

		read tag_op
		case $tag_op in
		1)
			show_header
			echo "所有标签:"
			echo "----------------------------------------------"
			grep -vE '^#|^$|^\[' "$CONFIG_FILE" | awk -F'|' '{print $6}' | tr ',' '\n' | sort | uniq | grep -v '^$' | awk '{print " - " $0}'
			echo "----------------------------------------------"
			read -n1 -p "按任意键继续..."
			;;
		2)
			show_header
			echo "重命名标签"
			echo "----------------------------------------------"
			echo -n "输入原标签名: "
			read old_tag
			echo -n "输入新标签名: "
			read new_tag

			if [ -n "$old_tag" ] && [ -n "$new_tag" ]; then
				# 更新配置文件
				sed -i "s/\(.*|.*|.*|.*|.*|.*\)$old_tag\(.*\)/\1$new_tag\2/g" "$CONFIG_FILE"
				sed -i "s/\(.*|.*|.*|.*|.*|.*\)$old_tag,\(.*\)/\1$new_tag,\2/g" "$CONFIG_FILE"
				sed -i "s/\(.*|.*|.*|.*|.*|.*\),$old_tag\(.*\)/\1,$new_tag\2/g" "$CONFIG_FILE"
				echo "标签已更新: '$old_tag' -> '$new_tag'"
			else
				echo "无效输入"
			fi
			read -n1 -p "按任意键继续..."
			;;
		3)
			show_header
			echo "删除标签"
			echo "----------------------------------------------"
			echo -n "输入要删除的标签名: "
			read del_tag

			if [ -n "$del_tag" ]; then
				# 从所有服务器中删除该标签
				sed -i "s/\(.*|.*|.*|.*|.*|.*\)$del_tag\(.*\)/\1\2/g" "$CONFIG_FILE"
				sed -i "s/\(.*|.*|.*|.*|.*|.*\)$del_tag,\(.*\)/\1\2/g" "$CONFIG_FILE"
				sed -i "s/\(.*|.*|.*|.*|.*|.*\),$del_tag\(.*\)/\1\2/g" "$CONFIG_FILE"
				echo "标签 '$del_tag' 已从所有服务器中删除"
			else
				echo "无效输入"
			fi
			read -n1 -p "按任意键继续..."
			;;
		4)
			return
			;;
		*)
			echo "无效选择"
			;;
		esac
	done
}

# 主程序
while true; do
	show_header
	show_menu

	read main_choice
	case $main_choice in
	1)
		# 连接服务器
		TMP_MENU=$(mktemp)
		show_header
		display_servers "$CONFIG_FILE"

		while true; do
			read choice

			[ "$choice" == "b" ] && break

			if [[ "$choice" =~ ^[0-9]+$ ]]; then
				selected=$(awk -F'|' -v choice="$choice" '$1 == choice {print $0}' "$TMP_MENU")
				if [ -n "$selected" ]; then
					rm -f "$TMP_MENU"
					connect_server "$selected"
					break
				fi
			fi

			echo -n "无效选择，请重新输入: "
		done
		rm -f "$TMP_MENU"
		;;

	2)
		# 搜索服务器
		search_servers
		;;

	3)
		# 按标签筛选
		filter_by_tag
		;;

	4)
		# 显示历史记录
		show_history
		;;

	5)
		# 编辑配置
		edit_config
		;;

	6)
		# 管理标签
		manage_tags
		;;

	7)
		# 退出
		echo ""
		echo "感谢使用mssh!"
		exit 0
		;;

	*)
		echo "无效选择"
		sleep 1
		;;
	esac
done
