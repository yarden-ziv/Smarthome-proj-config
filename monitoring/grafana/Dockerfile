FROM grafana/grafana:latest

USER root

COPY dashboards /var/lib/grafana/dashboards
COPY provisioning /etc/grafana/provisioning

# Install dos2unix and clean dashboard files
RUN apk add --no-cache dos2unix && \
    find /var/lib/grafana/dashboards -name '*.json' -exec dos2unix {} + && \
    find /var/lib/grafana/dashboards -name '*.json' -exec sed -i '1s/^\xEF\xBB\xBF//' {} +
