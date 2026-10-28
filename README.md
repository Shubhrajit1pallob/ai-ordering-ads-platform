# Local Store AI Ordering and Ads Platform

A multi-tenant AWS platform for small local stores. Staff photograph the weekly offers, AI turns the photo into a live deals catalog, customers order for pickup, and the platform creates and tracks local ads, attributing each order to the ad that drove it.

## Setup

```sh
uv sync
uv tool install pre-commit
pre-commit install
uv run pytest
```
