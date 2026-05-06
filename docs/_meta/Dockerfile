# docs/_meta/Dockerfile
#
# Adds the include-markdown + neoteroi-mkdocs plugins to the official
# mkdocs-material image so we can pull README.md / examples/*/README.md into
# the docs site and render the OpenAPI spec inline.
#
# Build (context is docs/_meta/ to avoid the repo-root .dockerignore allowlist):
#   docker build -t edge_core_docs -f docs/_meta/Dockerfile docs/_meta/
#
# Serve (live-reload on the host):
#   docker run --rm -it -p 28080:8000 -v "$PWD:/docs" -w /docs \
#     edge_core_docs serve --dev-addr 0.0.0.0:8000
FROM squidfunk/mkdocs-material:latest

COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt
