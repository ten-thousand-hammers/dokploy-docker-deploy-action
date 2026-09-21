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
    uses: ten-thousand-hammers/dokploy-docker-deploy-actions@main
    with:
      DOKPLOY_HOST: https://dokploy.example.com
      DOKPLOY_TOKEN: ${{ secrets.DOKPLOY_AUTH_TOKEN }}
      APPLICATION_ID: ${{ env.DOKPLOY_APPLICATION_ID }}
      DOCKER_REGISTRY: ghcr.io/example/home
      DOCKER_TAG: ${{ env.CUSTOM_TAG }}
      RELEASE_DESCRIPTION: ${{ github.event.release.body }}
```

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
