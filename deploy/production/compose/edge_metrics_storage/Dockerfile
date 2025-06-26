# deploy/production/compose/edge_metrics_storage/Dockerfile
FROM victoriametrics/victoria-metrics:v1.120.0

COPY ./deploy/production/compose/edge_metrics_storage/entrypoint /entrypoint
RUN sed -i 's/\r$//g' /entrypoint
RUN chmod +x /entrypoint

ENTRYPOINT ["/entrypoint"]
