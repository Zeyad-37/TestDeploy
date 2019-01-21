#!/usr/bin/env bash

function format_to_gradle {
    version=(${1})
    delimiter=", "
    temp="${version/./$delimiter}"

    result="${temp/./$delimiter}"
    echo ${result}
}

# ensure you are on latest develop & master
git checkout master
git pull origin master
git checkout develop
git pull origin develop
echo "Got latest of develop and master"

# Read Version -
VERSION=$(git describe --tags $(git rev-list --tags --max-count=1))

echo "Current version ${VERSION}"

echo "Enter 1 for major, 2 for minor or 3 for patch bump"
read bumpLocation

# Bump released version
NEXTVERSION=`./auto_deployment/increment-version.sh ${VERSION} ${bumpLocation}`
echo "Releasing new version ${NEXTVERSION}"

branchPrefix='release'
# Start Release
if [[ "$bumpLocation" == "3" ]]; then
    branchPrefix='hotfix'
fi

branchName=${branchPrefix}/${NEXTVERSION}

echo branchName= ${branchName}

git checkout -b ${branchName} develop
echo "Created ${branchPrefix} branch '${branchName}'"

# Bump in gradle file
oldGradleVersion=$(format_to_gradle ${VERSION})
newGradleVersion=$(format_to_gradle ${NEXTVERSION})

echo oldGradleVersion= ${oldGradleVersion}
echo newGradleVersion= ${newGradleVersion}

sed -i '' -e "s/${oldGradleVersion}/${newGradleVersion}/g" ./app/build.gradle

# Commit
git commit -m "Bumps version to ${NEXTVERSION}"
echo "Bumped version in app build.gradle file to ${NEXTVERSION}"

# Merge to master and develop
git checkout master
git merge --no-ff ${branchName}
git tag -a ${NEXTVERSION}
git checkout develop
git merge --no-ff ${branchName}
echo "Merged to master and develop and created tag"
# Delete branch
git branch -d ${branchName}
echo "Deleted ${branchPrefix} branch '${branchName}'"
# Push develop, master and tag to origin
git push origin develop && git push origin master --tags
echo "Pushed develop, master and tag to origin"

