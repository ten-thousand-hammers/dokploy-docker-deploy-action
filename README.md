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
