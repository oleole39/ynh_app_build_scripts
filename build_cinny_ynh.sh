#!/bin/bash
# 
# This script build cinny_ynh from upstream source adding path placeholder to enable YNH subdirectory install support.
# *Deps: it requires 'nvm' and appropriate node version (`nvm install xx`). 
# *Resources usage: It may use up to 1GB disk space and 5GB RAM. 
#
# Authors: @oleole39 based on @Josue-T 
# License: GPL-3.0
#---------------------------------------------------------------------------------------------------------------------

# Github variables
upstream_owner="cinnyapp"
upstream_repo="cinny"
ynh_owner="Yunohost-Apps"
ynh_repo="cinny_ynh"
perstok="" #if perstok is left empty, upload step will be skipped - https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens

# Other variables
node_version=20

set -x

# Download & extract source
last_upstream_version=$(curl --silent "https://api.github.com/repos/${upstream_owner}/${upstream_repo}/releases/latest" | grep -Po "(?<=\"tag_name\": \").*(?=\")")
build_folder="${upstream_repo}_${last_upstream_version}"
curl -LJ "https://api.github.com/repos/${upstream_owner}/${upstream_repo}/tarball/${last_upstream_version}" --output "${build_folder}.tar.gz"
mkdir "$build_folder"
tar --strip-components=1 -xvf "${build_folder}.tar.gz" -C "./${build_folder}/"

# Add path placeholder
sed -i "s/base: '\/'/base: '\/__YNH_SUBDIR_PATH__'/" "$build_folder/build.config.ts"

# Build
pushd "$build_folder"
    source ~/.nvm/nvm.sh use $node_version
    npm ci && npm run build
    mv dist "${ynh_repo}"
    zip -r "${build_folder}_ynh.zip" "${ynh_repo}"
    mv "${build_folder}_ynh.zip" "../${build_folder}_ynh.zip"
popd

# Clean
rm -r "${build_folder}"
rm "${build_folder}.tar.gz"

# Upload release - code adapted from https://github.com/Josue-T/synapse_python_build/blob/master/build_pyenv.sh
if [[ $perstok ]]; then
    
    echo "Trying to upload the release to https://github.com/${ynh_owner}/${ynh_repo}/releases/ ..."

    ynh_archive_name="${build_folder}_ynh.zip"
    sha256sumarchive=$(sha256sum "$ynh_archive_name" | cut -d' ' -f1)

    if [[ "$@" =~ "push_release" ]]
    then
        ## Make a draft release json with a markdown body
        release='"tag_name": "'$last_upstream_version'", "target_commitish": "master", "name": "'$last_upstream_version'", '
        body="Cinny prebuilt archive for cinny_ynh\\n=========\\nPlease refer to main Cinny project for the change : https://github.com/$upstream_owner/$upstream_repo/releases\\n\\nSha256sum : $sha256sumarchive"
        body=\"$body\"
        body='"body": '$body', '
        release=$release$body
        release=$release'"draft": true, "prerelease": false'
        release='{'$release'}'
        url="https://api.github.com/repos/$ynh_owner/$ynh_repo/releases"
        succ=$(curl -H "Authorization: token $perstok" --data "$release" $url)

        ## In case of success, we upload a file
        upload_generic=$(echo "$succ" | grep upload_url)
        if [[ $? -eq 0 ]]; then
            echo "Release created."
        else
            echo "Error creating release!"
            return
        fi

        # $upload_generic is like:
        # "upload_url": "https://uploads.github.com/repos/:owner/:repo/releases/:ID/assets{?name,label}",
        upload_prefix=$(echo $upload_generic | cut -d "\"" -f4 | cut -d "{" -f1)
        upload_file="$upload_prefix?name=$ynh_archive_name"

        echo "Start uploading first file"
        i=0
        upload_ok=false
        while [ $i -le 4 ]; do
            i=$((i+1))
            # Download file
            set +e
            succ=$(curl -H "Authorization: token $perstok" \
                -H "Content-Type: $(file -b --mime-type $ynh_archive_name)" \
                -H "Accept: application/vnd.github.v3+json" \
                --data-binary @$ynh_archive_name $upload_file)
            res=$?
            set -e
            if [ $res -ne 0 ]; then
                echo "Curl upload failled"
                continue
            fi
            echo "Upload done, check result"

            set +eu
            download=$(echo "$succ" | egrep -o "browser_download_url.+?")
            res=$?
            if [ $res -ne 0 ] || [ -z "$download" ]; then
                set -eu
                echo "Result upload error"
                continue
            fi
            set -eu
            echo "$download" | cut -d: -f2,3 | cut -d\" -f2
            echo "Upload OK"
            upload_ok=true
            break
        done
        
        set +x  

        if ! $upload_ok; then
            echo "Upload completely failed, exit"
            exit 1
        fi
    fi

    exit 0

else
    set +x 
    echo "Build completed but not uploaded - missing Github Token"
fi
