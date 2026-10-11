#!/usr/bin/env bash
TF_STATE_NAME=$1
STATE_URL="https://git.chas-lab.dev/api/v4/projects/582/terraform/state"

if [[ -z "$TF_STATE_NAME" ]]; then
    echo "usage: $0 STATE_NAME"
    exit 1
fi

if ! [[ -f "main.tf" ]]; then
    echo "script needs to be ran from the terraform dir"
    exit 1
fi

cmd=""
if command -v terraform &> /dev/null; then
    cmd="terraform"
elif command -v tofu &> /dev/null; then
    cmd="tofu"
else
    echo "neither tofu or terraform is installed"
    exit 1
fi

if [[ -z "$GITLAB_ACCESS_TOKEN" ]]; then
    echo "GITLAB_ACCESS_TOKEN env var not set"
    exit 1
fi

if [[ -z "$GITLAB_USER_NAME" ]]; then
    echo "GITLAB_USER_NAME env var not set"
    exit 1
fi


$cmd init -reconfigure \
    -backend-config="address=$STATE_URL/$TF_STATE_NAME" \
    -backend-config="lock_address=$STATE_URL/$TF_STATE_NAME/lock" \
    -backend-config="unlock_address=$STATE_URL/$TF_STATE_NAME/lock" \
    -backend-config="username=$GITLAB_USER_NAME" \
    -backend-config="password=$GITLAB_ACCESS_TOKEN" \
    -backend-config="lock_method=POST" \
    -backend-config="unlock_method=DELETE" \
    -backend-config="retry_wait_min=5"
