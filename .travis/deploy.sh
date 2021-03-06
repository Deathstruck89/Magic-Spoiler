#!/bin/bash
set -e # Exit with nonzero exit code if anything fails

SOURCE_BRANCH="master"
TARGET_BRANCH="files"

function doCompile {
    echo "Running script..."
    python main.py
}

# Pull requests and commits to other branches shouldn't try to deploy, just build to verify
if [ "$TRAVIS_PULL_REQUEST" != "false" -o "$TRAVIS_BRANCH" != "$SOURCE_BRANCH" ]; then
    echo "Skipping deploy; just doing a build."
    # Run our compile script and let user know in logs
    doCompile
    exit 0
fi

# Save some useful information
REPO=`git config remote.origin.url`
SSH_REPO=${REPO/https:\/\/github.com\//git@github.com:}
SHA=`git rev-parse --verify HEAD`

# Clone the existing gh-pages for this repo into out/
# Create a new empty branch if gh-pages doesn't exist yet (should only happen on first deply)
git clone $REPO out
cd out
git checkout $TARGET_BRANCH || git checkout --orphan $TARGET_BRANCH
cd ..

# Clean out existing contents
rm -rf out/**/* || exit 0

# Run our compile script and let user know in logs
doCompile

echo TRAVIS_PULL_REQUEST ${TRAVIS_PULL_REQUEST}
echo TRAVIS_SECURE_ENV_VARS ${TRAVIS_SECURE_ENV_VARS}
echo TRAVIS_EVENT_TYPE ${TRAVIS_EVENT_TYPE}

# Don't push to our branch for PRs.
#if [ "${ghToken:-false}" != "false" ]; then
#    doCompile
#else
#    doCompile
#    exit 0
#fi

# Now let's go have some fun with the cloned repo
cd out
ls
git config user.name "Travis CI"
git config user.email "$COMMIT_AUTHOR_EMAIL"

# If there are no changes to the compiled out (e.g. this is a README update) then just bail.
#if git diff --quiet; then
#    echo "No changes to the output on this push; exiting."
#    exit 0
#fi

# Commit the "changes", i.e. the new version.
# The delta will show diffs between new and old versions.
# Only commit if more than one line has been changed (datetime in spoiler.xml)
CHANGED_FILES=`git diff --numstat --minimal | sed '/^[1-]\s\+[1-]\s\+.*/d' | wc -c`
ONLYDATECHANGE=true
if [[ $CHANGED_FILES -eq 0 ]]; then
  for CHANGED_FILE in `git diff --name-only`; do
    if ! [[ $CHANGED_FILE =~ "spoiler.xml" ]]; then
      ONLYDATECHANGE=false
    fi
  done
else
  ONLYDATECHANGE=false
fi
if [[ $ONLYDATECHANGE == false ]]; then
  git add -A .
  git commit -m "Travis Deploy: ${SHA}"
else
  echo "Only date in spoiler.xml changed, not committing"
fi

# Get the deploy key by using Travis's stored variables to decrypt deploy_key.enc
ENCRYPTED_KEY_VAR="encrypted_${ENCRYPTION_LABEL}_key"
ENCRYPTED_IV_VAR="encrypted_${ENCRYPTION_LABEL}_iv"
ENCRYPTED_KEY=${!ENCRYPTED_KEY_VAR}
ENCRYPTED_IV=${!ENCRYPTED_IV_VAR}
openssl aes-256-cbc -K $ENCRYPTED_KEY -iv $ENCRYPTED_IV -in ../.travis/deploy_key.enc -out ../deploy_key -d
chmod 600 ../deploy_key
eval `ssh-agent -s`
ssh-add ../deploy_key

# Now that we're all set up, we can push.
git push $SSH_REPO $TARGET_BRANCH

ssh-agent -k
