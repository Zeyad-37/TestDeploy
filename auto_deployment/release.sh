#!/usr/bin/env bash

function gh_create_release {
    tag_name=$1
    body=$2
    jbody="${body//$'\n'/\n}"
    githubAPIToken=$3
    echo ${jbody}
    API_JSON="{\"tag_name\": \"$tag_name\",
                \"target_commitish\": \"master\",
                \"name\": \"$tag_name\",
                \"body\": \"$jbody\",
                \"draft\": false,
                \"prerelease\": false
              }"
    echo ${API_JSON}
    curl --data "$API_JSON" https://api.github.com/repos/Zeyad-37/TestDeploy/releases?access_token=${githubAPIToken}
}

function gh_release {
    local next_version=$1
    local filename=$2
    # Script to upload a release asset using the GitHub API v3.
    # Define variables.
    local githubAPIToken=$3
    local GH_API="https://api.github.com"
    local GH_REPO="$GH_API/repos/Zeyad-37/TestDeploy"
    local GH_TAGS="$GH_REPO/releases/tags/${next_version}"
    local AUTH="Authorization: token $githubAPIToken"
#    local WGET_ARGS="--content-disposition --auth-no-challenge --no-cookie"
    local CURL_ARGS="-LJO#"

    if [[ "${next_version}" == 'LATEST' ]]; then
      GH_TAGS="$GH_REPO/releases/latest"
    fi

    # Validate token.
    curl -o /dev/null -sH "$AUTH" ${GH_REPO} || { echo "Error: Invalid repo, token or network issue!";  exit 1; }

    # Read asset tags.
    response=$(curl -sH "$AUTH" ${GH_TAGS})

    # Get ID of the asset based on given filename.
    eval $(echo "$response" | grep -m 1 "id.:" | grep -w id | tr : = | tr -cd '[[:alnum:]]=')
    [[ "$id" ]] || { echo "Error: Failed to get release id for tag: ${next_version}"; echo "$response" | awk 'length($0)<100' >&2; exit 1; }

    # Upload asset
    echo "Uploading asset... "

    # Construct url
    GH_ASSET="https://uploads.github.com/repos/Zeyad-37/TestDeploy/releases/$id/assets?name=$(basename ${filename})"

    curl --data-binary @"$filename" -H "Authorization: token $githubAPIToken" -H "Content-Type: application/octet-stream" ${GH_ASSET}
}

function format_to_gradle {
    local version=(${1})
    local delimiter=", "
    local temp="${version/./$delimiter}"

    local result="${temp/./$delimiter}"
    echo ${result}
}

# Accepts a version string and prints it incremented by one.
# Usage: increment_version <version> [<position>] [<leftmost>]
increment_version() {
   local usage=" USAGE: $FUNCNAME [-l] [-t] <version> [<position>] [<leftmost>]
           -l : remove leading zeros
           -t : drop trailing zeros
    <version> : The version string.
   <position> : Optional. The position (starting with one) of the number
                within <version> to increment.  If the position does not
                exist, it will be created.  Defaults to last position.
   <leftmost> : The leftmost position that can be incremented.  If does not
                exist, position will be created.  This right-padding will
                occur even to right of <position>, unless passed the -t flag."
   # Get flags.
   local flag_remove_leading_zeros=0
   local flag_drop_trailing_zeros=0
   while [[ "${1:0:1}" == "-" ]]; do
      if [[ "$1" == "--" ]]; then shift; break
      elif [[ "$1" == "-l" ]]; then flag_remove_leading_zeros=1
      elif [[ "$1" == "-t" ]]; then flag_drop_trailing_zeros=1
      else echo -e "Invalid flag: ${1}\n$usage"; return 1; fi
      shift; done

   # Get arguments.
   if [[ ${#@} -lt 1 ]]; then echo "$usage"; return 1; fi
   local v="${1}"             # version string
   local targetPos=${2-last}  # target position
   local minPos=${3-${2-0}}   # minimum position

   # Split version string into array using its periods.
   local IFSbak; IFSbak=IFS; IFS='.' # IFS restored at end of func to
   read -ra v <<< "$v"               #  avoid breaking other scripts.

   # Determine target position.
   if [[ "${targetPos}" == "last" ]]; then
      if [[ "${minPos}" == "last" ]]; then minPos=0; fi
      targetPos=$((${#v[@]}>${minPos}?${#v[@]}:$minPos)); fi
   if [[ ! ${targetPos} -gt 0 ]]; then
      echo -e "Invalid position: '$targetPos'\n$usage"; return 1; fi
   (( targetPos--  )) || true # offset to match array index

   # Make sure minPosition exists.
   while [[ ${#v[@]} -lt ${minPos} ]]; do v+=("0"); done;

   # Increment target position.
   v[$targetPos]=`printf %0${#v[$targetPos]}d $((10#${v[$targetPos]}+1))`;

   # Remove leading zeros, if -l flag passed.
   if [[ ${flag_remove_leading_zeros} == 1 ]]; then
      for (( pos=0; $pos<${#v[@]}; pos++ )); do
         v[$pos]=$((${v[$pos]}*1)); done; fi

   # If targetPosition was not at end of array, reset following positions to
   #   zero (or remove them if -t flag was passed).
   if [[ ${flag_drop_trailing_zeros} -eq "1" ]]; then
        for (( p=$((${#v[@]}-1)); $p>$targetPos; p-- )); do unset v[$p]; done
   else for (( p=$((${#v[@]}-1)); $p>$targetPos; p-- )); do v[$p]=0; done; fi

   echo "${v[*]}"
   IFS=IFSbak

   return 0
}

function checkFileValidity() {
    file=$1
    if [[ ! -e ${file} ]]; then
        touch ${file}
    fi

    if ! [[ -s ${file} ]]
    then
        echo 'Release Notes are empty, you can fill them at '${file}
        exit 1
    fi

    tags=$(git log -n 1 --pretty=format:%H -- ${file} | git tag --contains)
    arr=(${tags})
    len=${#arr[@]}
    if [[ ${len} > 0 ]];then
        index=${len}-1
        release_notes_tag=${arr[${index}]}
        current_tag=$(git describe --tags $(git rev-list --tags --max-count=1))
        if [[ ${current_tag} == ${release_notes_tag} ]];then
            echo 'Release Notes are stale, you can update them at '${file}
            exit 1
        fi
    fi

    echo 'Release Notes seem valid, beginning the release process'
}

release_type=$1
if [[ release_type -gt "4" || release_type -lt "1" ]]
then
    echo 'Unsupported Release type: ' ${release_type}
    exit 1
fi

bump_location=${release_type}
if [[ release_type == "4" ]]
then
    bump_location=3
fi

checkFileValidity ./auto_deployment/release_notes.txt
checkFileValidity ./auto_deployment/tech_release_notes.txt

# ensure you are on latest develop & master
git checkout master
git pull origin master
git checkout develop
git pull origin develop
echo "Got latest of develop and master"

# Read Version -
current_version=$(git describe --tags $(git rev-list --tags --max-count=1))
echo Current version ${current_version}
# Bump released version
next_version=$(increment_version ${current_version} ${bump_location})
echo "Releasing new version ${next_version}"

branch_prefix='release'
source_branch='develop'
# Start Release
if [[ "$release_type" == "4" ]]; then
    branch_prefix='hotfix'
    source_branch='master'
fi

branch_name=${branch_prefix}/${next_version}

echo "branch_name=${branch_name}"

git checkout -b ${branch_name} ${source_branch}
echo "Created ${branch_prefix} branch '${branch_name}'"

# Bump in gradle file
old_gradle_version=$(format_to_gradle ${current_version})
new_gradle_version=$(format_to_gradle ${next_version})

echo "old_gradle_version= ${old_gradle_version}"
echo "new_gradle_version= ${new_gradle_version}"

sed -i '' -e "s/${old_gradle_version}/${new_gradle_version}/g" ./app/build.gradle

# Commit
git add app/build.gradle
git commit -m "Bumps version to ${next_version}"
echo "Bumped version in app build.gradle file to ${next_version}"

# Merge to master and develop
git checkout master
git merge --no-ff --no-edit ${branch_name}
git tag -a ${next_version} -m "${next_version}"
git checkout develop
git merge --no-ff --no-edit ${branch_name}
echo "Merged to master and develop and created tag"
# Delete branch
git branch -d ${branch_name}
echo "Deleted ${branch_prefix} branch '${branch_name}'"
# Push develop, master and tag to origin
git push origin develop
git push origin master
git push origin ${next_version}
echo "Pushed develop, master and tag to origin"

# Build APK
./gradlew assembleRelease

# Make Release for Github

tech_release_notes=$(cat ./auto_deployment/tech_release_notes.txt)
gh_create_release ${next_version} "${tech_release_notes}" $2

# Upload Release asset
file=$(find app/build/outputs/apk/release -name '*.apk' -print0 |
            xargs -0 ls -1 -t |
            head -1)
gh_release ${next_version} ${file} $2
