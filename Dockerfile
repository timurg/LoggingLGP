FROM ubuntu:22.04

# Установка необходимых зависимостей
RUN apt-get update && apt-get install -y \
    supervisor \
    wget \
    unzip \
    curl \
    gnupg \
    lsb-release \
    adduser \
    libfontconfig1 \
    musl \
    libz-dev \
    libc6 \
    && rm -rf /var/lib/apt/lists/*

# Создание non-root пользователя
RUN adduser --disabled-password --gecos "" --uid 1000 appuser \
    && mkdir -p /loki/chunks /loki/index /loki/cache /var/lib/grafana /etc/loki /etc/fluent-bit /etc/grafana/provisioning/datasources /etc/grafana /var/log/supervisor \
    && chown -R appuser:appuser /loki /var/lib/grafana /etc/loki /etc/fluent-bit /etc/grafana /var/log/supervisor \
    && rm -rf /etc/grafana/grafana.ini

# Установка Fluent-bit через APT (для Ubuntu)
RUN curl https://packages.fluentbit.io/fluentbit.key | gpg --dearmor > /usr/share/keyrings/fluentbit-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/fluentbit-keyring.gpg] https://packages.fluentbit.io/ubuntu/$(lsb_release -cs) $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/fluent-bit.list \
    && apt-get update \
    && apt-get install -y fluent-bit \
    && rm -rf /var/lib/apt/lists/*

# Установка Grafana
RUN wget https://dl.grafana.com/oss/release/grafana_12.1.1_amd64.deb \
    && dpkg -i grafana_12.1.1_amd64.deb \
    && rm grafana_12.1.1_amd64.deb

# Установка Loki
RUN wget https://github.com/grafana/loki/releases/download/v3.5.0/loki-linux-amd64.zip \
    && unzip loki-linux-amd64.zip \
    && mv loki-linux-amd64 /usr/bin/loki \
    && chmod +x /usr/bin/loki \
    && rm loki-linux-amd64.zip

# Копирование конфигураций
COPY loki-etc/local-config.yaml /etc/loki/local-config.yaml
COPY fluent-config/local.conf /etc/fluent-bit/local.conf

# Настройка конфигураций для локального запуска
RUN sed -i 's/instance_addr: loki/instance_addr: 127.0.0.1/' /etc/loki/local-config.yaml \
    && sed -i 's/Host loki/Host 127.0.0.1/' /etc/fluent-bit/local.conf \
    && chown appuser:appuser /etc/loki/local-config.yaml /etc/fluent-bit/local.conf

# Настройка Grafana datasource для Loki
COPY <<EOF /etc/grafana/provisioning/datasources/loki.yaml
apiVersion: 1
datasources:
  - name: Loki
    type: loki
    access: proxy
    url: http://127.0.0.1:3100
    jsonData:
      maxLines: 1000
EOF
RUN chown appuser:appuser /etc/grafana/provisioning/datasources/loki.yaml

# Настройка Supervisor
COPY <<EOF /etc/supervisor/supervisord.conf
[supervisord]
nodaemon=true
user=appuser
logfile=/var/log/supervisor/supervisord.log
pidfile=/var/run/supervisord.pid
logfile_maxbytes=10MB
logfile_backups=3

[program:loki]
command=/usr/bin/loki -config.file=/etc/loki/local-config.yaml
user=appuser
autostart=true
autorestart=true
stderr_logfile=/var/log/supervisor/loki.err.log
stdout_logfile=/var/log/supervisor/loki.out.log
logfile_maxbytes=10MB
logfile_backups=3

[program:grafana]
command=/usr/sbin/grafana-server --homepath=/usr/share/grafana --config=/etc/grafana/grafana.ini
user=appuser
autostart=true
autorestart=true
stderr_logfile=/var/log/supervisor/grafana.err.log
stdout_logfile=/var/log/supervisor/grafana.out.log
logfile_maxbytes=10MB
logfile_backups=3

[program:fluent-bit]
command=/opt/fluent-bit/bin/fluent-bit -c /etc/fluent-bit/local.conf
user=appuser
autostart=true
autorestart=true
stderr_logfile=/var/log/supervisor/fluent-bit.err.log
stdout_logfile=/var/log/supervisor/fluent-bit.out.log
logfile_maxbytes=10MB
logfile_backups=3
EOF
RUN chown appuser:appuser /etc/supervisor/supervisord.conf

# Переменные окружения для настройки
ENV LOKI_RETENTION_PERIOD=720h
ENV FLUENTBIT_LOG_LEVEL=info

# Entry-point для применения переменных окружения
COPY <<EOF /entrypoint.sh
#!/bin/bash
sed -i "s/retention_period: 720h/retention_period: \$LOKI_RETENTION_PERIOD/" /etc/loki/local-config.yaml
sed -i "s/log_level trace/log_level \$FLUENTBIT_LOG_LEVEL/" /etc/fluent-bit/local.conf
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
EOF
RUN chmod +x /entrypoint.sh && chown appuser:appuser /entrypoint.sh

# Healthcheck для сервисов
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s CMD \
    curl -f http://localhost:3100/ready || exit 1 && \
    curl -f http://localhost:3000/api/health || exit 1

# Тома для персистентности
VOLUME ["/loki", "/var/lib/grafana"]

# Открытие портов
EXPOSE 3000 24224/tcp 24224/udp

# Точка входа
ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]