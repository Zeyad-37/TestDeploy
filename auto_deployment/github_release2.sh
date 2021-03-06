#!/usr/bin/env bash

githubAPIToken="29a1b2fb32f1208aa9790e21fe51c059467f32c6"

function gh_create_release() {
    tag_name=$1
    body=$2

    API_JSON="{\"tag_name\": \"$tag_name\",
                \"target_commitish\": \"master\",
                \"name\": \"$tag_name\",
                \"body\": \"$body\",
                \"draft\": false,
                \"prerelease\": false
              }"

    curl --data "$API_JSON" https://api.github.com/repos/Glovo/glovo-courier-android/releases?access_token=${githubAPIToken}
}

function gh_upload_release_asset {
    local next_version=$1
    local filename=$2
    # Script to upload a release asset using the GitHub API v3.
    # Define variables.
    local GH_API="https://api.github.com"
    local GH_REPO="$GH_API/repos/Glovo/glovo-courier-android"
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
    GH_ASSET="https://uploads.github.com/repos/Glovo/glovo-courier-android/releases/$id/assets?name=$(basename ${filename})"

    curl --data-binary @"$filename" -H "Authorization: token $githubAPIToken" -H "Content-Type: application/octet-stream" ${GH_ASSET}
}

current_version=$(git describe --tags $(git rev-list --tags --max-count=1))
current_version=1.14.0
releaseNotes="Testing this shit"
file=$(find app/build/outputs/apk/release -name '*.apk' -print0 |
            xargs -0 ls -1 -t |
            head -1)

gh_create_release ${current_version} ${releaseNotes}
gh_upload_release_asset ${current_version} ${file}