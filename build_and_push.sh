#!/bin/bash

# Название образа и тег
IMAGE_NAME="monitoring-stack-lfg"
TAG="latest"
REGISTRY="docker.io"
REPO="timurg"

# Полное имя образа
FULL_IMAGE_NAME="${REGISTRY}/${REPO}/${IMAGE_NAME}:${TAG}"

# Функция для вывода сообщений об ошибках
error_exit() {
    echo "Ошибка: $1" >&2
    exit 1
}

# Проверка, авторизован ли пользователь в реестре
check_docker_login() {
    if ! docker info --format '{{.IndexServerAddress}}' | grep -q "${REGISTRY}"; then
        echo "Выполните 'docker login ${REGISTRY}' для авторизации в реестре."
        exit 1
    fi
}

# Проверка наличия Dockerfile
if [ ! -f "Dockerfile" ]; then
    error_exit "Dockerfile не найден в текущей директории."
fi

# Проверка входных аргументов
if [ $# -gt 1 ]; then
    error_exit "Использование: $0 [тег_образа]"
fi

# Если тег передан, используем его
if [ $# -eq 1 ]; then
    TAG="$1"
    FULL_IMAGE_NAME="${REGISTRY}/${REPO}/${IMAGE_NAME}:${TAG}"
fi

echo "Сборка образа ${FULL_IMAGE_NAME}..."

# Сборка Docker-образа
docker build -t "${FULL_IMAGE_NAME}" . || error_exit "Не удалось собрать образ."

# Сканирование образа на уязвимости с помощью Trivy
echo "Сканирование образа на уязвимости..."
docker run --rm aquasec/trivy image --exit-code 1 --severity HIGH,CRITICAL "${FULL_IMAGE_NAME}" || echo "Внимание: найдены уязвимости, проверьте вывод Trivy."

# Проверка авторизации в реестре
check_docker_login

echo "Публикация образа ${FULL_IMAGE_NAME} в реестр..."

# Пуш образа в реестр
docker push "${FULL_IMAGE_NAME}" || error_exit "Не удалось опубликовать образ."

echo "Образ ${FULL_IMAGE_NAME} успешно собран и опубликован."