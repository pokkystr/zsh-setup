# Sync remote information -> local
git fetch origin --prune

# Preview local branches whose origin branch no longer exists
git branch -vv | grep ': gone]'

# Delete those LOCAL branches
#ถ้าต้องการหา local branch ที่ไม่มี remote ชื่อเดียวกัน ให้ preview ด้วย:

git for-each-ref --format='%(refname:short)' refs/heads |
while read branch; do
  git show-ref --verify --quiet "refs/remotes/origin/$branch" ||
    printf '%s\n' "$branch"
done

#เมื่อรายชื่อถูกต้องแล้ว ลบแบบปลอดภัยด้วย:
git for-each-ref --format='%(refname:short)' refs/heads |
while read branch; do
  git show-ref --verify --quiet "refs/remotes/origin/$branch" ||
    printf '%s\n' "$branch"
done |
xargs -r git branch -d

# Delete LOCAL tags that don't exist on origin
git tag | while read tag; do
  git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1 \
    || git tag -d "$tag"
done

# Fetch remote tags -> local
git fetch origin --tags
