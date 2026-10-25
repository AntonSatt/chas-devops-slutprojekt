#!/usr/bin/env bash
set -eo pipefail

get() {
    echo "=== getting keys from cluster..."
    keys=$(kubectl -n kube-system get secrets -o jsonpath='{.items}' --selector sealedsecrets.bitnami.com/sealed-secrets-key)

    if [[ -f "$file" ]] && [[ "$ALSO_FORCE" != "true" ]]; then
        keys_current=$($openssl_cmd -d -in "$file")

        sorted_keys=$(jq -c 'sort_by(.metadata.name) | [.[].metadata.name]' <<< "$keys")
        sorted_current_keys=$(jq -c 'sort_by(.metadata.name) | [.[].metadata.name]' <<< "$keys_current")

        if [[ "$sorted_keys" == "$sorted_current_keys" ]]; then
            echo "=== has same keys, skipping updating"
            return 0
        fi

    fi

    $openssl_cmd <<<"$keys" -out "$file"

    echo "=== updated secrets file"

    if [[ "$ALSO_COMMIT" != "true" ]]; then
        echo "--- ALSO_COMMIT is not 'true', skipping commiting"
        return 0
    fi


    cd "$dir"

    if [[ "$ALSO_PULL" == "true" ]]; then
        echo "=== pulling..."
        git pull
    fi

    echo -e "\n=== commiting..."

    git add .
    git commit -m "sealed-secrets-keys: Updated keys $(date '+%Y-%m-%d %H:%M:%S%:z')"

    if [[ "$ALSO_PUSH" != "true" ]]; then
        echo "--- ALSO_PUSH is not 'true', skipping pushing"
        return 0
    fi

    echo -e "\n=== pushing..."
    git push
}

put() {

    if ! [[ -f "$file" ]]; then
        echo "keys file does not exist"
        exit 1
    fi

    echo "=== getting existing keys from cluster..."
    mapfile -t key_names_existing < <(kubectl -n kube-system get secrets -o jsonpath='{.items[*].metadata.name}' --selector sealedsecrets.bitnami.com/sealed-secrets-key)

    echo "=== decrypting expected keys..."
    mapfile -t keys < <($openssl_cmd -d -in "$file" | jq -c '.[]')

    echo "=== applying keys..."

    for key in "${keys[@]}"; do
        key_name="$(jq -r '.metadata.name' <<<"$key")"
        if [[ " ${key_names_existing[*]} " == *" $key_name "* ]]; then
            echo "--- skipping key: $key_name"
            continue
        fi

        echo "--- applying key: $key_name"

        echo "$key" | kubectl apply -f -
    done
}

if ! [[ -d .git ]]; then
    echo "not in root of repo"
    exit 1
fi

if [[ -z "$KUBECONFIG" ]]; then
    echo "need to explicitly set KUBECONFIG"
    exit 1
fi

if [[ -z "$SEALED_SECRETS_KEY_ENCRYPTION_PASSWORD" ]]; then
    echo "password not set via env var: SEALED_SECRETS_KEY_ENCRYPTION_PASSWORD"
    exit 1
fi

if [[ "$ALSO_PULL" == "true" ]]; then
    echo "=== pulling..."
    git pull
else
    echo "=== skipped pulling"
fi


dir=$(realpath "../devops-grupp-secrets")

if [[ "$ALSO_TEMP" == "true" ]]; then

    for i in $(git worktree list | awk '{ print $1 }'); do 
        git worktree remove "$i" --force 2> /dev/null || true
    done

    dir=$(mktemp -d -t "devops-grupp-secrets_XXXXXX")

    echo "=== using '$dir' as worktree path"
fi

file="$dir/sealed-secrets-keys.json.enc"
openssl_cmd="openssl enc -aes-256-cbc -pbkdf2 -pass env:SEALED_SECRETS_KEY_ENCRYPTION_PASSWORD"

if ! [[ -d "$dir" ]] || [[ "$ALSO_TEMP" == "true" ]]; then
    echo "=== creating worktree: $dir"
    git worktree add "$dir" secrets
else
    echo "=== skipped creating worktree: $dir"
fi


case $1 in
    "put")
        put
    ;;

    "get")
        get
    ;;
    *)
        echo "usage: $0 get|put"
        exit 1
    ;;
esac

if [[ "$ALSO_TEMP" == "true" ]]; then
    echo "=== removing temp worktree..."
    git worktree remove --force "$dir"
    rm -rf "$dir"
fi
