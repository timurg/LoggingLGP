#!/bin/bash

# Название образа и тег
IMAGE_NAME="monitoring-stack-lfg"
TAG="latest"
FULL_IMAGE_NAME="docker.io/timurg/${IMAGE_NAME}:${TAG}"

# Функция для вывода сообщений об ошибках
error_exit() {
    echo "Ошибка: $1" >&2
    exit 1
}

# Проверка наличия Dockerfile
if [ ! -f "Dockerfile" ]; then
    error_exit "Dockerfile не найден в текущей директории."
fi

# Проверка наличия конфигурационных файлов
if [ ! -f "loki-etc/local-config.yaml" ] || [ ! -f "fluent-config/local.conf" ]; then
    error_exit "Конфигурационные файлы loki-etc/local-config.yaml или fluent-config/local.conf не найдены."
fi

# Проверка, что grafana.ini не является директорией
if [ -d "grafana.ini" ]; then
    error_exit "grafana.ini является директорией. Удалите её с помощью 'rm -rf grafana.ini' и создайте файл."
fi

# Проверка входных аргументов
if [ $# -gt 1 ]; then
    error_exit "Использование: $0 [тег_образа]"
fi

# Если тег передан, используем его
if [ $# -eq 1 ]; then
    TAG="$1"
    FULL_IMAGE_NAME="docker.io/timurg/${IMAGE_NAME}:${TAG}"
fi

echo "Сборка образа ${FULL_IMAGE_NAME}..."

# Сборка Docker-образа
docker build -t "${FULL_IMAGE_NAME}" . || error_exit "Не удалось собрать образ."

# Сканирование образа на уязвимости с помощью Trivy
echo "Сканирование образа на уязвимости..."
if ! command -v trivy &> /dev/null; then
    echo "Trivy не установлен. Установите Trivy для проверки уязвимостей: https://aquasecurity.github.io/trivy"
else
    trivy image --exit-code 1 --severity HIGH,CRITICAL "${FULL_IMAGE_NAME}" || echo "Внимание: найдены уязвимости, проверьте вывод Trivy."
fi

echo "Создание grafana.ini для локального тестирования..."
cat <<EOF > grafana.ini
[security]
admin_password = mysecretpassword
EOF

# Проверка и удаление существующего контейнера
if docker ps -a --filter "name=monitoring-stack-lfg" -q | grep -q .; then
    echo "Контейнер monitoring-stack-lfg уже существует. Останавливаем и удаляем..."
    docker stop monitoring-stack-lfg >/dev/null
    docker rm monitoring-stack-lfg >/dev/null
fi

echo "Запуск контейнера для локального тестирования..."

# Запуск контейнера
docker run -d \
    --name monitoring-stack-lfg \
    -p 3000:3000 \
    -p 24224:24224 \
    -p 24224:24224/udp \
    -v loki-data:/loki \
    -v grafana-data:/var/lib/grafana \
    -v $(pwd)/grafana.ini:/etc/grafana/grafana.ini \
    -e LOKI_RETENTION_PERIOD="168h" \
    -e FLUENTBIT_LOG_LEVEL="info" \
    "${FULL_IMAGE_NAME}" || error_exit "Не удалось запустить контейнер."

echo "Контейнер запущен. Проверка статуса сервисов..."

# Ожидание запуска сервисов (30 секунд)
sleep 30

# Проверка статуса сервисов через логи Supervisor
echo "Логи контейнера:"
docker logs monitoring-stack-lfg

echo "Проверка доступности сервисов..."
echo "Grafana: http://localhost:3000 (логин: admin, пароль: mysecretpassword)"
echo "Loki: http://localhost:3100/ready"
echo "Fluent-bit: порт 24224 (TCP/UDP)"

# Проверка healthcheck
if curl -f http://localhost:3100/ready >/dev/null; then
    echo "Loki: OK"
else
    echo "Loki: Ошибка, проверьте логи контейнера."
    echo "Логи Loki:"
    docker logs monitoring-stack-lfg 2>&1 | grep loki
    echo "Логи ошибок Loki:"
    docker exec monitoring-stack-lfg cat /var/log/supervisor/loki.err.log || echo "Логи ошибок Loki недоступны."
fi

if curl -f http://localhost:3000/api/health >/dev/null; then
    echo "Grafana: OK"
else
    echo "Grafana: Ошибка, проверьте логи контейнера."
    echo "Логи Grafana:"
    docker logs monitoring-stack-lfg 2>&1 | grep grafana
    echo "Логи ошибок Grafana:"
    docker exec monitoring-stack-lfg cat /var/log/supervisor/grafana.err.log || echo "Логи ошибок Grafana недоступны."
fi

# Проверка Fluent-bit
echo "Отправка тестового лога на порт 24224..."
echo '{"message": "test log"}' | nc localhost 24224 >/dev/null
if [ $? -eq 0 ]; then
    echo "Fluent-bit: OK (тестовый лог отправлен)"
else
    echo "Fluent-bit: Ошибка, проверьте логи контейнера."
    echo "Логи Fluent-bit:"
    docker logs monitoring-stack-lfg 2>&1 | grep fluent-bit
    echo "Логи ошибок Fluent-bit:"
    docker exec monitoring-stack-lfg cat /var/log/supervisor/fluent-bit.err.log || echo "Логи ошибок Fluent-bit недоступны."
fi

echo "Тестирование завершено. Для просмотра логов используйте: docker logs monitoring-stack-lfg"
echo "Для остановки контейнера: docker stop monitoring-stack-lfg"
echo "Для удаления контейнера: docker rm monitoring-stack-lfg"