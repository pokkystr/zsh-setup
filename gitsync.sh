git fetch origin --prune

git tag | while read tag; do
  git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1 \
    || git tag -d "$tag"
done

git fetch origin --tags
