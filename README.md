# Edge Core

The core to manage edge computing infrastructure

## Basic Commands

### Installation

- Make sure you have `docker` and `docker compose` installed:

    ```sh
    docker  --version
    docker compose version
    ```

- Spin up development servers (developing on `WSl` or `Linux` is recommended):

    ```sh
    docker compose -f deploy/local/web.yml up --build --remove-orphans
    ```
