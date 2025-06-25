# deploy/local/compose/edge_metrics_collector/Dockerfile
FROM victoriametrics/vmagent:v1.120.0

COPY ./deploy/local/compose/edge_metrics_collector/entrypoint /entrypoint
RUN sed -i 's/\r$//g' /entrypoint
RUN chmod +x /entrypoint

ENTRYPOINT ["/entrypoint"]
