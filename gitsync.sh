# Sync remote information -> local
git fetch origin --prune

# Preview local branches whose origin branch no longer exists
git branch -vv | grep ': gone]'

# Delete those LOCAL branches
git branch -vv | grep ': gone]' | awk '{print $1}' | xargs -r git branch -D

# Delete LOCAL tags that don't exist on origin
git tag | while read tag; do
  git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1 \
    || git tag -d "$tag"
done

# Fetch remote tags -> local
git fetch origin --tags
