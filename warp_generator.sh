#!/bin/bash

# Очистка экрана (необязательно)
clear

# Создание директории для работы без предупреждений
mkdir -p ~/.cloudshell && touch ~/.cloudshell/no-apt-get-warning

# Убедимся, что WireGuard установлен
if ! dpkg -l | grep -q wireguard-tools; then
    echo "Установка WireGuard..."
    sudo apt-get update -y --fix-missing && sudo apt-get install wireguard-tools -y --fix-missing
else
    echo "WireGuard уже установлен."
fi

# Генерация приватного и публичного ключей
priv="${1:-$(wg genkey)}"
pub="${2:-$(echo "${priv}" | wg pubkey)}"

# Cloudflare API для регистрации клиента
api="https://api.cloudflareclient.com/v0i1909051800"

# Функция для выполнения безопасных HTTP-запросов через curl
ins() {
    curl -s -H 'user-agent:' -H 'content-type: application/json' -X "$1" "${api}/$2" "${@:3}" || {
        echo "Ошибка при подключении к API." >&2
        exit 1
    }
}

# Функция для запроса с авторизацией
sec() {
    ins "$1" "$2" -H "authorization: Bearer $3" "${@:4}"
}

# Регистрация нового клиента через API
response=$(ins POST "reg" -d "{\"install_id\":\"\",\"tos\":\"$(date -u +%FT%T.000Z)\",\"key\":\"${pub}\",\"fcm_token\":\"\",\"type\":\"ios\",\"locale\":\"en_US\"}")
id=$(echo "$response" | jq -r '.result.id')
token=$(echo "$response" | jq -r '.result.token')

# Обновление конфигурации клиента и получение данных о пире
response=$(sec PATCH "reg/${id}" "$token" -d '{"warp_enabled":true}')
peer_pub=$(echo "$response" | jq -r '.result.config.peers[0].public_key')
peer_endpoint=$(echo "$response" | jq -r '.result.config.peers[0].endpoint.host')
client_ipv4=$(echo "$response" | jq -r '.result.config.interface.addresses.v4')
client_ipv6=$(echo "$response" | jq -r '.result.config.interface.addresses.v6')

# Извлечение порта и изменения адреса пира на зафиксированный IP
port=$(echo "$peer_endpoint" | sed 's/.*:\([0-9]*\)$/\1/')
peer_endpoint=$(echo "$peer_endpoint" | sed 's/\(.*\):[0-9]*/162.159.193.5/')

# Формирование конфигурации WireGuard
conf=$(cat <<-EOM
[Interface]
PrivateKey = ${priv}
Address = ${client_ipv4}, ${client_ipv6}
DNS = 1.1.1.1, 2606:4700:4700::1111, 1.0.0.1, 2606:4700:4700::1001

[Peer]
PublicKey = ${peer_pub}
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = ${peer_endpoint}:${port}
EOM
)

# Проверка, поддерживает ли терминал вывод (чтобы не выводить конфигурацию в открытый терминал)
if [ -t 1 ]; then
    echo "########## НАЧАЛО КОНФИГА ##########"
    echo "${conf}"
    echo "########### КОНЕЦ КОНФИГА ###########"
else
    echo "Конфигурация не выведена, так как терминал не поддерживает безопасный вывод."
fi

# Сохранение конфигурации в файл с безопасными правами доступа
config_path="$HOME/WARP.conf"
echo "${conf}" > "${config_path}"
chmod 600 "${config_path}"  # Только владелец может читать файл
echo "Конфигурация сохранена в файл: ${config_path}"

# Окончание работы
echo "WireGuard конфигурация успешно создана и сохранена."
