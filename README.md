# Dokploy Docker Deploy Action

This repository contains GitHub Actions for triggering docker deployments of an application in Dokploy.

## Features

- Trigger deployment on Dokploy
- Easy integration with GitHub workflows

## Usage

To use these actions in your GitHub workflow, add the following to your `.github/workflows/deploy.yml` file:

```yaml
name: Deploy application

on:
  push:
    branches:
      - main

jobs:
  dokploy_deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: ten-thousand-hammers/dokploy-docker-deploy-action@v1
        with:
          DOKPLOY_HOST: https://dokploy.example.com
          DOKPLOY_TOKEN: ${{ secrets.DOKPLOY_AUTH_TOKEN }}
          APPLICATION_ID: ${{ vars.DOKPLOY_APPLICATION_ID }}
          DOCKER_REGISTRY: ghcr.io/example/home
          DOCKER_TAG: ${{ env.CUSTOM_TAG }}
          RELEASE_DESCRIPTION: ${{ github.event.release.body }}
```

## Private registries

Dokploy pulls the image with the credentials stored **on the application**, and
that is the only place it looks — a registry entry configured in the Dokploy UI
is not consulted for an application that deploys a prebuilt image. Supply
`REGISTRY_USERNAME` and `REGISTRY_PASSWORD` and the action writes them to every
application it deploys:

```yaml
- uses: ten-thousand-hammers/dokploy-docker-deploy-action@v1
  with:
    DOKPLOY_HOST: https://dokploy.example.com
    DOKPLOY_TOKEN: ${{ secrets.DOKPLOY_AUTH_TOKEN }}
    APPLICATION_ID: ${{ vars.DOKPLOY_APPLICATION_ID }}
    DOCKER_REGISTRY: ghcr.io/org/app
    DOCKER_TAG: 2026.9.21-1
    REGISTRY_USERNAME: ${{ secrets.REGISTRY_USERNAME }}
    REGISTRY_PASSWORD: ${{ secrets.REGISTRY_PASSWORD }}
```

`REGISTRY_URL` is optional and defaults to the host of `DOCKER_REGISTRY`
(`ghcr.io` for `ghcr.io/org/app`). The password is never printed; the log only
names the registry and the username.

Leave both unset and the registry fields are omitted from the request entirely,
so credentials already stored on the application are left alone. That matters:
Dokploy's `saveDockerProvider` is a partial update that writes every field it
receives, so sending empty strings wipes stored credentials and the next pull of
a private image fails with `denied: denied`.

## Waiting for the deployment

By default the action returns as soon as Dokploy accepts the request, so a
container that never boots still reports success. Set `WAIT: "true"` to poll
every application until its deployment reports `done`, and fail the step if any
of them errors, is cancelled, or times out.

```yaml
- uses: ten-thousand-hammers/dokploy-docker-deploy-action@v1
  with:
    DOKPLOY_HOST: https://dokploy.example.com
    DOKPLOY_TOKEN: ${{ secrets.DOKPLOY_AUTH_TOKEN }}
    APPLICATION_ID: ${{ vars.DOKPLOY_APPLICATION_ID }}
    DOCKER_REGISTRY: ghcr.io/org/app
    DOCKER_TAG: 2026.9.21-1
    RELEASE_DESCRIPTION: ${{ steps.release.outputs.changes }}
    WAIT: "true"
```

`WAIT_ATTEMPTS` (default 60) and `WAIT_INTERVAL_SECONDS` (default 10) bound how
long it waits — ten minutes by default.

Deployments are identified by snapshotting the existing deployment IDs *before*
deploying, because Dokploy's deploy endpoint does not return the deployment it
created. Without that, re-deploying the same tag would match an older,
already-successful deployment and return immediately.

With several comma-separated `APPLICATION_ID`s, every one is waited on even
after another fails, so the log shows the whole picture.
