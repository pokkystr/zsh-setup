#!/bin/bash

set -e

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Error: Not inside a Git repository"
    exit 1
fi

echo "Fetching tags..."
git fetch --tags --quiet

TAG=$(git tag --list '[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | head -1)

if [ -z "$TAG" ]; then
    NEW_TAG="0.0.1"
else
    NEW_TAG=$(echo "$TAG" | awk -F. '{print $1"."$2"."$3+1}')
fi

echo "$TAG -> $NEW_TAG"

git tag "$NEW_TAG"

echo "Created tag: $NEW_TAG"
