# infra/envs/dev

Root module that composes the modules in `infra/modules` for the dev environment.
State lives in the bucket created by `infra/bootstrap` (`envs/dev/terraform.tfstate`, native
S3 lockfile). It has no resources yet.
